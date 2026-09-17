import { pool } from "../config/db.js";
import { initPlannerSchema } from "./planner.js";

const tableExists = async (tableName) => {
  const result = await pool.query(
    `SELECT EXISTS (
       SELECT 1
       FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = $1
     ) AS exists`,
    [tableName]
  );
  return result.rows[0].exists;
};

const columnInfo = async (tableName, columnName) => {
  const result = await pool.query(
    `SELECT data_type
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = $1
       AND column_name = $2`,
    [tableName, columnName]
  );
  return result.rows[0] || null;
};

export const initSchema = async () => {
  if (await tableExists("users")) {
    const idColumn = await columnInfo("users", "id");
    const userIdColumn = await columnInfo("users", "user_id");

    if (idColumn && !userIdColumn) {
      await pool.query(`
        DROP TABLE IF EXISTS refresh_tokens;

        CREATE TABLE users_new (
          user_id SERIAL PRIMARY KEY,
          name VARCHAR(120) NOT NULL,
          email VARCHAR(255) NOT NULL,
          phone VARCHAR(20),
          password TEXT NOT NULL,
          "actual password" TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        INSERT INTO users_new (name, email, phone, password, created_at, updated_at)
        SELECT name, email, phone, password, created_at, updated_at
        FROM users
        ORDER BY created_at;

        DROP TABLE users;
        ALTER TABLE users_new RENAME TO users;
        ALTER SEQUENCE users_new_user_id_seq RENAME TO users_user_id_seq;
        ALTER TABLE users
          ALTER COLUMN user_id SET DEFAULT nextval('users_user_id_seq');
      `);
      console.log("Migrated users.id to serial user_id");
    }
  }

  const sequence = await pool.query(
    `SELECT pg_get_serial_sequence('users', 'user_id') AS seq`
  );
  const seqName = sequence.rows[0]?.seq;
  if (seqName && seqName.includes("users_new_user_id_seq")) {
    await pool.query(
      `ALTER SEQUENCE ${seqName} RENAME TO users_user_id_seq`
    );
    await pool.query(
      `ALTER TABLE users
       ALTER COLUMN user_id SET DEFAULT nextval('users_user_id_seq')`
    );
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      user_id SERIAL PRIMARY KEY,
      name VARCHAR(120) NOT NULL,
      email VARCHAR(255) NOT NULL,
      phone VARCHAR(20),
      password TEXT NOT NULL,
      "actual password" TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    ALTER TABLE users
      ADD COLUMN IF NOT EXISTS "actual password" TEXT;

    CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_idx
      ON users (LOWER(email));

    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      token TEXT NOT NULL UNIQUE,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_idx
      ON refresh_tokens (user_id);
  `);

  await initPlannerSchema();
  console.log("Database schema ready");
};
