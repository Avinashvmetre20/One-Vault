import { pool } from "../config/db.js";

export const DEFAULT_TIME_ZONE = "Asia/Kolkata";

const TZ_RE = /^(UTC|GMT|[A-Za-z_]+(?:\/[A-Za-z0-9_+-]+)+)$/;
const CIVIL_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const WALL_RE = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;

let zoneCache = null;

export const loadTimeZones = async () => {
  if (zoneCache) return zoneCache;
  const result = await pool.query("SELECT name FROM pg_timezone_names");
  zoneCache = new Set(result.rows.map((row) => row.name));
  zoneCache.add("UTC");
  zoneCache.add("GMT");
  return zoneCache;
};

export const isValidTimeZone = async (name) => {
  const zones = await loadTimeZones();
  return zones.has(name);
};

export const requestTimeZone = async (req) => {
  const raw = String(
    req.headers["x-timezone"] || req.query.timezone || DEFAULT_TIME_ZONE
  ).trim();
  if (!TZ_RE.test(raw)) return DEFAULT_TIME_ZONE;
  return (await isValidTimeZone(raw)) ? raw : DEFAULT_TIME_ZONE;
};

const hasOffset = (text) => /Z|[+-]\d{2}:?\d{2}$/.test(text);

const padWall = (text) => {
  const wall = text.replace("T", " ").replace(/\.\d+$/, "");
  if (wall.length === 10) return `${wall} 00:00:00`;
  if (wall.length === 16) return `${wall}:00`;
  return wall.slice(0, 19);
};

const toIso = (value) => {
  if (value == null) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? undefined : value.toISOString();
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
};

export const parseInstant = async (value, timeZone = DEFAULT_TIME_ZONE) => {
  if (value == null || value === "") return null;
  if (value instanceof Date) return toIso(value);
  const text = String(value).trim();
  if (!text) return null;

  if (hasOffset(text)) {
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
  }

  const padded = padWall(text);
  if (!WALL_RE.test(padded)) return undefined;
  if (!(await isValidTimeZone(timeZone))) return undefined;

  try {
    const result = await pool.query(
      `SELECT (to_timestamp($1, 'YYYY-MM-DD HH24:MI:SS')::timestamp AT TIME ZONE $2) AS utc`,
      [padded, timeZone]
    );
    return toIso(result.rows[0]?.utc);
  } catch {
    return undefined;
  }
};

export const parseRangeBound = async (value, timeZone, { endOfDay = false } = {}) => {
  if (value == null || value === "") return null;
  const text = String(value).trim();
  if (CIVIL_DATE_RE.test(text)) {
    const wall = endOfDay ? `${text} 23:59:59` : `${text} 00:00:00`;
    return parseInstant(wall, timeZone);
  }
  return parseInstant(text, timeZone);
};

export const localToday = async (timeZone = DEFAULT_TIME_ZONE) => {
  const result = await pool.query(
    `SELECT (NOW() AT TIME ZONE $1)::date::text AS today`,
    [timeZone]
  );
  return result.rows[0].today;
};

export const MAX_RANGE_DAYS = 366;
export const MAX_OCCURRENCES = 400;

export const civilDaysBetween = (from, to) => {
  const start = Date.parse(`${from}T00:00:00Z`);
  const end = Date.parse(`${to}T00:00:00Z`);
  if (Number.isNaN(start) || Number.isNaN(end)) return null;
  return Math.round((end - start) / 86400000);
};

export const shiftCivilDate = (ymd, days) => {
  const [year, month, day] = String(ymd).split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return date.toISOString().slice(0, 10);
};

