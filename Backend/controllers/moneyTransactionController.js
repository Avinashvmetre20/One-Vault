import { pool } from "../config/db.js";
import { ensureDefaultMoneyData } from "../db/finance.js";
import {
  asDate,
  asDateTime,
  clampText,
  fail,
  ok,
  parseId,
  pick,
} from "../utils/planner.js";
import { requestTimeZone } from "../utils/time.js";
import {
  TXN_DETAIL_COLUMNS,
  TXN_JOINS,
  TXN_LIST_COLUMNS,
  asPositiveMoney,
  asTransactionType,
  formatMoney,
  loadAccount,
  loadCard,
  mapCategory,
  mapTransactionDetail,
  mapTransactionList,
  monthBounds,
  refreshLedger,
  withTx,
} from "../utils/finance.js";

const userId = (req) => req.user.user_id;

const TRANSFER_TYPES = new Set(["transfer", "cash_withdrawal", "cash_deposit"]);

const loadTransaction = async (client, id, authUserId, { detail = false } = {}) => {
  const columns = detail ? TXN_DETAIL_COLUMNS : TXN_LIST_COLUMNS;
  const result = await client.query(
    `SELECT ${columns}
     ${TXN_JOINS}
     WHERE t.transaction_id = $1 AND t.user_id = $2 AND t.deleted_at IS NULL`,
    [id, authUserId]
  );
  return result.rows[0] || null;
};

const classifyTransfer = (fromKind, toKind, type) => {
  if (type && type !== "transfer") return type;
  if (fromKind === "bank" && toKind === "cash") return "cash_withdrawal";
  if (fromKind === "cash" && toKind === "bank") return "cash_deposit";
  return "transfer";
};

const parseTxnInput = async (client, body, authUserId, { partial = false } = {}) => {
  const type = asTransactionType(pick(body, "transactionType", "transaction_type", "type"));
  if (!partial && !type) return { error: "Transaction type is required" };
  if (pick(body, "transactionType", "transaction_type", "type") && !type) {
    return { error: "Invalid transaction type" };
  }

  const title = clampText(pick(body, "title"), { required: !partial, max: 200 });
  if (title.error) return { error: title.error };

  const amount = asPositiveMoney(pick(body, "amount"), { required: !partial });
  if (amount === undefined) return { error: "Amount must be greater than 0" };

  const occurredAt = asDateTime(pick(body, "occurredAt", "occurred_at", "date", "transactionDate"));
  if (occurredAt === undefined) return { error: "Invalid date" };

  const merchant = clampText(pick(body, "merchantName", "merchant_name", "merchant"), { max: 200 });
  if (merchant.error) return { error: merchant.error };
  const description = clampText(pick(body, "description", "notes"), { max: 2000 });
  if (description.error) return { error: description.error };
  const paymentMethod = clampText(pick(body, "paymentMethod", "payment_method"), { max: 40 });
  if (paymentMethod.error) return { error: paymentMethod.error };

  const categoryIdRaw = pick(body, "categoryId", "category_id");
  let categoryId;
  if (categoryIdRaw === undefined) categoryId = undefined;
  else if (categoryIdRaw === null || categoryIdRaw === "") categoryId = null;
  else {
    categoryId = parseId(categoryIdRaw);
    if (!categoryId) return { error: "Invalid category" };
    const cat = await client.query(
      `SELECT category_id FROM money_categories WHERE category_id = $1 AND user_id = $2 AND is_active = TRUE`,
      [categoryId, authUserId]
    );
    if (!cat.rowCount) return { error: "Category not found" };
  }

  const accountIdRaw = pick(body, "accountId", "account_id", "fromAccountId", "from_account_id");
  let accountId;
  if (accountIdRaw === undefined) accountId = undefined;
  else if (accountIdRaw === null || accountIdRaw === "") accountId = null;
  else {
    accountId = parseId(accountIdRaw);
    if (!accountId) return { error: "Invalid account" };
  }

  const toRaw = pick(body, "counterpartyAccountId", "counterparty_account_id", "toAccountId", "to_account_id");
  let toAccountId;
  if (toRaw === undefined) toAccountId = undefined;
  else if (toRaw === null || toRaw === "") toAccountId = null;
  else {
    toAccountId = parseId(toRaw);
    if (!toAccountId) return { error: "Invalid destination account" };
  }

  const cardRaw = pick(body, "cardId", "card_id");
  let cardId;
  if (cardRaw === undefined) cardId = undefined;
  else if (cardRaw === null || cardRaw === "") cardId = null;
  else {
    cardId = parseId(cardRaw);
    if (!cardId) return { error: "Invalid card" };
  }

  const linkedRaw = pick(body, "linkedTransactionId", "linked_transaction_id");
  let linkedTransactionId;
  if (linkedRaw === undefined) linkedTransactionId = undefined;
  else if (linkedRaw === null || linkedRaw === "") linkedTransactionId = null;
  else {
    linkedTransactionId = parseId(linkedRaw);
    if (!linkedTransactionId) return { error: "Invalid linked transaction" };
  }

  const clientTransactionId = clampText(pick(body, "clientTransactionId", "client_transaction_id"), {
    max: 80,
  });
  if (clientTransactionId.error) return { error: clientTransactionId.error };

  return {
    type,
    title: title.value,
    amount,
    occurredAt,
    merchantName: merchant.value,
    description: description.value,
    paymentMethod: paymentMethod.value,
    categoryId,
    accountId,
    toAccountId,
    cardId,
    linkedTransactionId,
    clientTransactionId: clientTransactionId.value || null,
  };
};

