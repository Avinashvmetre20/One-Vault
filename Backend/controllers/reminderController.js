import { pool } from "../config/db.js";
import {
  asBoolean,
  asInterval,
  asReminderKind,
  asReminderStatus,
  asRepeatType,
  clampText,
  fail,
  ok,
  parseId,
  parsePagination,
  pick,
  toCamel,
} from "../utils/planner.js";
import { nextInstant, parseInstant, parseRangeBound, requestTimeZone } from "../utils/time.js";

const userId = (req) => req.user.user_id;

const loadReminder = async (reminderId, authUserId) => {
  const result = await pool.query(
    `SELECT r.reminder_id, r.user_id, r.task_id, r.title, r.description, r.reminder_at,
            r.repeat_type, r.repeat_interval, r.status, r.snoozed_until, r.notification_id,
            r.kind, r.time_zone, r.created_at, r.updated_at, r.completed_at, t.title AS task_title
     FROM reminders r
     LEFT JOIN tasks t ON t.task_id = r.task_id
     WHERE r.reminder_id = $1 AND r.user_id = $2`,
    [reminderId, authUserId]
  );
  return result.rows[0] || null;
};

const ownedTask = async (taskId, authUserId) => {
  if (!taskId) return true;
  const result = await pool.query(
    `SELECT task_id FROM tasks WHERE task_id = $1 AND user_id = $2`,
    [taskId, authUserId]
  );
  return result.rowCount > 0;
};

const parseReminderInput = async (body, authUserId, { partial = false, timeZone } = {}) => {
  const titleRaw = pick(body, "title");
  const title = titleRaw === undefined && partial
    ? { value: undefined }
    : clampText(titleRaw, { required: !partial, max: 200 });
  if (title.error) return { error: title.error };
  const descriptionRaw = pick(body, "description");
  const description = descriptionRaw === undefined && partial
    ? { value: undefined }
    : clampText(descriptionRaw, { max: 5000 });
  if (description.error) return { error: description.error };

  const atValue = pick(body, "reminderAt", "reminder_at", "dateTime");
  const reminderAt = atValue === undefined ? undefined : await parseInstant(atValue, timeZone);
  if (!partial && !reminderAt) return { error: "Reminder date and time are required" };
  if (atValue !== undefined && reminderAt === undefined) return { error: "Invalid reminder date" };

  const repeatValue = pick(body, "repeatType", "repeat_type", "recurrence");
  const repeatType = repeatValue == null ? (partial ? undefined : "none") : asRepeatType(repeatValue);
  if (repeatValue != null && !repeatType) return { error: "Invalid repeat type" };

  const intervalValue = pick(body, "repeatInterval", "repeat_interval");
  const repeatInterval = intervalValue == null ? (partial ? undefined : 1) : asInterval(intervalValue);
  if (intervalValue != null && !repeatInterval) return { error: "Invalid repeat interval" };

  const taskValue = pick(body, "taskId", "task_id");
  let taskId;
  if (taskValue === undefined) taskId = undefined;
  else if (taskValue == null || taskValue === "") taskId = null;
  else taskId = parseId(taskValue);
  if (taskValue != null && taskValue !== "" && !taskId) return { error: "Invalid task" };
  if (taskId && !(await ownedTask(taskId, authUserId))) return { error: "Task not found" };

  const kindValue = pick(body, "kind");
  const kind = kindValue == null ? (partial ? undefined : "reminder") : asReminderKind(kindValue, null);
  if (kindValue != null && !kind) return { error: "Invalid reminder kind" };

  return {
    title: title.value,
    description: description.value,
    reminderAt,
    repeatType,
    repeatInterval,
    taskId,
    kind,
    notificationId: pick(body, "notificationId", "notification_id"),
  };
};

