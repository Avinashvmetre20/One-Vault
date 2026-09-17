import { pool } from "../config/db.js";
import { fail, ok, toCamel } from "../utils/planner.js";

const userId = (req) => req.user.user_id;

export const plannerSummary = async (req, res) => {
  try {
    const authUserId = userId(req);
    const result = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM tasks
           WHERE user_id = $1 AND status = 'pending' AND is_archived = FALSE) AS tasks_open,
         (SELECT COUNT(*)::int FROM tasks
           WHERE user_id = $1 AND status = 'pending' AND is_archived = FALSE
             AND due_date = CURRENT_DATE) AS tasks_today,
         (SELECT COUNT(*)::int FROM notes
           WHERE user_id = $1 AND is_archived = FALSE) AS notes_total,
         (SELECT COUNT(*)::int FROM notes
           WHERE user_id = $1 AND is_archived = FALSE AND is_pinned = TRUE) AS notes_pinned,
         (SELECT COUNT(*)::int FROM reminders
           WHERE user_id = $1 AND status = 'pending' AND COALESCE(kind, 'reminder') = 'reminder') AS reminders_upcoming,
         (SELECT COUNT(*)::int FROM reminders
           WHERE user_id = $1 AND status = 'pending' AND COALESCE(kind, 'reminder') = 'reminder'
             AND COALESCE(snoozed_until, reminder_at)::date = CURRENT_DATE) AS reminders_today,
         (SELECT COUNT(*)::int FROM reminders
           WHERE user_id = $1 AND status = 'pending' AND kind = 'alarm') AS alarms_upcoming,
         (SELECT COUNT(*)::int FROM reminders
           WHERE user_id = $1 AND status = 'pending' AND kind = 'alarm'
             AND COALESCE(snoozed_until, reminder_at)::date = CURRENT_DATE) AS alarms_today,
         (SELECT COUNT(*)::int FROM calendar_events
           WHERE user_id = $1 AND start_at::date = CURRENT_DATE) AS events_today`,
      [authUserId]
    );
    const row = result.rows[0];
    return ok(res, {
      tasks: { open: row.tasks_open, today: row.tasks_today },
      notes: { total: row.notes_total, pinned: row.notes_pinned },
      reminders: { upcoming: row.reminders_upcoming, today: row.reminders_today },
      alarms: { upcoming: row.alarms_upcoming, today: row.alarms_today },
      events: { today: row.events_today },
    });
  } catch (error) {
    console.error("Planner summary error:", error);
    return fail(res, 500, "Could not load planner summary");
  }
};

export const plannerSearch = async (req, res) => {
  try {
    const q = String(req.query.q || req.query.search || "").trim();
    if (q.length < 1) {
      return ok(res, { results: [] });
    }

    const authUserId = userId(req);
    const like = `%${q}%`;

    const [tasks, notes, reminders, events] = await Promise.all([
      pool.query(
        `SELECT task_id, title, description, status, due_date
         FROM tasks
         WHERE user_id = $1 AND is_archived = FALSE
           AND (title ILIKE $2 OR description ILIKE $2)
         ORDER BY updated_at DESC
         LIMIT 10`,
        [authUserId, like]
      ),
      pool.query(
        `SELECT n.note_id, n.title, n.content
         FROM notes n
         WHERE n.user_id = $1 AND n.is_archived = FALSE
           AND (
             n.title ILIKE $2 OR n.content ILIKE $2 OR EXISTS (
               SELECT 1 FROM note_tag_mapping m
               JOIN note_tags t ON t.note_tag_id = m.note_tag_id
               WHERE m.note_id = n.note_id AND t.name ILIKE $2
             )
           )
         ORDER BY n.updated_at DESC
         LIMIT 10`,
        [authUserId, like]
      ),
      pool.query(
        `SELECT reminder_id, title, description, reminder_at, status, kind
         FROM reminders
         WHERE user_id = $1
           AND (title ILIKE $2 OR description ILIKE $2)
         ORDER BY reminder_at DESC
         LIMIT 10`,
        [authUserId, like]
      ),
      pool.query(
        `SELECT calendar_event_id, title, description, start_at, end_at
         FROM calendar_events
         WHERE user_id = $1
           AND (title ILIKE $2 OR description ILIKE $2)
         ORDER BY start_at DESC
         LIMIT 10`,
        [authUserId, like]
      ),
    ]);

    const results = [
      ...tasks.rows.map((row) => ({ type: "task", ...toCamel(row) })),
      ...notes.rows.map((row) => ({ type: "note", ...toCamel(row) })),
      ...reminders.rows.map((row) => ({
        type: row.kind === "alarm" ? "alarm" : "reminder",
        ...toCamel(row),
      })),
      ...events.rows.map((row) => ({ type: "event", ...toCamel(row) })),
    ];

    return ok(res, { results });
  } catch (error) {
    console.error("Planner search error:", error);
    return fail(res, 500, "Could not search planner");
  }
};

export const plannerAgenda = async (req, res) => {
  try {
    const authUserId = userId(req);
    const from = req.query.from || new Date().toISOString().slice(0, 10);
    const to = req.query.to || from;

    const [tasks, reminders, events] = await Promise.all([
      pool.query(
        `SELECT t.task_id, t.title, t.priority, t.status, t.due_date, t.due_time, c.name AS category_name
         FROM tasks t
         LEFT JOIN task_categories c ON c.task_category_id = t.category_id
         WHERE t.user_id = $1 AND t.is_archived = FALSE
           AND t.due_date BETWEEN $2 AND $3
         ORDER BY t.due_date ASC, t.due_time ASC NULLS LAST`,
        [authUserId, from, to]
      ),
      pool.query(
        `SELECT reminder_id, title, reminder_at, status, snoozed_until, task_id
         FROM reminders
         WHERE user_id = $1
           AND COALESCE(snoozed_until, reminder_at)::date BETWEEN $2 AND $3
         ORDER BY COALESCE(snoozed_until, reminder_at) ASC`,
        [authUserId, from, to]
      ),
      pool.query(
        `SELECT calendar_event_id, title, start_at, end_at, is_all_day
         FROM calendar_events
         WHERE user_id = $1
           AND start_at::date <= $3
           AND COALESCE(end_at, start_at)::date >= $2
         ORDER BY start_at ASC`,
        [authUserId, from, to]
      ),
    ]);

    return ok(res, {
      from,
      to,
      tasks: tasks.rows.map(toCamel),
      reminders: reminders.rows.map(toCamel),
      events: events.rows.map(toCamel),
    });
  } catch (error) {
    console.error("Planner agenda error:", error);
    return fail(res, 500, "Could not load agenda");
  }
};