const resolveTxnAccounts = async (client, input, authUserId) => {
  const type = input.type;
  let accountId = input.accountId ?? null;
  let toAccountId = input.toAccountId ?? null;
  let cardId = input.cardId ?? null;
  let from = null;
  let to = null;
  let card = null;

  if (cardId) {
    card = await loadCard(client, cardId, authUserId);
    if (!card) return { error: "Card not found" };
    if (!card.is_active) return { error: "This card is archived" };
  }
  if (accountId) {
    from = await loadAccount(client, accountId, authUserId);
    if (!from) return { error: "Account not found" };
    if (!from.is_active) return { error: "This account is archived" };
  }
  if (toAccountId) {
    to = await loadAccount(client, toAccountId, authUserId);
    if (!to) return { error: "Destination account not found" };
    if (!to.is_active) return { error: "Destination account is archived" };
  }

  if (type === "expense" || type === "income") {
    if (card && card.card_type === "debit") {
      accountId = accountId || card.linked_account_id;
      from = from || (accountId ? await loadAccount(client, accountId, authUserId) : null);
      if (!from) return { error: "Link this debit card to an account first" };
      cardId = card.card_id;
    } else if (card && card.card_type === "credit") {
      return { error: "Use Card Purchase for credit-card spending" };
    }
    if (!from) return { error: "Account is required" };
    toAccountId = null;
    if (type === "income") cardId = card?.card_type === "debit" ? card.card_id : null;
  }

  if (type === "card_purchase") {
    if (!card) return { error: "Card is required" };
    if (card.card_type === "debit") {
      accountId = accountId || card.linked_account_id;
      from = from || (accountId ? await loadAccount(client, accountId, authUserId) : null);
      if (!from) return { error: "Link this debit card to an account first" };
    } else {
      accountId = null;
      from = null;
    }
    toAccountId = null;
  }

  if (type === "card_payment") {
    if (!card || card.card_type !== "credit") return { error: "Credit card is required" };
    if (!from) return { error: "Payment account is required" };
    toAccountId = null;
  }

  if (type === "refund") {
    if (!from && !card) return { error: "Account or card is required" };
    if (card?.card_type === "credit") {
      accountId = null;
      from = null;
    } else if (!from) {
      return { error: "Account is required" };
    }
    toAccountId = null;
  }

  if (TRANSFER_TYPES.has(type) || type === "transfer") {
    if (!from || !to) return { error: "From and to accounts are required" };
    if (from.account_id === to.account_id) return { error: "Choose two different accounts" };
    cardId = null;
  }

  const resolvedType = TRANSFER_TYPES.has(type)
    ? classifyTransfer(from?.account_kind, to?.account_kind, type)
    : type;

  return {
    type: resolvedType,
    accountId: from?.account_id ?? null,
    toAccountId: to?.account_id ?? null,
    cardId: card?.card_id ?? null,
  };
};

