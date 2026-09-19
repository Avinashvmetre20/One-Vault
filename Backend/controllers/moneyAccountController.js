import { pool } from "../config/db.js";
import { ensureDefaultMoneyData } from "../db/finance.js";
import {
  asBoolean,
  fail,
  ok,
  parseId,
  pick,
} from "../utils/planner.js";
import { requestTimeZone } from "../utils/time.js";
import {
  loadAccount,
  loadCard,
  mapAccount,
  mapCard,
  monthBounds,
  parseAccountInput,
  parseCardInput,
  formatMoney,
  refreshAccountBalance,
  refreshCardOutstanding,
  withTx,
} from "../utils/finance.js";

const userId = (req) => req.user.user_id;

const accountHasTransactions = async (accountId, authUserId) => {
  const result = await pool.query(
    `SELECT 1
     FROM money_transactions
     WHERE user_id = $2
       AND deleted_at IS NULL
       AND (account_id = $1 OR counterparty_account_id = $1)
     LIMIT 1`,
    [accountId, authUserId]
  );
  return result.rowCount > 0;
};

const cardHasTransactions = async (cardId, authUserId) => {
  const result = await pool.query(
    `SELECT 1
     FROM money_transactions
     WHERE user_id = $2 AND deleted_at IS NULL AND card_id = $1
     LIMIT 1`,
    [cardId, authUserId]
  );
  return result.rowCount > 0;
};

export const listAccounts = async (req, res) => {
  try {
    await ensureDefaultMoneyData(userId(req));
    const includeInactive = asBoolean(req.query.includeInactive ?? req.query.include_inactive, false);
    const result = await pool.query(
      `SELECT account_id, user_id, name, institution_name, account_kind, bank_account_type,
              last_four_digits, opening_balance, current_balance, currency, notes, is_active,
              created_at, updated_at
       FROM money_accounts
       WHERE user_id = $1 ${includeInactive ? "" : "AND is_active = TRUE"}
       ORDER BY account_kind ASC, name ASC`,
      [userId(req)]
    );
    return ok(res, { accounts: result.rows.map(mapAccount) });
  } catch (error) {
    console.error("List money accounts error:", error);
    return fail(res, 500, "Could not load accounts");
  }
};

export const getAccount = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid account id");
    const account = await loadAccount(pool, id, userId(req));
    if (!account) return fail(res, 404, "Account not found", "ACCOUNT_NOT_FOUND");

    const tz = await requestTimeZone(req);
    const bounds = await monthBounds(pool, tz);
    const month = await pool.query(
      `SELECT
         COALESCE(SUM(t.amount) FILTER (
           WHERE t.transaction_type = 'income' AND t.account_id = $1
         ), 0) AS income,
         COALESCE(SUM(t.amount) FILTER (
           WHERE t.transaction_type IN ('expense', 'card_purchase') AND t.account_id = $1
         ), 0) AS expense,
         COALESCE(SUM(t.amount) FILTER (
           WHERE t.transaction_type IN ('transfer', 'cash_withdrawal', 'cash_deposit')
             AND (t.account_id = $1 OR t.counterparty_account_id = $1)
         ), 0) AS transfers
       FROM money_transactions t
       WHERE t.user_id = $2 AND t.deleted_at IS NULL
         AND t.occurred_at >= $3 AND t.occurred_at < $4`,
      [id, userId(req), bounds.startAt, bounds.endAt]
    );

    return ok(res, {
      account: mapAccount(account),
      thisMonth: {
        income: formatMoney(month.rows[0].income),
        expense: formatMoney(month.rows[0].expense),
        transfers: formatMoney(month.rows[0].transfers),
      },
    });
  } catch (error) {
    console.error("Get money account error:", error);
    return fail(res, 500, "Could not load account");
  }
};

export const createAccount = async (req, res) => {
  try {
    const input = parseAccountInput(req.body);
    if (input.error) return fail(res, 400, input.error, "VALIDATION_ERROR");

    const opening = input.openingBalance ?? "0.00";
    const created = await pool.query(
      `INSERT INTO money_accounts (
         user_id, name, institution_name, account_kind, bank_account_type,
         last_four_digits, opening_balance, current_balance, currency, notes
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8, $9)
       RETURNING account_id, user_id, name, institution_name, account_kind, bank_account_type,
                 last_four_digits, opening_balance, current_balance, currency, notes, is_active,
                 created_at, updated_at`,
      [
        userId(req),
        input.name,
        input.institutionName || "",
        input.accountKind,
        input.bankAccountType,
        input.lastFourDigits,
        opening,
        input.currency,
        input.notes || "",
      ]
    );
    return ok(res, { account: mapAccount(created.rows[0]) }, { status: 201, message: "Account created" });
  } catch (error) {
    console.error("Create money account error:", error);
    return fail(res, 500, "Could not create account");
  }
};