export const listReminders = async (req, res) => {
  try {
    const { limit, offset } = parsePagination(req.query);
    const authUserId = userId(req);
    const filters = ["r.user_id = $1"];
    const params = [authUserId];

    const status = req.query.status ? asReminderStatus(req.query.status) : null;
    if (req.query.status && !status) return fail(res, 400, "Invalid status");
    if (status) {
      params.push(status);
      filters.push(`r.status = $${params.length}`);
    }

    const scope = String(req.query.scope || "").toLowerCase();
    if (scope === "upcoming" || scope === "pending") {
      filters.push("r.status = 'pending'");
    } else if (scope === "today") {
      filters.push("r.status = 'pending'");
      params.push(await requestTimeZone(req));
      filters.push(
        `(COALESCE(r.snoozed_until, r.reminder_at) AT TIME ZONE $${params.length})::date = (NOW() AT TIME ZONE $${params.length})::date`
      );
    } else if (scope === "completed") {
      filters.push("r.status = 'completed'");
    } else if (scope === "cancelled") {
      filters.push("r.status = 'cancelled'");
    }

    const search = String(req.query.search || req.query.q || "").trim();
    if (search) {
      params.push(`%${search}%`);
      filters.push(`(r.title ILIKE $${params.length} OR r.description ILIKE $${params.length})`);
    }

    const taskId = parseId(req.query.taskId || req.query.task_id);
    if ((req.query.taskId || req.query.task_id) && !taskId) return fail(res, 400, "Invalid task");
    if (taskId) {
      params.push(taskId);
      filters.push(`r.task_id = $${params.length}`);
    }

    const kindQuery = req.query.kind;
    if (kindQuery) {
      const kind = asReminderKind(kindQuery, null);
      if (!kind) return fail(res, 400, "Invalid kind");
      params.push(kind);
      filters.push(`r.kind = $${params.length}`);
    }

    const tz = await requestTimeZone(req);
    const from = req.query.from ? await parseRangeBound(req.query.from, tz) : null;
    const to = req.query.to ? await parseRangeBound(req.query.to, tz, { endOfDay: true }) : null;
    if (req.query.from && from === undefined) return fail(res, 400, "Invalid from date");
    if (req.query.to && to === undefined) return fail(res, 400, "Invalid to date");
    if (from) {
      params.push(from);
      filters.push(`COALESCE(r.snoozed_until, r.reminder_at) >= $${params.length}`);
    }
    if (to) {
      params.push(to);
      filters.push(`COALESCE(r.snoozed_until, r.reminder_at) <= $${params.length}`);
    }

    const where = filters.join(" AND ");
    const count = await pool.query(
      `SELECT COUNT(*)::int AS total FROM reminders r WHERE ${where}`,
      params
    );
    params.push(limit, offset);
    const result = await pool.query(
      `SELECT r.reminder_id, r.user_id, r.task_id, r.title, r.description, r.reminder_at,
              r.repeat_type, r.repeat_interval, r.status, r.snoozed_until, r.notification_id,
              r.kind, r.time_zone, r.created_at, r.updated_at, r.completed_at, t.title AS task_title
       FROM reminders r
       LEFT JOIN tasks t ON t.task_id = r.task_id
       WHERE ${where}
       ORDER BY COALESCE(r.snoozed_until, r.reminder_at) ASC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return ok(res, {
      reminders: result.rows.map(toCamel),
      pagination: { limit, offset, total: count.rows[0].total },
    });
  } catch (error) {
    console.error("List reminders error:", error);
    return fail(res, 500, "Could not load reminders");
  }
};

export const getReminder = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid reminder id");
    const reminder = await loadReminder(id, userId(req));
    if (!reminder) return fail(res, 404, "Reminder not found", "REMINDER_NOT_FOUND");
    return ok(res, { reminder: toCamel(reminder) });
  } catch (error) {
    console.error("Get reminder error:", error);
    return fail(res, 500, "Could not load reminder");
  }
};

export const createReminder = async (req, res) => {
  try {
    const tz = await requestTimeZone(req);
    const parsed = await parseReminderInput(req.body, userId(req), { timeZone: tz });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    const created = await pool.query(
      `INSERT INTO reminders (
         user_id, task_id, title, description, reminder_at, repeat_type, repeat_interval, kind, notification_id, time_zone
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING reminder_id`,
      [
        userId(req),
        parsed.taskId ?? null,
        parsed.title,
        parsed.description,
        parsed.reminderAt,
        parsed.repeatType,
        parsed.repeatInterval,
        parsed.kind ?? "reminder",
        parsed.notificationId ?? null,
        tz,
      ]
    );
    const reminder = await loadReminder(created.rows[0].reminder_id, userId(req));
    return ok(res, { reminder: toCamel(reminder) }, { status: 201, message: "Reminder created" });
  } catch (error) {
    console.error("Create reminder error:", error);
    return fail(res, 500, "Could not create reminder");
  }
};

export const updateReminder = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid reminder id");
    const existing = await loadReminder(id, userId(req));
    if (!existing) return fail(res, 404, "Reminder not found", "REMINDER_NOT_FOUND");

    const tz = await requestTimeZone(req);
    const parsed = await parseReminderInput(req.body, userId(req), {
      partial: true,
      timeZone: tz,
    });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    await pool.query(
      `UPDATE reminders
       SET title = $1, description = $2, reminder_at = $3, repeat_type = $4,
           repeat_interval = $5, task_id = $6, kind = $7, notification_id = $8,
           time_zone = $9, updated_at = NOW()
       WHERE reminder_id = $10 AND user_id = $11`,
      [
        parsed.title || existing.title,
        parsed.description === undefined ? existing.description : parsed.description,
        parsed.reminderAt ?? existing.reminder_at,
        parsed.repeatType ?? existing.repeat_type,
        parsed.repeatInterval ?? existing.repeat_interval,
        parsed.taskId === undefined ? existing.task_id : parsed.taskId,
        parsed.kind ?? existing.kind ?? "reminder",
        parsed.notificationId === undefined ? existing.notification_id : parsed.notificationId,
        parsed.reminderAt ? tz : existing.time_zone,
        id,
        userId(req),
      ]
    );
    const reminder = await loadReminder(id, userId(req));
    return ok(res, { reminder: toCamel(reminder) }, { message: "Reminder updated" });
  } catch (error) {
    console.error("Update reminder error:", error);
    return fail(res, 500, "Could not update reminder");
  }
};

export const deleteReminder = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid reminder id");
    const deleted = await pool.query(
      `DELETE FROM reminders WHERE reminder_id = $1 AND user_id = $2 RETURNING reminder_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Reminder not found", "REMINDER_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Reminder deleted" });
  } catch (error) {
    console.error("Delete reminder error:", error);
    return fail(res, 500, "Could not delete reminder");
  }
};

export const completeReminder = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid reminder id");
    const existing = await loadReminder(id, userId(req));
    if (!existing) return fail(res, 404, "Reminder not found", "REMINDER_NOT_FOUND");

    const reopen = asBoolean(pick(req.body, "reopen"), existing.status === "completed");
    if (reopen) {
      await pool.query(
        `UPDATE reminders
         SET status = 'pending', completed_at = NULL, snoozed_until = NULL, updated_at = NOW()
         WHERE reminder_id = $1 AND user_id = $2`,
        [id, userId(req)]
      );
    } else if (existing.repeat_type && existing.repeat_type !== "none") {
      const nextAt = await nextInstant(
        existing.reminder_at,
        existing.repeat_type,
        existing.repeat_interval,
        existing.time_zone || (await requestTimeZone(req)),
        { after: new Date().toISOString() }
      );
      if (!nextAt) {
        await pool.query(
          `UPDATE reminders
           SET status = 'completed', completed_at = NOW(), snoozed_until = NULL, updated_at = NOW()
           WHERE reminder_id = $1 AND user_id = $2`,
          [id, userId(req)]
        );
      } else {
        await pool.query(
          `UPDATE reminders
           SET status = 'pending', reminder_at = $1, snoozed_until = NULL,
               completed_at = NULL, updated_at = NOW()
           WHERE reminder_id = $2 AND user_id = $3`,
          [nextAt, id, userId(req)]
        );
      }
    } else {
      await pool.query(
        `UPDATE reminders
         SET status = 'completed', completed_at = NOW(), snoozed_until = NULL, updated_at = NOW()
         WHERE reminder_id = $1 AND user_id = $2`,
        [id, userId(req)]
      );
    }

    const reminder = await loadReminder(id, userId(req));
    return ok(res, { reminder: toCamel(reminder) }, { message: "Reminder updated" });
  } catch (error) {
    console.error("Complete reminder error:", error);
    return fail(res, 500, "Could not update reminder");
  }
};