const insertTransaction = async (client, authUserId, input, resolved) => {
  const result = await client.query(
    `INSERT INTO money_transactions (
       user_id, transaction_type, title, description, amount, occurred_at, category_id,
       merchant_name, account_id, counterparty_account_id, card_id, linked_transaction_id,
       payment_method, client_transaction_id
     ) VALUES ($1,$2,$3,$4,$5,COALESCE($6::timestamptz, NOW()),$7,$8,$9,$10,$11,$12,$13,$14)
     RETURNING transaction_id`,
    [
      authUserId,
      resolved.type,
      input.title,
      input.description || "",
      input.amount,
      input.occurredAt,
      input.categoryId ?? null,
      input.merchantName || "",
      resolved.accountId,
      resolved.toAccountId,
      resolved.cardId,
      input.linkedTransactionId ?? null,
      input.paymentMethod || "",
      input.clientTransactionId,
    ]
  );
  return result.rows[0].transaction_id;
};

export const listTransactions = async (req, res) => {
  try {
    const authUserId = userId(req);
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit ?? req.query.pageSize, 10) || 30, 1), 100);
    const filters = ["t.user_id = $1", "t.deleted_at IS NULL"];
    const params = [authUserId];

    const type = asTransactionType(req.query.type || req.query.transactionType);
    if ((req.query.type || req.query.transactionType) && !type) return fail(res, 400, "Invalid type");
    if (type) {
      if (type === "transfer") {
        filters.push(`t.transaction_type IN ('transfer', 'cash_withdrawal', 'cash_deposit')`);
      } else {
        params.push(type);
        filters.push(`t.transaction_type = $${params.length}`);
      }
    }

    const accountId = req.query.accountId || req.query.account_id;
    if (accountId) {
      const id = parseId(accountId);
      if (!id) return fail(res, 400, "Invalid account id");
      params.push(id);
      filters.push(`(t.account_id = $${params.length} OR t.counterparty_account_id = $${params.length})`);
    }

    const cardId = req.query.cardId || req.query.card_id;
    if (cardId) {
      const id = parseId(cardId);
      if (!id) return fail(res, 400, "Invalid card id");
      params.push(id);
      filters.push(`t.card_id = $${params.length}`);
    }

    const categoryId = req.query.categoryId || req.query.category_id;
    if (categoryId) {
      const id = parseId(categoryId);
      if (!id) return fail(res, 400, "Invalid category id");
      params.push(id);
      filters.push(`t.category_id = $${params.length}`);
    }

    const search = String(req.query.search || req.query.q || "").trim();
    if (search) {
      params.push(`%${search}%`);
      filters.push(
        `(t.title ILIKE $${params.length} OR t.merchant_name ILIKE $${params.length} OR t.description ILIKE $${params.length})`
      );
    }

    const merchant = String(req.query.merchant || "").trim();
    if (merchant) {
      params.push(`%${merchant}%`);
      filters.push(`t.merchant_name ILIKE $${params.length}`);
    }

    const from = asDate(req.query.from || req.query.fromDate);
    const to = asDate(req.query.to || req.query.toDate);
    if (from === undefined || to === undefined) return fail(res, 400, "Invalid date range");
    const tz = await requestTimeZone(req);
    if (from) {
      params.push(from, tz);
      filters.push(`(t.occurred_at AT TIME ZONE $${params.length})::date >= $${params.length - 1}`);
    }
    if (to) {
      params.push(to, tz);
      filters.push(`(t.occurred_at AT TIME ZONE $${params.length})::date <= $${params.length - 1}`);
    }

    const minAmount = asPositiveMoney(req.query.minAmount);
    const maxAmount = asPositiveMoney(req.query.maxAmount);
    if (minAmount === undefined || maxAmount === undefined) return fail(res, 400, "Invalid amount range");
    if (minAmount) {
      params.push(minAmount);
      filters.push(`t.amount >= $${params.length}`);
    }
    if (maxAmount) {
      params.push(maxAmount);
      filters.push(`t.amount <= $${params.length}`);
    }

    const cursor = String(req.query.cursor || "").trim();
    if (cursor) {
      const [cursorAt, cursorId] = cursor.split("|");
      const id = parseId(cursorId);
      const at = asDateTime(cursorAt);
      if (!id || !at) return fail(res, 400, "Invalid cursor");
      params.push(at, id);
      filters.push(
        `(t.occurred_at, t.transaction_id) < ($${params.length - 1}::timestamptz, $${params.length})`
      );
    }

    const where = filters.join(" AND ");
    params.push(limit + 1);
    const result = await pool.query(
      `SELECT ${TXN_LIST_COLUMNS}
       ${TXN_JOINS}
       WHERE ${where}
       ORDER BY t.occurred_at DESC, t.transaction_id DESC
       LIMIT $${params.length}`,
      params
    );

    const rows = result.rows;
    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    const last = items[items.length - 1];
    const nextCursor = hasMore && last
      ? `${new Date(last.occurred_at).toISOString()}|${last.transaction_id}`
      : null;

    return ok(res, {
      transactions: items.map(mapTransactionList),
      pagination: { limit, nextCursor, hasMore },
    });
  } catch (error) {
    console.error("List money transactions error:", error);
    return fail(res, 500, "Could not load transactions");
  }
};

