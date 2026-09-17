import { pool } from "../config/db.js";

const DEFAULT_TASK_CATEGORIES = [
  "Personal",
  "Work",
  "Finance",
  "Shopping",
  "Health",
  "Travel",
  "Learning",
  "Other",
];

const DEFAULT_NOTE_CATEGORIES = ["Personal", "Work", "Ideas", "Other"];

export const initPlannerSchema = async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS task_categories (
      task_category_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      name VARCHAR(80) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE UNIQUE INDEX IF NOT EXISTS task_categories_user_name_idx
      ON task_categories (user_id, LOWER(name));

    CREATE TABLE IF NOT EXISTS tasks (
      task_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      category_id INTEGER REFERENCES task_categories(task_category_id) ON DELETE SET NULL,
      title VARCHAR(200) NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'completed', 'archived')),
      priority VARCHAR(20) NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('low', 'medium', 'high')),
      due_date DATE,
      due_time TIME,
      repeat_type VARCHAR(20) NOT NULL DEFAULT 'none'
        CHECK (repeat_type IN ('none', 'daily', 'weekly', 'monthly', 'yearly', 'custom')),
      repeat_interval INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval >= 1),
      is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
      is_archived BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS tasks_user_status_idx ON tasks (user_id, status);
    CREATE INDEX IF NOT EXISTS tasks_user_due_date_idx ON tasks (user_id, due_date);

    CREATE TABLE IF NOT EXISTS task_subtasks (
      task_subtask_id SERIAL PRIMARY KEY,
      task_id INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
      title VARCHAR(200) NOT NULL,
      is_completed BOOLEAN NOT NULL DEFAULT FALSE,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS task_subtasks_task_id_idx ON task_subtasks (task_id, position);

    CREATE TABLE IF NOT EXISTS note_categories (
      note_category_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      name VARCHAR(80) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE UNIQUE INDEX IF NOT EXISTS note_categories_user_name_idx
      ON note_categories (user_id, LOWER(name));

    CREATE TABLE IF NOT EXISTS notes (
      note_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      category_id INTEGER REFERENCES note_categories(note_category_id) ON DELETE SET NULL,
      title VARCHAR(200) NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
      is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
      is_archived BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS notes_user_updated_at_idx ON notes (user_id, updated_at DESC);

    CREATE TABLE IF NOT EXISTS note_tags (
      note_tag_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      name VARCHAR(60) NOT NULL
    );

    CREATE UNIQUE INDEX IF NOT EXISTS note_tags_user_name_idx
      ON note_tags (user_id, LOWER(name));

    CREATE TABLE IF NOT EXISTS note_tag_mapping (
      note_id INTEGER NOT NULL REFERENCES notes(note_id) ON DELETE CASCADE,
      note_tag_id INTEGER NOT NULL REFERENCES note_tags(note_tag_id) ON DELETE CASCADE,
      PRIMARY KEY (note_id, note_tag_id)
    );

    CREATE TABLE IF NOT EXISTS reminders (
      reminder_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      task_id INTEGER REFERENCES tasks(task_id) ON DELETE SET NULL,
      title VARCHAR(200) NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      reminder_at TIMESTAMPTZ NOT NULL,
      repeat_type VARCHAR(20) NOT NULL DEFAULT 'none'
        CHECK (repeat_type IN ('none', 'daily', 'weekly', 'monthly', 'yearly', 'custom')),
      repeat_interval INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval >= 1),
      status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'completed', 'cancelled')),
      snoozed_until TIMESTAMPTZ,
      notification_id VARCHAR(80),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS reminders_user_status_at_idx
      ON reminders (user_id, status, reminder_at);
  `);

  await pool.query(`
    ALTER TABLE reminders
      ADD COLUMN IF NOT EXISTS kind VARCHAR(20) NOT NULL DEFAULT 'reminder';
  `);

  await pool.query(`
    DO $$ BEGIN
      ALTER TABLE reminders
        ADD CONSTRAINT reminders_kind_check
        CHECK (kind IN ('reminder', 'alarm'));
    EXCEPTION
      WHEN duplicate_object THEN NULL;
    END $$;
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS reminders_user_kind_status_idx
      ON reminders (user_id, kind, status);

    CREATE TABLE IF NOT EXISTS calendar_events (
      calendar_event_id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      title VARCHAR(200) NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      start_at TIMESTAMPTZ NOT NULL,
      end_at TIMESTAMPTZ,
      is_all_day BOOLEAN NOT NULL DEFAULT FALSE,
      repeat_type VARCHAR(20) NOT NULL DEFAULT 'none'
        CHECK (repeat_type IN ('none', 'daily', 'weekly', 'monthly', 'yearly', 'custom')),
      repeat_interval INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval >= 1),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS calendar_events_user_start_at_idx
      ON calendar_events (user_id, start_at);
  `);

  console.log("Planner schema ready");
};

export const ensureDefaultPlannerData = async (userId) => {
  const existingTasks = await pool.query(
    "SELECT 1 FROM task_categories WHERE user_id = $1 LIMIT 1",
    [userId]
  );

  if (existingTasks.rowCount === 0) {
    for (const name of DEFAULT_TASK_CATEGORIES) {
      await pool.query(
        `INSERT INTO task_categories (user_id, name)
         VALUES ($1, $2)`,
        [userId, name]
      );
    }
  }

  const existingNotes = await pool.query(
    "SELECT 1 FROM note_categories WHERE user_id = $1 LIMIT 1",
    [userId]
  );

  if (existingNotes.rowCount === 0) {
    for (const name of DEFAULT_NOTE_CATEGORIES) {
      await pool.query(
        `INSERT INTO note_categories (user_id, name)
         VALUES ($1, $2)`,
        [userId, name]
      );
    }
  }
};
