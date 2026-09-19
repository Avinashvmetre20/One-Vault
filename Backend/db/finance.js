import { pool } from "../config/db.js";

const DEFAULT_CATEGORIES = [
  ["Salary", "income"],
  ["Bonus", "income"],
  ["Freelance", "income"],
  ["Interest", "income"],
  ["Dividend", "income"],
  ["Refund", "income"],
  ["Money Received", "income"],
  ["Other Income", "income"],
  ["Food", "expense"],
  ["Groceries", "expense"],
  ["Shopping", "expense"],
  ["Rent", "expense"],
  ["Electricity", "expense"],
  ["Water", "expense"],
  ["Internet", "expense"],
  ["Mobile", "expense"],
  ["Fuel", "expense"],
  ["Transport", "expense"],
  ["Travel", "expense"],
  ["Entertainment", "expense"],
  ["Subscriptions", "expense"],
  ["Medical", "expense"],
  ["Education", "expense"],
  ["Insurance", "expense"],
  ["Household", "expense"],
  ["Personal", "expense"],
  ["Other", "expense"],
  ["Investment", "financial"],
  ["Loan Payment", "financial"],
  ["Bank Charges", "financial"],
  ["Interest Paid", "financial"],
  ["Credit Card Payment", "financial"],
];

export const initFinanceSchema = async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS money_accounts (
      account_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      name VARCHAR(120) NOT NULL,
      institution_name VARCHAR(120) NOT NULL DEFAULT '',
      account_kind VARCHAR(20) NOT NULL DEFAULT 'bank'
        CHECK (account_kind IN ('bank', 'cash')),
      bank_account_type VARCHAR(20)
        CHECK (bank_account_type IS NULL OR bank_account_type IN ('savings', 'current', 'salary', 'other')),
      last_four_digits VARCHAR(4)
        CHECK (last_four_digits IS NULL OR last_four_digits ~ '^[0-9]{4}$'),
      opening_balance NUMERIC(18, 2) NOT NULL DEFAULT 0,
      current_balance NUMERIC(18, 2) NOT NULL DEFAULT 0,
      currency VARCHAR(3) NOT NULL DEFAULT 'INR',
      notes TEXT NOT NULL DEFAULT '',
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS money_accounts_user_active_idx
      ON money_accounts (user_id, is_active, name);

    CREATE TABLE IF NOT EXISTS money_cards (
      card_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      name VARCHAR(120) NOT NULL,
      card_type VARCHAR(20) NOT NULL CHECK (card_type IN ('debit', 'credit')),
      issuer_name VARCHAR(120) NOT NULL DEFAULT '',
      last_four_digits VARCHAR(4)
        CHECK (last_four_digits IS NULL OR last_four_digits ~ '^[0-9]{4}$'),
      linked_account_id INTEGER REFERENCES money_accounts(account_id) ON DELETE SET NULL,
      credit_limit NUMERIC(18, 2),
      opening_outstanding NUMERIC(18, 2) NOT NULL DEFAULT 0,
      current_outstanding NUMERIC(18, 2) NOT NULL DEFAULT 0,
      statement_day INTEGER CHECK (statement_day IS NULL OR statement_day BETWEEN 1 AND 31),
      due_day INTEGER CHECK (due_day IS NULL OR due_day BETWEEN 1 AND 31),
      minimum_due NUMERIC(18, 2),
      notes TEXT NOT NULL DEFAULT '',
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS money_cards_user_active_idx
      ON money_cards (user_id, is_active, card_type, name);

    CREATE TABLE IF NOT EXISTS money_categories (
      category_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      name VARCHAR(80) NOT NULL,
      kind VARCHAR(20) NOT NULL CHECK (kind IN ('income', 'expense', 'financial')),
      icon VARCHAR(40),
      is_system BOOLEAN NOT NULL DEFAULT FALSE,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE UNIQUE INDEX IF NOT EXISTS money_categories_user_name_kind_idx
      ON money_categories (user_id, LOWER(name), kind);

    CREATE TABLE IF NOT EXISTS money_transactions (
      transaction_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      transaction_type VARCHAR(30) NOT NULL
        CHECK (transaction_type IN (
          'expense', 'income', 'transfer', 'refund', 'card_purchase',
          'card_payment', 'cash_withdrawal', 'cash_deposit', 'adjustment'
        )),
      title VARCHAR(200) NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      amount NUMERIC(18, 2) NOT NULL CHECK (amount > 0),
      occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      category_id INTEGER REFERENCES money_categories(category_id) ON DELETE SET NULL,
      merchant_name VARCHAR(200) NOT NULL DEFAULT '',
      account_id INTEGER REFERENCES money_accounts(account_id) ON DELETE RESTRICT,
      counterparty_account_id INTEGER REFERENCES money_accounts(account_id) ON DELETE RESTRICT,
      card_id INTEGER REFERENCES money_cards(card_id) ON DELETE RESTRICT,
      linked_transaction_id INTEGER REFERENCES money_transactions(transaction_id) ON DELETE SET NULL,
      payment_method VARCHAR(40) NOT NULL DEFAULT '',
      client_transaction_id VARCHAR(80),
      deleted_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT money_txn_transfer_chk CHECK (
        transaction_type NOT IN ('transfer', 'cash_withdrawal', 'cash_deposit')
        OR (
          account_id IS NOT NULL
          AND counterparty_account_id IS NOT NULL
          AND account_id <> counterparty_account_id
        )
      ),
      CONSTRAINT money_txn_card_chk CHECK (
        transaction_type NOT IN ('card_purchase', 'card_payment')
        OR card_id IS NOT NULL
      )
    );

    CREATE INDEX IF NOT EXISTS money_transactions_user_date_idx
      ON money_transactions (user_id, occurred_at DESC, transaction_id DESC)
      WHERE deleted_at IS NULL;

    CREATE INDEX IF NOT EXISTS money_transactions_user_account_date_idx
      ON money_transactions (user_id, account_id, occurred_at DESC)
      WHERE deleted_at IS NULL;

    CREATE INDEX IF NOT EXISTS money_transactions_user_card_date_idx
      ON money_transactions (user_id, card_id, occurred_at DESC)
      WHERE deleted_at IS NULL;

    CREATE INDEX IF NOT EXISTS money_transactions_user_category_date_idx
      ON money_transactions (user_id, category_id, occurred_at DESC)
      WHERE deleted_at IS NULL;

    CREATE INDEX IF NOT EXISTS money_transactions_user_type_date_idx
      ON money_transactions (user_id, transaction_type, occurred_at DESC)
      WHERE deleted_at IS NULL;

    CREATE UNIQUE INDEX IF NOT EXISTS money_transactions_user_client_id_idx
      ON money_transactions (user_id, client_transaction_id)
      WHERE client_transaction_id IS NOT NULL AND deleted_at IS NULL;
  `);
};

export const ensureDefaultMoneyData = async (userId) => {
  const existing = await pool.query(
    `SELECT 1 FROM money_categories WHERE user_id = $1 LIMIT 1`,
    [userId]
  );
  if (existing.rowCount > 0) return;

  const names = DEFAULT_CATEGORIES.map((item) => item[0]);
  const kinds = DEFAULT_CATEGORIES.map((item) => item[1]);
  await pool.query(
    `INSERT INTO money_categories (user_id, name, kind, is_system)
     SELECT $1, name, kind, TRUE
     FROM unnest($2::text[], $3::text[]) AS t(name, kind)`,
    [userId, names, kinds]
  );
};