export const getTransaction = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid transaction id");
    const row = await loadTransaction(pool, id, userId(req), { detail: true });
    if (!row) return fail(res, 404, "Transaction not found", "TRANSACTION_NOT_FOUND");
    return ok(res, { transaction: mapTransactionDetail(row) });
  } catch (error) {
    console.error("Get money transaction error:", error);
    return fail(res, 500, "Could not load transaction");
  }
};

export const createTransaction = async (req, res) => {
  try {
    const authUserId = userId(req);
    const created = await withTx(async (client) => {
      const input = await parseTxnInput(client, req.body, authUserId);
      if (input.error) throw Object.assign(new Error(input.error), { status: 400 });

      if (input.clientTransactionId) {
        const existing = await client.query(
          `SELECT transaction_id FROM money_transactions
           WHERE user_id = $1 AND client_transaction_id = $2 AND deleted_at IS NULL`,
          [authUserId, input.clientTransactionId]
        );
        if (existing.rowCount) {
          return { id: existing.rows[0].transaction_id, replayed: true };
        }
      }

      const resolved = await resolveTxnAccounts(client, input, authUserId);
      if (resolved.error) throw Object.assign(new Error(resolved.error), { status: 400 });
      if (!input.title) throw Object.assign(new Error("Title is required"), { status: 400 });
      if (!input.amount) throw Object.assign(new Error("Amount is required"), { status: 400 });

      const id = await insertTransaction(client, authUserId, input, resolved);
      await refreshLedger(client, {
        userId: authUserId,
        accountIds: [resolved.accountId, resolved.toAccountId],
        cardIds: [resolved.cardId],
      });
      return { id, replayed: false };
    });

    const row = await loadTransaction(pool, created.id, authUserId, { detail: true });
    return ok(
      res,
      { transaction: mapTransactionDetail(row) },
      { status: created.replayed ? 200 : 201, message: created.replayed ? "Transaction saved" : "Transaction added" }
    );
  } catch (error) {
    if (error.code === "23505") {
      return fail(res, 409, "Duplicate transaction", "DUPLICATE_TRANSACTION");
    }
    if (error.status === 400) return fail(res, 400, error.message, "VALIDATION_ERROR");
    console.error("Create money transaction error:", error);
    return fail(res, 500, "Could not save transaction");
  }
};

