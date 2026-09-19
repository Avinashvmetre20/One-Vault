import { pool } from "../config/db.js";
import { clampText, parseId, pick, toCamel } from "./planner.js";

export const ACCOUNT_KINDS = ["bank", "cash"];
export const BANK_ACCOUNT_TYPES = ["savings", "current", "salary", "other"];
export const CARD_TYPES = ["debit", "credit"];
export const CATEGORY_KINDS = ["income", "expense", "financial"];
export const TRANSACTION_TYPES = [
  "expense",
  "income",
  "transfer",
  "refund",
  "card_purchase",
  "card_payment",
  "cash_withdrawal",
  "cash_deposit",
  "adjustment",
];

export const monthBounds = async (client, tz, month) => {
  if (month) {
    const text = String(month);
    if (!/^\d{4}-\d{2}$/.test(text)) return undefined;
    const result = await client.query(
      `SELECT
         ($1::date AT TIME ZONE $2) AS start_at,
         (($1::date + interval '1 month') AT TIME ZONE $2) AS end_at`,
      [`${text}-01`, tz]
    );
    return { startAt: result.rows[0].start_at, endAt: result.rows[0].end_at };
  }
  const result = await client.query(
    `SELECT
       (date_trunc('month', timezone($1, now())) AT TIME ZONE $1) AS start_at,
       ((date_trunc('month', timezone($1, now())) + interval '1 month') AT TIME ZONE $1) AS end_at`,
    [tz]
  );
  return { startAt: result.rows[0].start_at, endAt: result.rows[0].end_at };
};

export const withTx = async (fn) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
};

export const moneyText = (value) => {
  if (value == null || value === "") return null;
  const text = String(value).trim().replace(/,/g, "");
  const match = text.match(/^(-)?(\d+)(?:\.(\d{1,2}))?$/);
  if (!match) return undefined;
  const sign = match[1] || "";
  const frac = (match[3] || "").padEnd(2, "0");
  return `${sign}${match[2]}.${frac}`;
};

export const asPositiveMoney = (value, { required = false } = {}) => {
  if (value == null || value === "") return required ? undefined : null;
  const text = moneyText(value);
  if (text == null) return text;
  if (text === undefined || text.startsWith("-") || text === "0.00") return undefined;
  return text;
};

export const asMoney = (value, { required = false, allowNegative = true } = {}) => {
  if (value == null || value === "") return required ? undefined : null;
  const text = moneyText(value);
  if (text == null) return text;
  if (text === undefined) return undefined;
  if (!allowNegative && text.startsWith("-")) return undefined;
  return text;
};

export const asLastFour = (value) => {
  if (value == null || value === "") return null;
  const digits = String(value).replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length !== 4) return undefined;
  return digits;
};

export const asDay = (value) => {
  if (value == null || value === "") return null;
  const day = Number.parseInt(value, 10);
  return Number.isInteger(day) && day >= 1 && day <= 31 ? day : undefined;
};

export const asAccountKind = (value, fallback = "bank") => {
  if (value == null || value === "") return fallback;
  const kind = String(value).toLowerCase();
  return ACCOUNT_KINDS.includes(kind) ? kind : null;
};

export const asBankAccountType = (value) => {
  if (value == null || value === "") return null;
  const type = String(value).toLowerCase();
  return BANK_ACCOUNT_TYPES.includes(type) ? type : null;
};

export const asCardType = (value) => {
  if (value == null || value === "") return null;
  const type = String(value).toLowerCase();
  return CARD_TYPES.includes(type) ? type : null;
};

export const asCategoryKind = (value) => {
  if (value == null || value === "") return null;
  const kind = String(value).toLowerCase();
  return CATEGORY_KINDS.includes(kind) ? kind : null;
};

export const asTransactionType = (value) => {
  if (value == null || value === "") return null;
  const type = String(value).toLowerCase().replace(/-/g, "_");
  return TRANSACTION_TYPES.includes(type) ? type : null;
};

export const formatMoney = (value) => moneyText(value) ?? "0.00";

export const mapAccount = (row) => {
  if (!row) return null;
  return toCamel({
    ...row,
    opening_balance: formatMoney(row.opening_balance),
    current_balance: formatMoney(row.current_balance),
    last_four_digits: row.last_four_digits || null,
  });
};

export const mapCard = (row) => {
  if (!row) return null;
  return toCamel({
    ...row,
    credit_limit: row.credit_limit == null ? null : formatMoney(row.credit_limit),
    opening_outstanding: formatMoney(row.opening_outstanding),
    current_outstanding: formatMoney(row.current_outstanding),
    minimum_due: row.minimum_due == null ? null : formatMoney(row.minimum_due),
    last_four_digits: row.last_four_digits || null,
    available_credit:
      row.card_type === "credit" && row.credit_limit != null
        ? formatMoney(
            // available is computed in SQL when present
            row.available_credit ?? null
          )
        : null,
  });
};