export const snoozeReminder = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid reminder id");
    const existing = await loadReminder(id, userId(req));
    if (!existing) return fail(res, 404, "Reminder not found", "REMINDER_NOT_FOUND");

    const untilValue = pick(req.body, "snoozedUntil", "snoozed_until", "until");
    const minutes = Number.parseInt(pick(req.body, "minutes"), 10);
    let until = untilValue ? await parseInstant(untilValue, await requestTimeZone(req)) : undefined;
    if (untilValue && until === undefined) return fail(res, 400, "Invalid snooze time");
    if (!until) {
      const add = Number.isInteger(minutes) && minutes > 0 ? minutes : 10;
      until = new Date(Date.now() + add * 60 * 1000).toISOString();
    }
    if (new Date(until) <= new Date()) return fail(res, 400, "Snooze time must be in the future");

    await pool.query(
      `UPDATE reminders
       SET snoozed_until = $1, status = 'pending', updated_at = NOW()
       WHERE reminder_id = $2 AND user_id = $3`,
      [until, id, userId(req)]
    );
    const reminder = await loadReminder(id, userId(req));
    return ok(res, { reminder: toCamel(reminder) }, { message: "Reminder snoozed" });
  } catch (error) {
    console.error("Snooze reminder error:", error);
    return fail(res, 500, "Could not snooze reminder");
  }
};

export const cancelReminder = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid reminder id");
    const updated = await pool.query(
      `UPDATE reminders
       SET status = 'cancelled', snoozed_until = NULL, updated_at = NOW()
       WHERE reminder_id = $1 AND user_id = $2
       RETURNING reminder_id`,
      [id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Reminder not found", "REMINDER_NOT_FOUND");
    const reminder = await loadReminder(id, userId(req));
    return ok(res, { reminder: toCamel(reminder) }, { message: "Reminder cancelled" });
  } catch (error) {
    console.error("Cancel reminder error:", error);
    return fail(res, 500, "Could not cancel reminder");
  }
};