export const updateTransaction = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid transaction id");
    const authUserId = userId(req);

    await withTx(async (client) => {
      const existing = await client.query(
        `SELECT * FROM money_transactions
         WHERE transaction_id = $1 AND user_id = $2 AND deleted_at IS NULL`,
        [id, authUserId]
      );
      if (!existing.rowCount) throw Object.assign(new Error("Transaction not found"), { status: 404 });
      const current = existing.rows[0];
      const input = await parseTxnInput(client, req.body, authUserId, { partial: true });
      if (input.error) throw Object.assign(new Error(input.error), { status: 400 });

      const merged = {
        type: input.type || current.transaction_type,
        title: input.title || current.title,
        amount: input.amount ?? current.amount,
        occurredAt: input.occurredAt === undefined ? current.occurred_at : input.occurredAt,
        merchantName: input.merchantName ?? current.merchant_name,
        description: input.description ?? current.description,
        paymentMethod: input.paymentMethod ?? current.payment_method,
        categoryId: input.categoryId === undefined ? current.category_id : input.categoryId,
        accountId: input.accountId === undefined ? current.account_id : input.accountId,
        toAccountId: input.toAccountId === undefined ? current.counterparty_account_id : input.toAccountId,
        cardId: input.cardId === undefined ? current.card_id : input.cardId,
        linkedTransactionId:
          input.linkedTransactionId === undefined ? current.linked_transaction_id : input.linkedTransactionId,
        clientTransactionId: current.client_transaction_id,
      };

      const resolved = await resolveTxnAccounts(client, merged, authUserId);
      if (resolved.error) throw Object.assign(new Error(resolved.error), { status: 400 });

      await client.query(
        `UPDATE money_transactions
         SET transaction_type = $1, title = $2, description = $3, amount = $4, occurred_at = $5,
             category_id = $6, merchant_name = $7, account_id = $8, counterparty_account_id = $9,
             card_id = $10, linked_transaction_id = $11, payment_method = $12, updated_at = NOW()
         WHERE transaction_id = $13 AND user_id = $14`,
        [
          resolved.type,
          merged.title,
          merged.description || "",
          merged.amount,
          merged.occurredAt,
          merged.categoryId,
          merged.merchantName || "",
          resolved.accountId,
          resolved.toAccountId,
          resolved.cardId,
          merged.linkedTransactionId,
          merged.paymentMethod || "",
          id,
          authUserId,
        ]
      );

      await refreshLedger(client, {
        userId: authUserId,
        accountIds: [current.account_id, current.counterparty_account_id, resolved.accountId, resolved.toAccountId],
        cardIds: [current.card_id, resolved.cardId],
      });
    });

    const row = await loadTransaction(pool, id, authUserId, { detail: true });
    if (!row) return fail(res, 404, "Transaction not found", "TRANSACTION_NOT_FOUND");
    return ok(res, { transaction: mapTransactionDetail(row) }, { message: "Transaction updated" });
  } catch (error) {
    if (error.status === 404) return fail(res, 404, error.message, "TRANSACTION_NOT_FOUND");
    if (error.status === 400) return fail(res, 400, error.message, "VALIDATION_ERROR");
    console.error("Update money transaction error:", error);
    return fail(res, 500, "Could not update transaction");
  }
};

export const deleteTransaction = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid transaction id");
    const authUserId = userId(req);

    const deleted = await withTx(async (client) => {
      const existing = await client.query(
        `UPDATE money_transactions
         SET deleted_at = NOW(), updated_at = NOW()
         WHERE transaction_id = $1 AND user_id = $2 AND deleted_at IS NULL
         RETURNING account_id, counterparty_account_id, card_id`,
        [id, authUserId]
      );
      if (!existing.rowCount) return null;
      const row = existing.rows[0];
      await refreshLedger(client, {
        userId: authUserId,
        accountIds: [row.account_id, row.counterparty_account_id],
        cardIds: [row.card_id],
      });
      return row;
    });

    if (!deleted) return fail(res, 404, "Transaction not found", "TRANSACTION_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Transaction deleted" });
  } catch (error) {
    console.error("Delete money transaction error:", error);
    return fail(res, 500, "Could not delete transaction");
  }
};

export const listCategories = async (req, res) => {
  try {
    await ensureDefaultMoneyData(userId(req));
    const kind = String(req.query.kind || req.query.type || "").toLowerCase();
    const filters = ["user_id = $1", "is_active = TRUE"];
    const params = [userId(req)];
    if (kind === "income" || kind === "expense" || kind === "financial") {
      params.push(kind);
      filters.push(`kind = $${params.length}`);
    }
    const result = await pool.query(
      `SELECT category_id, user_id, name, kind, icon, is_system, is_active, created_at, updated_at
       FROM money_categories
       WHERE ${filters.join(" AND ")}
       ORDER BY kind ASC, name ASC`,
      params
    );
    return ok(res, { categories: result.rows.map(mapCategory) });
  } catch (error) {
    console.error("List money categories error:", error);
    return fail(res, 500, "Could not load categories");
  }
};

