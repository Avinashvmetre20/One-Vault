import { pool } from "../config/db.js";
import {
  asBoolean,
  asDateTime,
  asInterval,
  asRepeatType,
  clampText,
  fail,
  ok,
  parseId,
  parsePagination,
  pick,
  toCamel,
} from "../utils/planner.js";

const userId = (req) => req.user.user_id;

const loadEvent = async (eventId, authUserId) => {
  const result = await pool.query(
    `SELECT calendar_event_id, user_id, title, description, start_at, end_at,
            is_all_day, repeat_type, repeat_interval, created_at, updated_at
     FROM calendar_events
     WHERE calendar_event_id = $1 AND user_id = $2`,
    [eventId, authUserId]
  );
  return result.rows[0] || null;
};

const parseEventInput = (body, { partial = false } = {}) => {
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

  const startValue = pick(body, "startAt", "start_at");
  const startAt = startValue === undefined ? undefined : asDateTime(startValue);
  if (!partial && !startAt) return { error: "Start date and time are required" };
  if (startValue !== undefined && startAt === undefined) return { error: "Invalid start date" };

  const endValue = pick(body, "endAt", "end_at");
  const endAt = endValue === undefined ? undefined : asDateTime(endValue);
  if (endValue !== undefined && endAt === undefined) return { error: "Invalid end date" };

  const repeatValue = pick(body, "repeatType", "repeat_type");
  const repeatType = repeatValue == null ? (partial ? undefined : "none") : asRepeatType(repeatValue);
  if (repeatValue != null && !repeatType) return { error: "Invalid repeat type" };

  const intervalValue = pick(body, "repeatInterval", "repeat_interval");
  const repeatInterval = intervalValue == null ? (partial ? undefined : 1) : asInterval(intervalValue);
  if (intervalValue != null && !repeatInterval) return { error: "Invalid repeat interval" };

  const isAllDayValue = pick(body, "isAllDay", "is_all_day");

  return {
    title: title.value,
    description: description.value,
    startAt,
    endAt,
    repeatType,
    repeatInterval,
    isAllDay: isAllDayValue === undefined ? undefined : asBoolean(isAllDayValue, false),
  };
};

export const listCalendarEvents = async (req, res) => {
  try {
    const { limit, offset } = parsePagination(req.query);
    const authUserId = userId(req);
    const filters = ["user_id = $1"];
    const params = [authUserId];

    const search = String(req.query.search || req.query.q || "").trim();
    if (search) {
      params.push(`%${search}%`);
      filters.push(`(title ILIKE $${params.length} OR description ILIKE $${params.length})`);
    }

    const from = req.query.from ? asDateTime(req.query.from) : null;
    const to = req.query.to ? asDateTime(req.query.to) : null;
    if (req.query.from && from === undefined) return fail(res, 400, "Invalid from date");
    if (req.query.to && to === undefined) return fail(res, 400, "Invalid to date");
    if (from) {
      params.push(from);
      filters.push(`COALESCE(end_at, start_at) >= $${params.length}`);
    }
    if (to) {
      params.push(to);
      filters.push(`start_at <= $${params.length}`);
    }

    const where = filters.join(" AND ");
    const count = await pool.query(
      `SELECT COUNT(*)::int AS total FROM calendar_events WHERE ${where}`,
      params
    );
    params.push(limit, offset);
    const result = await pool.query(
      `SELECT calendar_event_id, user_id, title, description, start_at, end_at,
              is_all_day, repeat_type, repeat_interval, created_at, updated_at
       FROM calendar_events
       WHERE ${where}
       ORDER BY start_at ASC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return ok(res, {
      events: result.rows.map(toCamel),
      pagination: { limit, offset, total: count.rows[0].total },
    });
  } catch (error) {
    console.error("List calendar events error:", error);
    return fail(res, 500, "Could not load calendar");
  }
};

export const getCalendarEvent = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid event id");
    const event = await loadEvent(id, userId(req));
    if (!event) return fail(res, 404, "Event not found", "EVENT_NOT_FOUND");
    return ok(res, { event: toCamel(event) });
  } catch (error) {
    console.error("Get calendar event error:", error);
    return fail(res, 500, "Could not load event");
  }
};

export const createCalendarEvent = async (req, res) => {
  try {
    const parsed = parseEventInput(req.body);
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");
    if (parsed.endAt && parsed.startAt && new Date(parsed.endAt) < new Date(parsed.startAt)) {
      return fail(res, 400, "End time must be after start time");
    }

    const created = await pool.query(
      `INSERT INTO calendar_events (
         user_id, title, description, start_at, end_at, is_all_day, repeat_type, repeat_interval
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       RETURNING calendar_event_id`,
      [
        userId(req),
        parsed.title,
        parsed.description,
        parsed.startAt,
        parsed.endAt ?? null,
        parsed.isAllDay ?? false,
        parsed.repeatType,
        parsed.repeatInterval,
      ]
    );
    const event = await loadEvent(created.rows[0].calendar_event_id, userId(req));
    return ok(res, { event: toCamel(event) }, { status: 201, message: "Event created" });
  } catch (error) {
    console.error("Create calendar event error:", error);
    return fail(res, 500, "Could not create event");
  }
};

export const updateCalendarEvent = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid event id");
    const existing = await loadEvent(id, userId(req));
    if (!existing) return fail(res, 404, "Event not found", "EVENT_NOT_FOUND");

    const parsed = parseEventInput(req.body, { partial: true });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    const startAt = parsed.startAt ?? existing.start_at;
    const endAt = parsed.endAt === undefined ? existing.end_at : parsed.endAt;
    if (endAt && startAt && new Date(endAt) < new Date(startAt)) {
      return fail(res, 400, "End time must be after start time");
    }

    await pool.query(
      `UPDATE calendar_events
       SET title = $1, description = $2, start_at = $3, end_at = $4,
           is_all_day = $5, repeat_type = $6, repeat_interval = $7, updated_at = NOW()
       WHERE calendar_event_id = $8 AND user_id = $9`,
      [
        parsed.title || existing.title,
        parsed.description === undefined ? existing.description : parsed.description,
        startAt,
        endAt,
        parsed.isAllDay === undefined ? existing.is_all_day : parsed.isAllDay,
        parsed.repeatType ?? existing.repeat_type,
        parsed.repeatInterval ?? existing.repeat_interval,
        id,
        userId(req),
      ]
    );
    const event = await loadEvent(id, userId(req));
    return ok(res, { event: toCamel(event) }, { message: "Event updated" });
  } catch (error) {
    console.error("Update calendar event error:", error);
    return fail(res, 500, "Could not update event");
  }
};

export const deleteCalendarEvent = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid event id");
    const deleted = await pool.query(
      `DELETE FROM calendar_events WHERE calendar_event_id = $1 AND user_id = $2 RETURNING calendar_event_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Event not found", "EVENT_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Event deleted" });
  } catch (error) {
    console.error("Delete calendar event error:", error);
    return fail(res, 500, "Could not delete event");
  }
};
