import { pool } from "../config/db.js";

export const initVaultSchema = async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS vault_meta (
      user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
      kdf TEXT NOT NULL DEFAULT 'argon2id',
      kdf_memory INTEGER NOT NULL,
      kdf_iterations INTEGER NOT NULL,
      kdf_parallelism INTEGER NOT NULL,
      salt TEXT NOT NULL,
      wrapped_dek TEXT NOT NULL,
      wrapped_dek_nonce TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS vault_credentials (
      credential_id UUID PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      encrypted_payload TEXT NOT NULL,
      nonce TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      deleted_at TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS vault_credentials_user_updated_idx
      ON vault_credentials (user_id, updated_at DESC);
  `);
};