export const createCategory = async (req, res) => {
  try {
    const name = clampText(pick(req.body, "name"), { required: true, max: 80 });
    if (name.error) return fail(res, 400, name.error, "VALIDATION_ERROR");
    const kind = String(pick(req.body, "kind", "type") || "expense").toLowerCase();
    if (!["income", "expense", "financial"].includes(kind)) {
      return fail(res, 400, "Invalid category type", "VALIDATION_ERROR");
    }
    const created = await pool.query(
      `INSERT INTO money_categories (user_id, name, kind, is_system)
       VALUES ($1, $2, $3, FALSE)
       RETURNING category_id, user_id, name, kind, icon, is_system, is_active, created_at, updated_at`,
      [userId(req), name.value, kind]
    );
    return ok(res, { category: mapCategory(created.rows[0]) }, { status: 201, message: "Category created" });
  } catch (error) {
    if (error.code === "23505") return fail(res, 409, "Category already exists", "CATEGORY_EXISTS");
    console.error("Create money category error:", error);
    return fail(res, 500, "Could not create category");
  }
};

export const updateCategory = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid category id");
    const name = clampText(pick(req.body, "name"), { required: true, max: 80 });
    if (name.error) return fail(res, 400, name.error, "VALIDATION_ERROR");
    const updated = await pool.query(
      `UPDATE money_categories
       SET name = $1, updated_at = NOW()
       WHERE category_id = $2 AND user_id = $3
       RETURNING category_id, user_id, name, kind, icon, is_system, is_active, created_at, updated_at`,
      [name.value, id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Category not found", "CATEGORY_NOT_FOUND");
    return ok(res, { category: mapCategory(updated.rows[0]) }, { message: "Category updated" });
  } catch (error) {
    if (error.code === "23505") return fail(res, 409, "Category already exists", "CATEGORY_EXISTS");
    console.error("Update money category error:", error);
    return fail(res, 500, "Could not update category");
  }
};

export const deleteCategory = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid category id");
    const existing = await pool.query(
      `SELECT is_system FROM money_categories WHERE category_id = $1 AND user_id = $2`,
      [id, userId(req)]
    );
    if (!existing.rowCount) return fail(res, 404, "Category not found", "CATEGORY_NOT_FOUND");
    if (existing.rows[0].is_system) {
      await pool.query(
        `UPDATE money_categories SET is_active = FALSE, updated_at = NOW()
         WHERE category_id = $1 AND user_id = $2`,
        [id, userId(req)]
      );
      return ok(res, { archived: true }, { message: "Category archived" });
    }
    await pool.query(
      `DELETE FROM money_categories WHERE category_id = $1 AND user_id = $2`,
      [id, userId(req)]
    );
    return ok(res, { deleted: true }, { message: "Category deleted" });
  } catch (error) {
    console.error("Delete money category error:", error);
    return fail(res, 500, "Could not delete category");
  }
};

