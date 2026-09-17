import { pool } from "../config/db.js";
import {
  asBoolean,
  asDate,
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
import {
  civilDaysBetween,
  MAX_RANGE_DAYS,
  occurrenceJoin,
  parseInstant,
  requestTimeZone,
  shiftCivilDate,
} from "../utils/time.js";

const userId = (req) => req.user.user_id;

const EVENT_COLUMNS = `
  calendar_event_id, user_id, title, description, start_at, end_at,
  is_all_day, repeat_type, repeat_interval, time_zone, created_at, updated_at
`;

const loadEvent = async (eventId, authUserId) => {
  const result = await pool.query(
    `SELECT ${EVENT_COLUMNS}
     FROM calendar_events
     WHERE calendar_event_id = $1 AND user_id = $2`,
    [eventId, authUserId]
  );
  return result.rows[0] || null;
};

const parseEventInput = async (body, { partial = false, timeZone } = {}) => {
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

  const isAllDayValue = pick(body, "isAllDay", "is_all_day");
  const isAllDay = isAllDayValue === undefined ? undefined : asBoolean(isAllDayValue, false);

  const startValue = pick(body, "startAt", "start_at");
  let startAt = startValue === undefined ? undefined : await parseInstant(startValue, timeZone);
  if (!partial && !startAt) return { error: "Start date and time are required" };
  if (startValue !== undefined && startAt === undefined) return { error: "Invalid start date" };

  const endValue = pick(body, "endAt", "end_at");
  let endAt = endValue === undefined ? undefined : await parseInstant(endValue, timeZone);
  if (endValue !== undefined && endAt === undefined) return { error: "Invalid end date" };

  if (isAllDay && startValue != null && /^\d{4}-\d{2}-\d{2}$/.test(String(startValue).trim())) {
    startAt = await parseInstant(`${String(startValue).trim()} 00:00:00`, timeZone);
  }
  if (isAllDay && endValue != null && /^\d{4}-\d{2}-\d{2}$/.test(String(endValue).trim())) {
    endAt = await parseInstant(`${String(endValue).trim()} 23:59:59`, timeZone);
  }

  const repeatValue = pick(body, "repeatType", "repeat_type");
  const repeatType = repeatValue == null ? (partial ? undefined : "none") : asRepeatType(repeatValue);
  if (repeatValue != null && !repeatType) return { error: "Invalid repeat type" };

  const intervalValue = pick(body, "repeatInterval", "repeat_interval");
  const repeatInterval = intervalValue == null ? (partial ? undefined : 1) : asInterval(intervalValue);
  if (intervalValue != null && !repeatInterval) return { error: "Invalid repeat interval" };

  return {
    title: title.value,
    description: description.value,
    startAt,
    endAt,
    repeatType,
    repeatInterval,
    isAllDay,
    timeZone,
  };
};

export const listCalendarEvents = async (req, res) => {
  try {
    const { limit, offset } = parsePagination(req.query);
    const authUserId = userId(req);
    const tz = await requestTimeZone(req);
    const filters = ["e.user_id = $1"];
    const params = [authUserId];

    const search = String(req.query.search || req.query.q || "").trim();
    if (search) {
      params.push(`%${search}%`);
      filters.push(`(e.title ILIKE $${params.length} OR e.description ILIKE $${params.length})`);
    }

    const fromRaw = req.query.from;
    const toRaw = req.query.to;
    const ranged = Boolean(fromRaw || toRaw);
    let tzIdx = null;
    let fromIdx = null;
    let toIdx = null;

    if (ranged) {
      params.push(tz);
      tzIdx = params.length;
      let fromDate = fromRaw ? asDate(fromRaw) : null;
      let toDate = toRaw ? asDate(toRaw) : null;
      if (fromRaw && fromDate === undefined) return fail(res, 400, "from must be YYYY-MM-DD");
      if (toRaw && toDate === undefined) return fail(res, 400, "to must be YYYY-MM-DD");
      if (!fromDate && toDate) fromDate = shiftCivilDate(toDate, -MAX_RANGE_DAYS);
      if (!toDate && fromDate) toDate = shiftCivilDate(fromDate, MAX_RANGE_DAYS);
      if (!fromDate || !toDate) return fail(res, 400, "Invalid date range");
      if (fromDate > toDate) return fail(res, 400, "from must be on or before to");
      if ((civilDaysBetween(fromDate, toDate) ?? 0) > MAX_RANGE_DAYS) {
        return fail(res, 400, "Date range must be at most 366 days");
      }
      params.push(fromDate);
      fromIdx = params.length;
      params.push(toDate);
      toIdx = params.length;
      filters.push(
        `((occ.occ_start + occ.occ_duration) AT TIME ZONE $${tzIdx})::date >= $${fromIdx}`
      );
      filters.push(`(occ.occ_start AT TIME ZONE $${tzIdx})::date <= $${toIdx}`);
    }

    const source = ranged
      ? `calendar_events e ${occurrenceJoin({
          tzParam: `$${tzIdx}`,
          fromDateParam: fromIdx ? `$${fromIdx}` : undefined,
          toDateParam: toIdx ? `$${toIdx}` : undefined,
        })}`
      : "calendar_events e";
    const where = filters.join(" AND ");
    const count = await pool.query(
      `SELECT COUNT(*)::int AS total FROM ${source} WHERE ${where}`,
      params
    );
    params.push(limit, offset);
    const result = await pool.query(
      `SELECT e.calendar_event_id, e.user_id, e.title, e.description,
              ${ranged ? "occ.occ_start AS start_at" : "e.start_at"},
              ${ranged ? "(occ.occ_start + occ.occ_duration) AS end_at" : "e.end_at"},
              e.is_all_day, e.repeat_type, e.repeat_interval, e.time_zone,
              e.created_at, e.updated_at
       FROM ${source}
       WHERE ${where}
       ORDER BY ${ranged ? "occ.occ_start" : "e.start_at"} ASC
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
    const tz = await requestTimeZone(req);
    const parsed = await parseEventInput(req.body, { timeZone: tz });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");
    if (parsed.endAt && parsed.startAt && new Date(parsed.endAt) < new Date(parsed.startAt)) {
      return fail(res, 400, "End time must be after start time");
    }

    const created = await pool.query(
      `INSERT INTO calendar_events (
         user_id, title, description, start_at, end_at, is_all_day, repeat_type, repeat_interval, time_zone
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
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
        tz,
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

    const tz = await requestTimeZone(req);
    const parsed = await parseEventInput(req.body, { partial: true, timeZone: tz });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    const startAt = parsed.startAt ?? existing.start_at;
    const endAt = parsed.endAt === undefined ? existing.end_at : parsed.endAt;
    if (endAt && startAt && new Date(endAt) < new Date(startAt)) {
      return fail(res, 400, "End time must be after start time");
    }

    await pool.query(
      `UPDATE calendar_events
       SET title = $1, description = $2, start_at = $3, end_at = $4,
           is_all_day = $5, repeat_type = $6, repeat_interval = $7,
           time_zone = $8, updated_at = NOW()
       WHERE calendar_event_id = $9 AND user_id = $10`,
      [
        parsed.title || existing.title,
        parsed.description === undefined ? existing.description : parsed.description,
        startAt,
        endAt,
        parsed.isAllDay === undefined ? existing.is_all_day : parsed.isAllDay,
        parsed.repeatType ?? existing.repeat_type,
        parsed.repeatInterval ?? existing.repeat_interval,
        parsed.startAt ? tz : existing.time_zone,
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