export const updateAccount = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid account id");
    const input = parseAccountInput(req.body, { partial: true });
    if (input.error) return fail(res, 400, input.error, "VALIDATION_ERROR");

    const updated = await withTx(async (client) => {
      const existing = await loadAccount(client, id, userId(req));
      if (!existing) return null;

      const name = input.name || existing.name;
      const institution = input.institutionName ?? existing.institution_name;
      const kind = input.accountKind || existing.account_kind;
      const bankType = kind === "cash" ? null : (input.bankAccountType ?? existing.bank_account_type);
      const lastFour = kind === "cash" ? null : (input.lastFourDigits === undefined ? existing.last_four_digits : input.lastFourDigits);
      const opening = input.openingBalance ?? existing.opening_balance;
      const notes = input.notes ?? existing.notes;
      const currency = input.currency || existing.currency;

      const result = await client.query(
        `UPDATE money_accounts
         SET name = $1, institution_name = $2, account_kind = $3, bank_account_type = $4,
             last_four_digits = $5, opening_balance = $6, notes = $7, currency = $8, updated_at = NOW()
         WHERE account_id = $9 AND user_id = $10
         RETURNING account_id`,
        [name, institution, kind, bankType, lastFour, opening, notes, currency, id, userId(req)]
      );
      if (!result.rowCount) return null;
      await refreshAccountBalance(client, id, userId(req));
      return loadAccount(client, id, userId(req));
    });

    if (!updated) return fail(res, 404, "Account not found", "ACCOUNT_NOT_FOUND");
    return ok(res, { account: mapAccount(updated) }, { message: "Account updated" });
  } catch (error) {
    console.error("Update money account error:", error);
    return fail(res, 500, "Could not update account");
  }
};

export const archiveAccount = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid account id");
    const restore = asBoolean(pick(req.body, "restore"), false);

    const updated = await pool.query(
      `UPDATE money_accounts
       SET is_active = $3, updated_at = NOW()
       WHERE account_id = $1 AND user_id = $2
       RETURNING account_id, user_id, name, institution_name, account_kind, bank_account_type,
                 last_four_digits, opening_balance, current_balance, currency, notes, is_active,
                 created_at, updated_at`,
      [id, userId(req), restore]
    );
    if (!updated.rowCount) return fail(res, 404, "Account not found", "ACCOUNT_NOT_FOUND");
    return ok(res, { account: mapAccount(updated.rows[0]) }, {
      message: restore ? "Account restored" : "Account archived",
    });
  } catch (error) {
    console.error("Archive money account error:", error);
    return fail(res, 500, "Could not update account");
  }
};