export const moneyOverview = async (req, res) => {
  try {
    const authUserId = userId(req);
    await ensureDefaultMoneyData(authUserId);
    const tz = await requestTimeZone(req);
    const bounds = await monthBounds(pool, tz);

    const [accounts, cards, month, recent] = await Promise.all([
      pool.query(
        `SELECT account_id, name, account_kind, last_four_digits, current_balance, is_active
         FROM money_accounts
         WHERE user_id = $1 AND is_active = TRUE
         ORDER BY account_kind ASC, name ASC`,
        [authUserId]
      ),
      pool.query(
        `SELECT card_id, name, card_type, last_four_digits, credit_limit, current_outstanding,
                CASE
                  WHEN card_type = 'credit' AND credit_limit IS NOT NULL
                    THEN credit_limit - current_outstanding
                  ELSE NULL
                END AS available_credit
         FROM money_cards
         WHERE user_id = $1 AND is_active = TRUE AND card_type = 'credit'
         ORDER BY name ASC`,
        [authUserId]
      ),
      pool.query(
        `SELECT
           COALESCE(SUM(amount) FILTER (WHERE transaction_type = 'income'), 0) AS income,
           COALESCE(SUM(amount) FILTER (
             WHERE transaction_type IN ('expense', 'card_purchase')
           ), 0)
           - COALESCE(SUM(amount) FILTER (WHERE transaction_type = 'refund'), 0) AS expense,
           COALESCE(SUM(amount) FILTER (
             WHERE transaction_type IN ('transfer', 'cash_withdrawal', 'cash_deposit')
           ), 0) AS transfers,
           COALESCE(SUM(amount) FILTER (WHERE transaction_type = 'income'), 0)
           - (
             COALESCE(SUM(amount) FILTER (
               WHERE transaction_type IN ('expense', 'card_purchase')
             ), 0)
             - COALESCE(SUM(amount) FILTER (WHERE transaction_type = 'refund'), 0)
           ) AS net_income,
           (
             SELECT COALESCE(SUM(current_balance), 0)
             FROM money_accounts
             WHERE user_id = $1 AND is_active = TRUE
           ) AS cash_and_bank,
           (
             SELECT COALESCE(SUM(current_outstanding), 0)
             FROM money_cards
             WHERE user_id = $1 AND is_active = TRUE AND card_type = 'credit'
           ) AS credit_outstanding,
           (
             SELECT COALESCE(SUM(current_balance), 0)
             FROM money_accounts
             WHERE user_id = $1 AND is_active = TRUE
           ) - (
             SELECT COALESCE(SUM(current_outstanding), 0)
             FROM money_cards
             WHERE user_id = $1 AND is_active = TRUE AND card_type = 'credit'
           ) AS net_position
         FROM money_transactions
         WHERE user_id = $1 AND deleted_at IS NULL
           AND occurred_at >= $2 AND occurred_at < $3`,
        [authUserId, bounds.startAt, bounds.endAt]
      ),
      pool.query(
        `SELECT ${TXN_LIST_COLUMNS}
         ${TXN_JOINS}
         WHERE t.user_id = $1 AND t.deleted_at IS NULL
         ORDER BY t.occurred_at DESC, t.transaction_id DESC
         LIMIT 8`,
        [authUserId]
      ),
    ]);

    const stats = month.rows[0];
    return ok(res, {
      cashAndBank: formatMoney(stats.cash_and_bank),
      creditCardOutstanding: formatMoney(stats.credit_outstanding),
      netPosition: formatMoney(stats.net_position),
      monthlyIncome: formatMoney(stats.income),
      monthlyExpense: formatMoney(stats.expense),
      monthlyTransfers: formatMoney(stats.transfers),
      netIncome: formatMoney(stats.net_income),
      accounts: accounts.rows.map((row) => ({
        accountId: row.account_id,
        name: row.name,
        accountKind: row.account_kind,
        lastFourDigits: row.last_four_digits,
        currentBalance: formatMoney(row.current_balance),
      })),
      creditCards: cards.rows.map((row) => ({
        cardId: row.card_id,
        name: row.name,
        lastFourDigits: row.last_four_digits,
        currentOutstanding: formatMoney(row.current_outstanding),
        availableCredit: row.available_credit == null ? null : formatMoney(row.available_credit),
        creditLimit: row.credit_limit == null ? null : formatMoney(row.credit_limit),
      })),
      recentTransactions: recent.rows.map(mapTransactionList),
    });
  } catch (error) {
    console.error("Money overview error:", error);
    return fail(res, 500, "Could not load money overview");
  }
};