export const mapCategory = (row) => (row ? toCamel(row) : null);

export const mapTransactionList = (row) => {
  if (!row) return null;
  return toCamel({
    transaction_id: row.transaction_id,
    transaction_type: row.transaction_type,
    title: row.title,
    amount: formatMoney(row.amount),
    occurred_at: row.occurred_at,
    merchant_name: row.merchant_name || "",
    category_id: row.category_id,
    category_name: row.category_name || null,
    account_id: row.account_id,
    account_name: row.account_name || null,
    account_last_four: row.account_last_four || null,
    counterparty_account_id: row.counterparty_account_id,
    counterparty_account_name: row.counterparty_account_name || null,
    counterparty_last_four: row.counterparty_last_four || null,
    card_id: row.card_id,
    card_name: row.card_name || null,
    card_last_four: row.card_last_four || null,
  });
};

export const mapTransactionDetail = (row) => {
  if (!row) return null;
  return {
    ...mapTransactionList(row),
    description: row.description || "",
    paymentMethod: row.payment_method || "",
    linkedTransactionId: row.linked_transaction_id || null,
    clientTransactionId: row.client_transaction_id || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
};

export const TXN_LIST_COLUMNS = `
  t.transaction_id, t.transaction_type, t.title, t.amount, t.occurred_at,
  t.merchant_name, t.category_id, t.account_id, t.counterparty_account_id, t.card_id,
  cat.name AS category_name,
  src.name AS account_name, src.last_four_digits AS account_last_four,
  dest.name AS counterparty_account_name, dest.last_four_digits AS counterparty_last_four,
  card.name AS card_name, card.last_four_digits AS card_last_four
`;

export const TXN_DETAIL_COLUMNS = `
  ${TXN_LIST_COLUMNS},
  t.description, t.payment_method, t.linked_transaction_id, t.client_transaction_id,
  t.created_at, t.updated_at
`;

export const TXN_JOINS = `
  FROM money_transactions t
  LEFT JOIN money_categories cat ON cat.category_id = t.category_id
  LEFT JOIN money_accounts src ON src.account_id = t.account_id
  LEFT JOIN money_accounts dest ON dest.account_id = t.counterparty_account_id
  LEFT JOIN money_cards card ON card.card_id = t.card_id
`;

export const refreshAccountBalance = async (client, accountId, userId) => {
  if (!accountId) return;
  await client.query(
    `UPDATE money_accounts AS a
     SET current_balance = a.opening_balance + COALESCE((
       SELECT SUM(part.delta)
       FROM (
         SELECT CASE
           WHEN t.transaction_type IN ('income', 'refund') THEN t.amount
           WHEN t.transaction_type IN ('expense', 'card_purchase', 'card_payment') THEN -t.amount
           WHEN t.transaction_type IN ('transfer', 'cash_withdrawal', 'cash_deposit') THEN -t.amount
           ELSE 0
         END AS delta
         FROM money_transactions t
         WHERE t.deleted_at IS NULL AND t.account_id = a.account_id
         UNION ALL
         SELECT t.amount
         FROM money_transactions t
         WHERE t.deleted_at IS NULL
           AND t.counterparty_account_id = a.account_id
           AND t.transaction_type IN ('transfer', 'cash_withdrawal', 'cash_deposit')
       ) part
     ), 0),
         updated_at = NOW()
     WHERE a.account_id = $1 AND a.user_id = $2`,
    [accountId, userId]
  );
};

export const refreshCardOutstanding = async (client, cardId, userId) => {
  if (!cardId) return;
  await client.query(
    `UPDATE money_cards AS c
     SET current_outstanding = c.opening_outstanding + COALESCE((
       SELECT SUM(
         CASE
           WHEN t.transaction_type = 'card_purchase' THEN t.amount
           WHEN t.transaction_type IN ('refund', 'card_payment') THEN -t.amount
           ELSE 0
         END
       )
       FROM money_transactions t
       WHERE t.deleted_at IS NULL AND t.card_id = c.card_id
     ), 0),
         updated_at = NOW()
     WHERE c.card_id = $1 AND c.user_id = $2`,
    [cardId, userId]
  );
};

export const refreshLedger = async (client, { accountIds = [], cardIds = [], userId }) => {
  const accounts = [...new Set(accountIds.filter(Boolean))];
  const cards = [...new Set(cardIds.filter(Boolean))];
  for (const id of accounts) {
    await refreshAccountBalance(client, id, userId);
  }
  for (const id of cards) {
    await refreshCardOutstanding(client, id, userId);
  }
};

export const loadAccount = async (client, accountId, userId) => {
  const result = await client.query(
    `SELECT account_id, user_id, name, institution_name, account_kind, bank_account_type,
            last_four_digits, opening_balance, current_balance, currency, notes, is_active,
            created_at, updated_at
     FROM money_accounts
     WHERE account_id = $1 AND user_id = $2`,
    [accountId, userId]
  );
  return result.rows[0] || null;
};

export const loadCard = async (client, cardId, userId) => {
  const result = await client.query(
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
     WHERE c.card_id = $1 AND c.user_id = $2`,
    [cardId, userId]
  );
  return result.rows[0] || null;
};

export const parseAccountInput = (body, { partial = false } = {}) => {
  const name = clampText(pick(body, "name"), { required: !partial, max: 120 });
  if (name.error) return { error: name.error };

  const institution = clampText(pick(body, "institutionName", "institution_name", "bankName", "bank_name"), {
    max: 120,
  });
  if (institution.error) return { error: institution.error };

  const kind = asAccountKind(pick(body, "accountKind", "account_kind", "kind"), partial ? undefined : "bank");
  if (kind === null) return { error: "Invalid account kind" };

  const bankTypeRaw = pick(body, "bankAccountType", "bank_account_type", "accountType", "account_type");
  let bankType;
  if (bankTypeRaw === undefined) bankType = partial ? undefined : kind === "cash" ? null : "savings";
  else bankType = asBankAccountType(bankTypeRaw);

  if (bankTypeRaw !== undefined && bankTypeRaw !== null && bankTypeRaw !== "" && bankType === null) {
    return { error: "Invalid account type" };
  }

  const lastFour = asLastFour(pick(body, "lastFourDigits", "last_four_digits", "lastFour", "last_four"));
  if (lastFour === undefined) return { error: "Last 4 digits must be exactly 4 numbers" };

  const opening = asMoney(pick(body, "openingBalance", "opening_balance"), {
    required: false,
    allowNegative: true,
  });
  if (opening === undefined) return { error: "Invalid opening balance" };

  const notes = clampText(pick(body, "notes"), { max: 2000 });
  if (notes.error) return { error: notes.error };

  const currency = clampText(pick(body, "currency"), { max: 3 });
  if (currency.error) return { error: currency.error };

  return {
    name: name.value,
    institutionName: institution.value,
    accountKind: kind,
    bankAccountType: kind === "cash" ? null : bankType,
    lastFourDigits: kind === "cash" ? null : lastFour,
    openingBalance: opening,
    notes: notes.value,
    currency: (currency.value || "INR").toUpperCase(),
  };
};

export const parseCardInput = (body, { partial = false } = {}) => {
  const name = clampText(pick(body, "name"), { required: !partial, max: 120 });
  if (name.error) return { error: name.error };

  const cardType = asCardType(pick(body, "cardType", "card_type"));
  if (!partial && !cardType) return { error: "Card type is required" };
  if (pick(body, "cardType", "card_type") != null && pick(body, "cardType", "card_type") !== "" && !cardType) {
    return { error: "Invalid card type" };
  }

  const issuer = clampText(pick(body, "issuerName", "issuer_name", "bank"), { max: 120 });
  if (issuer.error) return { error: issuer.error };

  const lastFour = asLastFour(pick(body, "lastFourDigits", "last_four_digits", "lastFour"));
  if (lastFour === undefined) return { error: "Last 4 digits must be exactly 4 numbers" };

  const linkedRaw = pick(body, "linkedAccountId", "linked_account_id");
  let linkedAccountId;
  if (linkedRaw === undefined) linkedAccountId = undefined;
  else if (linkedRaw === null || linkedRaw === "") linkedAccountId = null;
  else {
    linkedAccountId = parseId(linkedRaw);
    if (!linkedAccountId) return { error: "Invalid linked account" };
  }

  const creditLimit = asPositiveMoney(pick(body, "creditLimit", "credit_limit"));
  if (creditLimit === undefined) return { error: "Invalid credit limit" };

  const opening = asMoney(pick(body, "openingOutstanding", "opening_outstanding"), {
    allowNegative: false,
  });
  if (opening === undefined) return { error: "Invalid opening outstanding" };

  const statementDay = asDay(pick(body, "statementDay", "statement_day"));
  if (statementDay === undefined) return { error: "Statement day must be 1-31" };
  const dueDay = asDay(pick(body, "dueDay", "due_day"));
  if (dueDay === undefined) return { error: "Due day must be 1-31" };

  const minimumDue = asMoney(pick(body, "minimumDue", "minimum_due"), { allowNegative: false });
  if (minimumDue === undefined) return { error: "Invalid minimum due" };

  const notes = clampText(pick(body, "notes"), { max: 2000 });
  if (notes.error) return { error: notes.error };

  return {
    name: name.value,
    cardType,
    issuerName: issuer.value,
    lastFourDigits: lastFour,
    linkedAccountId,
    creditLimit: cardType === "debit" ? null : creditLimit,
    openingOutstanding: cardType === "debit" ? "0.00" : opening,
    statementDay: cardType === "debit" ? null : statementDay,
    dueDay: cardType === "debit" ? null : dueDay,
    minimumDue: cardType === "debit" ? null : minimumDue,
    notes: notes.value,
  };
};