export const deleteAccount = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid account id");
    if (await accountHasTransactions(id, userId(req))) {
      return fail(res, 409, "Archive this account instead. It has transaction history.", "ACCOUNT_HAS_TRANSACTIONS");
    }
    const deleted = await pool.query(
      `DELETE FROM money_accounts WHERE account_id = $1 AND user_id = $2 RETURNING account_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Account not found", "ACCOUNT_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Account deleted" });
  } catch (error) {
    console.error("Delete money account error:", error);
    return fail(res, 500, "Could not delete account");
  }
};

export const listCards = async (req, res) => {
  try {
    const includeInactive = asBoolean(req.query.includeInactive ?? req.query.include_inactive, false);
    const type = String(req.query.type || "").toLowerCase();
    const filters = ["c.user_id = $1"];
    const params = [userId(req)];
    if (!includeInactive) filters.push("c.is_active = TRUE");
    if (type === "debit" || type === "credit") {
      params.push(type);
      filters.push(`c.card_type = $${params.length}`);
    }
    const result = await pool.query(
      `SELECT c.card_id, c.user_id, c.name, c.card_type, c.issuer_name, c.last_four_digits,
              c.linked_account_id, c.credit_limit, c.opening_outstanding, c.current_outstanding,
              CASE
                WHEN c.card_type = 'credit' AND c.credit_limit IS NOT NULL
                  THEN c.credit_limit - c.current_outstanding
                ELSE NULL
              END AS available_credit,
              c.statement_day, c.due_day, c.minimum_due, c.notes, c.is_active,
              c.created_at, c.updated_at,
              a.name AS linked_account_name, a.last_four_digits AS linked_account_last_four
       FROM money_cards c
       LEFT JOIN money_accounts a ON a.account_id = c.linked_account_id
       WHERE ${filters.join(" AND ")}
       ORDER BY c.card_type ASC, c.name ASC`,
      params
    );
    return ok(res, { cards: result.rows.map(mapCard) });
  } catch (error) {
    console.error("List money cards error:", error);
    return fail(res, 500, "Could not load cards");
  }
};

export const getCard = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid card id");
    const card = await loadCard(pool, id, userId(req));
    if (!card) return fail(res, 404, "Card not found", "CARD_NOT_FOUND");
    return ok(res, { card: mapCard(card) });
  } catch (error) {
    console.error("Get money card error:", error);
    return fail(res, 500, "Could not load card");
  }
};

export const createCard = async (req, res) => {
  try {
    const input = parseCardInput(req.body);
    if (input.error) return fail(res, 400, input.error, "VALIDATION_ERROR");
    if (input.cardType === "credit" && !input.creditLimit) {
      return fail(res, 400, "Credit limit is required for credit cards", "VALIDATION_ERROR");
    }
    if (input.linkedAccountId) {
      const linked = await loadAccount(pool, input.linkedAccountId, userId(req));
      if (!linked) return fail(res, 400, "Linked account not found", "ACCOUNT_NOT_FOUND");
    }

    const opening = input.openingOutstanding ?? "0.00";
    const created = await pool.query(
      `INSERT INTO money_cards (
         user_id, name, card_type, issuer_name, last_four_digits, linked_account_id,
         credit_limit, opening_outstanding, current_outstanding, statement_day, due_day,
         minimum_due, notes
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$8,$9,$10,$11,$12)
       RETURNING card_id`,
      [
        userId(req),
        input.name,
        input.cardType,
        input.issuerName || "",
        input.lastFourDigits,
        input.linkedAccountId ?? null,
        input.creditLimit,
        opening,
        input.statementDay,
        input.dueDay,
        input.minimumDue,
        input.notes || "",
      ]
    );
    const card = await loadCard(pool, created.rows[0].card_id, userId(req));
    return ok(res, { card: mapCard(card) }, { status: 201, message: "Card created" });
  } catch (error) {
    console.error("Create money card error:", error);
    return fail(res, 500, "Could not create card");
  }
};

export const updateCard = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid card id");
    const input = parseCardInput(req.body, { partial: true });
    if (input.error) return fail(res, 400, input.error, "VALIDATION_ERROR");

    const updated = await withTx(async (client) => {
      const existing = await loadCard(client, id, userId(req));
      if (!existing) return null;
      const cardType = input.cardType || existing.card_type;
      const linkedId = input.linkedAccountId === undefined ? existing.linked_account_id : input.linkedAccountId;
      if (linkedId) {
        const linked = await loadAccount(client, linkedId, userId(req));
        if (!linked) throw Object.assign(new Error("Linked account not found"), { status: 400 });
      }
      await client.query(
        `UPDATE money_cards
         SET name = $1, card_type = $2, issuer_name = $3, last_four_digits = $4,
             linked_account_id = $5, credit_limit = $6, opening_outstanding = $7,
             statement_day = $8, due_day = $9, minimum_due = $10, notes = $11, updated_at = NOW()
         WHERE card_id = $12 AND user_id = $13`,
        [
          input.name || existing.name,
          cardType,
          input.issuerName ?? existing.issuer_name,
          input.lastFourDigits === undefined ? existing.last_four_digits : input.lastFourDigits,
          linkedId,
          cardType === "debit" ? null : (input.creditLimit ?? existing.credit_limit),
          cardType === "debit" ? "0.00" : (input.openingOutstanding ?? existing.opening_outstanding),
          cardType === "debit" ? null : (input.statementDay === undefined ? existing.statement_day : input.statementDay),
          cardType === "debit" ? null : (input.dueDay === undefined ? existing.due_day : input.dueDay),
          cardType === "debit" ? null : (input.minimumDue === undefined ? existing.minimum_due : input.minimumDue),
          input.notes ?? existing.notes,
          id,
          userId(req),
        ]
      );
      await refreshCardOutstanding(client, id, userId(req));
      return loadCard(client, id, userId(req));
    });

    if (!updated) return fail(res, 404, "Card not found", "CARD_NOT_FOUND");
    return ok(res, { card: mapCard(updated) }, { message: "Card updated" });
  } catch (error) {
    if (error.status === 400) return fail(res, 400, error.message, "VALIDATION_ERROR");
    console.error("Update money card error:", error);
    return fail(res, 500, "Could not update card");
  }
};

export const archiveCard = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid card id");
    const restore = asBoolean(pick(req.body, "restore"), false);
    const result = await pool.query(
      `UPDATE money_cards
       SET is_active = $3, updated_at = NOW()
       WHERE card_id = $1 AND user_id = $2
       RETURNING card_id`,
      [id, userId(req), restore]
    );
    if (!result.rowCount) return fail(res, 404, "Card not found", "CARD_NOT_FOUND");
    const card = await loadCard(pool, id, userId(req));
    return ok(res, { card: mapCard(card) }, { message: restore ? "Card restored" : "Card archived" });
  } catch (error) {
    console.error("Archive money card error:", error);
    return fail(res, 500, "Could not update card");
  }
};

export const deleteCard = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid card id");
    if (await cardHasTransactions(id, userId(req))) {
      return fail(res, 409, "Archive this card instead. It has transaction history.", "CARD_HAS_TRANSACTIONS");
    }
    const deleted = await pool.query(
      `DELETE FROM money_cards WHERE card_id = $1 AND user_id = $2 RETURNING card_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Card not found", "CARD_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Card deleted" });
  } catch (error) {
    console.error("Delete money card error:", error);
    return fail(res, 500, "Could not delete card");
  }
};