export const moneyReports = async (req, res) => {
  try {
    const authUserId = userId(req);
    const tz = await requestTimeZone(req);
    const bounds = await monthBounds(pool, tz, req.query.month);
    if (!bounds) return fail(res, 400, "Invalid month");

    const [categories, accounts, cards, transfers] = await Promise.all([
      pool.query(
        `SELECT c.category_id, c.name,
                COALESCE(SUM(t.amount) FILTER (
                  WHERE t.transaction_type IN ('expense', 'card_purchase')
                ), 0)
                - COALESCE(SUM(t.amount) FILTER (WHERE t.transaction_type = 'refund'), 0) AS spent
         FROM money_categories c
         LEFT JOIN money_transactions t
           ON t.category_id = c.category_id AND t.user_id = $1 AND t.deleted_at IS NULL
          AND t.occurred_at >= $2 AND t.occurred_at < $3
         WHERE c.user_id = $1 AND c.is_active = TRUE AND c.kind IN ('expense', 'financial')
         GROUP BY c.category_id, c.name
         HAVING (
           COALESCE(SUM(t.amount) FILTER (
             WHERE t.transaction_type IN ('expense', 'card_purchase')
           ), 0)
           - COALESCE(SUM(t.amount) FILTER (WHERE t.transaction_type = 'refund'), 0)
         ) <> 0
         ORDER BY spent DESC`,
        [authUserId, bounds.startAt, bounds.endAt]
      ),
      pool.query(
        `SELECT a.account_id, a.name,
                COALESCE(SUM(t.amount) FILTER (
                  WHERE t.transaction_type IN ('expense', 'card_purchase') AND t.account_id = a.account_id
                ), 0)
                - COALESCE(SUM(t.amount) FILTER (
                  WHERE t.transaction_type = 'refund' AND t.account_id = a.account_id
                ), 0) AS spent
         FROM money_accounts a
         LEFT JOIN money_transactions t
           ON t.user_id = a.user_id AND t.deleted_at IS NULL
          AND t.occurred_at >= $2 AND t.occurred_at < $3
          AND (t.account_id = a.account_id)
         WHERE a.user_id = $1 AND a.is_active = TRUE
         GROUP BY a.account_id, a.name
         HAVING (
           COALESCE(SUM(t.amount) FILTER (
             WHERE t.transaction_type IN ('expense', 'card_purchase') AND t.account_id = a.account_id
           ), 0)
           - COALESCE(SUM(t.amount) FILTER (
             WHERE t.transaction_type = 'refund' AND t.account_id = a.account_id
           ), 0)
         ) <> 0
         ORDER BY spent DESC`,
        [authUserId, bounds.startAt, bounds.endAt]
      ),
      pool.query(
        `SELECT c.card_id, c.name, c.card_type,
                COALESCE(SUM(t.amount) FILTER (WHERE t.transaction_type = 'card_purchase'), 0) AS purchases,
                COALESCE(SUM(t.amount) FILTER (WHERE t.transaction_type = 'card_payment'), 0) AS payments
         FROM money_cards c
         LEFT JOIN money_transactions t
           ON t.card_id = c.card_id AND t.user_id = $1 AND t.deleted_at IS NULL
          AND t.occurred_at >= $2 AND t.occurred_at < $3
         WHERE c.user_id = $1 AND c.is_active = TRUE
         GROUP BY c.card_id, c.name, c.card_type
         HAVING COALESCE(SUM(t.amount) FILTER (WHERE t.transaction_type IN ('card_purchase', 'expense', 'card_payment')), 0) <> 0
         ORDER BY purchases DESC`,
        [authUserId, bounds.startAt, bounds.endAt]
      ),
      pool.query(
        `SELECT COALESCE(SUM(amount), 0) AS total
         FROM money_transactions
         WHERE user_id = $1 AND deleted_at IS NULL
           AND transaction_type IN ('transfer', 'cash_withdrawal', 'cash_deposit')
           AND occurred_at >= $2 AND occurred_at < $3`,
        [authUserId, bounds.startAt, bounds.endAt]
      ),
    ]);

    return ok(res, {
      categorySpending: categories.rows.map((row) => ({
        categoryId: row.category_id,
        name: row.name,
        amount: formatMoney(row.spent),
      })),
      accountSpending: accounts.rows.map((row) => ({
        accountId: row.account_id,
        name: row.name,
        amount: formatMoney(row.spent),
      })),
      cardSpending: cards.rows.map((row) => ({
        cardId: row.card_id,
        name: row.name,
        cardType: row.card_type,
        purchases: formatMoney(row.purchases),
        payments: formatMoney(row.payments),
      })),
      monthlyTransfers: formatMoney(transfers.rows[0].total),
    });
  } catch (error) {
    console.error("Money reports error:", error);
    return fail(res, 500, "Could not load reports");
  }
};
