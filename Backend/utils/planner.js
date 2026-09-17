const REPEAT_TYPES = ["none", "daily", "weekly", "monthly", "yearly", "custom"];
const TASK_STATUSES = ["pending", "completed", "archived"];
const TASK_PRIORITIES = ["low", "medium", "high"];
const REMINDER_STATUSES = ["pending", "completed", "cancelled"];
const REMINDER_KINDS = ["reminder", "alarm"];

export const toCamel = (value) => {
  if (value == null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(toCamel);
  if (value instanceof Date) return value.toISOString();

  const out = {};
  for (const [key, item] of Object.entries(value)) {
    const camel = key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
    out[camel] = toCamel(item);
  }
  return out;
};

export const pick = (body = {}, ...keys) => {
  for (const key of keys) {
    if (body[key] !== undefined) return body[key];
  }
  return undefined;
};

export const parseId = (value) => {
  const id = Number.parseInt(String(value), 10);
  return Number.isInteger(id) && id > 0 ? id : null;
};

export const parsePagination = (query = {}) => {
  const limit = Math.min(Math.max(Number.parseInt(query.limit, 10) || 30, 1), 100);
  const offset = Math.max(Number.parseInt(query.offset, 10) || 0, 0);
  return { limit, offset };
};

export const clampText = (value, { required = false, max = 200 } = {}) => {
  const text = value == null ? "" : String(value).trim();
  if (required && !text) return { error: "This field is required" };
  if (text.length > max) return { error: `Must be at most ${max} characters` };
  return { value: text };
};

export const asBoolean = (value, fallback) => {
  if (value === undefined) return fallback;
  if (typeof value === "boolean") return value;
  if (value === "true" || value === 1 || value === "1") return true;
  if (value === "false" || value === 0 || value === "0") return false;
  return fallback;
};

export const asRepeatType = (value, fallback = "none") => {
  const type = String(value || fallback).toLowerCase();
  return REPEAT_TYPES.includes(type) ? type : null;
};

export const asTaskStatus = (value) => {
  const status = String(value || "").toLowerCase();
  return TASK_STATUSES.includes(status) ? status : null;
};

export const asPriority = (value, fallback = "medium") => {
  const priority = String(value || fallback).toLowerCase();
  return TASK_PRIORITIES.includes(priority) ? priority : null;
};

export const asReminderStatus = (value) => {
  const status = String(value || "").toLowerCase();
  return REMINDER_STATUSES.includes(status) ? status : null;
};

export const asReminderKind = (value, fallback = "reminder") => {
  if (value == null || value === "") return fallback;
  const kind = String(value).toLowerCase();
  return REMINDER_KINDS.includes(kind) ? kind : null;
};

export const asDate = (value) => {
  if (value == null || value === "") return null;
  const text = String(value).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return undefined;
  return text;
};

export const asTime = (value) => {
  if (value == null || value === "") return null;
  const text = String(value);
  if (!/^\d{2}:\d{2}(:\d{2})?$/.test(text)) return undefined;
  return text.length === 5 ? `${text}:00` : text;
};

export const asDateTime = (value) => {
  if (value == null || value === "") return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
};

export const asInterval = (value, fallback = 1) => {
  if (value == null || value === "") return fallback;
  const interval = Number.parseInt(value, 10);
  return Number.isInteger(interval) && interval >= 1 ? interval : null;
};

export const nextDateOnly = (from, repeatType, interval = 1) => {
  if (!from || repeatType === "none") return null;
  const [year, month, day] = String(from).slice(0, 10).split("-").map(Number);
  if (!year || !month || !day) return null;
  const n = Math.max(1, interval);
  if (repeatType === "monthly" || repeatType === "yearly") {
    const addMonths = repeatType === "yearly" ? 12 * n : n;
    const total = year * 12 + (month - 1) + addMonths;
    const nextYear = Math.floor(total / 12);
    const nextMonth = total % 12;
    const lastDay = new Date(Date.UTC(nextYear, nextMonth + 1, 0)).getUTCDate();
    const nextDay = Math.min(day, lastDay);
    return `${String(nextYear).padStart(4, "0")}-${String(nextMonth + 1).padStart(2, "0")}-${String(nextDay).padStart(2, "0")}`;
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  if (repeatType === "weekly") date.setUTCDate(date.getUTCDate() + 7 * n);
  else date.setUTCDate(date.getUTCDate() + n);
  return date.toISOString().slice(0, 10);
};

export const formatDueTime = (value) => {
  if (!value) return null;
  if (typeof value === "string") return value.slice(0, 8);
  return value;
};

export const formatDateOnly = (value) => {
  if (!value) return null;
  if (typeof value === "string") {
    const match = value.match(/^(\d{4}-\d{2}-\d{2})/);
    return match ? match[1] : null;
  }
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

export const mapTask = (row, subtasks = []) => {
  if (!row) return null;
  return toCamel({
    ...row,
    due_date: formatDateOnly(row.due_date),
    due_time: formatDueTime(row.due_time),
    subtasks,
  });
};

export const fail = (res, status, message, code) =>
  res.status(status).json({
    success: false,
    message,
    ...(code ? { error: { code, message } } : {}),
  });

export const ok = (res, data, { status = 200, message } = {}) =>
  res.status(status).json({
    success: true,
    ...(message ? { message } : {}),
    data,
  });
