import { pool } from "../config/db.js";

export const initVaultSchema = async () => {
  await pool.query(`
    DROP TABLE IF EXISTS vault_meta;
    DROP TABLE IF EXISTS vault_credentials;

    CREATE TABLE IF NOT EXISTS passwords (
      password_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      title VARCHAR(200) NOT NULL,
      username VARCHAR(255) NOT NULL DEFAULT '',
      password TEXT NOT NULL DEFAULT '',
      website TEXT NOT NULL DEFAULT '',
      category VARCHAR(40) NOT NULL DEFAULT 'other',
      notes TEXT NOT NULL DEFAULT '',
      tags TEXT[] NOT NULL DEFAULT '{}',
      is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
      recovery_email VARCHAR(255) NOT NULL DEFAULT '',
      recovery_phone VARCHAR(40) NOT NULL DEFAULT '',
      two_factor_method VARCHAR(80) NOT NULL DEFAULT '',
      backup_codes TEXT NOT NULL DEFAULT '',
      security_notes TEXT NOT NULL DEFAULT '',
      domain VARCHAR(255) NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS passwords_user_updated_idx
      ON passwords (user_id, updated_at DESC);
    CREATE INDEX IF NOT EXISTS passwords_user_domain_idx
      ON passwords (user_id, domain);
  `);
};