export const nextInstant = async (
  from,
  repeatType,
  interval,
  timeZone,
  { after = null } = {}
) => {
  if (!from || repeatType === "none") return null;
  const n = Math.max(1, Number(interval) || 1);
  const amount = repeatType === "weekly" ? 7 * n : n;
  const unit =
    repeatType === "monthly" ? "months" : repeatType === "yearly" ? "years" : "days";
  const step =
    unit === "months"
      ? "make_interval(months => $3::int * g.n)"
      : unit === "years"
        ? "make_interval(years => $3::int * g.n)"
        : "make_interval(days => $3::int * g.n)";
  const guess =
    unit === "months"
      ? `GREATEST(1, ((EXTRACT(YEAR FROM after_local) - EXTRACT(YEAR FROM start_local)) * 12
          + (EXTRACT(MONTH FROM after_local) - EXTRACT(MONTH FROM start_local)))::int / $3)`
      : unit === "years"
        ? `GREATEST(1, (EXTRACT(YEAR FROM after_local) - EXTRACT(YEAR FROM start_local))::int / $3)`
        : `GREATEST(1, CEIL((after_local::date - start_local::date)::numeric / $3)::int)`;

  const result = await pool.query(
    `WITH local AS (
       SELECT
         ($1::timestamptz AT TIME ZONE $2) AS start_local,
         (COALESCE($4::timestamptz, $1::timestamptz) AT TIME ZONE $2) AS after_local,
         $2::text AS tz,
         COALESCE($4::timestamptz, $1::timestamptz) AS after_at
     ),
     guess AS (
       SELECT *, ${guess} AS n0 FROM local
     )
     SELECT occ AS next_at
     FROM guess
     CROSS JOIN generate_series(GREATEST(guess.n0 - 2, 1), guess.n0 + 6) AS g(n)
     CROSS JOIN LATERAL (
       SELECT ((guess.start_local + ${step}) AT TIME ZONE guess.tz) AS occ
     ) s
     WHERE occ > guess.after_at
     ORDER BY occ
     LIMIT 1`,
    [from, timeZone || DEFAULT_TIME_ZONE, amount, after]
  );
  return result.rows[0]?.next_at ?? null;
};

export const occurrenceJoin = ({
  start = "e.start_at",
  end = "e.end_at",
  repeat = "e.repeat_type",
  interval = "e.repeat_interval",
  zone = "e.time_zone",
  tzParam,
  fromDateParam,
  toDateParam,
} = {}) => {
  const zoneExpr = `COALESCE(NULLIF(${zone}, ''), ${tzParam})`;
  const startLocal = `(${start} AT TIME ZONE ${zoneExpr})`;
  const span = (dateParam, mode) => {
    const fn = mode === "floor" ? "FLOOR" : "CEIL";
    return `${fn}(CASE COALESCE(${repeat}, 'none')
         WHEN 'yearly' THEN (EXTRACT(YEAR FROM ${dateParam}::date) - EXTRACT(YEAR FROM ${startLocal})) / GREATEST(${interval}, 1)
         WHEN 'monthly' THEN ((EXTRACT(YEAR FROM ${dateParam}::date) - EXTRACT(YEAR FROM ${startLocal})) * 12
           + (EXTRACT(MONTH FROM ${dateParam}::date) - EXTRACT(MONTH FROM ${startLocal}))) / GREATEST(${interval}, 1)
         WHEN 'weekly' THEN (${dateParam}::date - ${startLocal}::date)::numeric / (7 * GREATEST(${interval}, 1))
         ELSE (${dateParam}::date - ${startLocal}::date)::numeric / GREATEST(${interval}, 1)
       END)`;
  };

  const nStart = fromDateParam
    ? `CASE COALESCE(${repeat}, 'none') WHEN 'none' THEN 0 ELSE GREATEST(0, ${span(fromDateParam, "floor")}::int - 1) END`
    : "0";
  const nEndUncapped = toDateParam
    ? `CASE COALESCE(${repeat}, 'none') WHEN 'none' THEN 0 ELSE GREATEST(0, ${span(toDateParam, "ceil")}::int + 2) END`
    : `CASE COALESCE(${repeat}, 'none')
         WHEN 'none' THEN 0
         WHEN 'yearly' THEN 40
         WHEN 'monthly' THEN 120
         ELSE ${MAX_OCCURRENCES}
       END`;
  const nEnd = `LEAST(${nEndUncapped}, (${nStart}) + ${MAX_OCCURRENCES})`;

  return `
CROSS JOIN LATERAL (
  SELECT ${nStart} AS n_start, ${nEnd} AS n_end
) occ_bounds
CROSS JOIN LATERAL generate_series(
  LEAST(occ_bounds.n_start, occ_bounds.n_end),
  GREATEST(occ_bounds.n_start, occ_bounds.n_end)
) AS occ_n(n)
CROSS JOIN LATERAL (
  SELECT
    ((${startLocal}
      + CASE
          WHEN COALESCE(${repeat}, 'none') = 'none' OR occ_n.n <= 0 THEN INTERVAL '0'
          WHEN ${repeat} = 'monthly' THEN make_interval(months => GREATEST(${interval}, 1) * occ_n.n)
          WHEN ${repeat} = 'yearly' THEN make_interval(years => GREATEST(${interval}, 1) * occ_n.n)
          WHEN ${repeat} = 'weekly' THEN make_interval(days => 7 * GREATEST(${interval}, 1) * occ_n.n)
          ELSE make_interval(days => GREATEST(${interval}, 1) * occ_n.n)
        END
     ) AT TIME ZONE ${zoneExpr}) AS occ_start,
    (COALESCE(${end}, ${start}) - ${start}) AS occ_duration
) occ`;
};
