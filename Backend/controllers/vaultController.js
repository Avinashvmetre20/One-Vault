import { pool } from "../config/db.js";
import { asBoolean, clampText, fail, ok, parseId, pick, toCamel } from "../utils/planner.js";

const userId = (req) => req.user.user_id;

const PASSWORD_CATEGORIES = new Set([
  "banking",
  "email",
  "socialMedia",
  "shopping",
  "work",
  "development",
  "servers",
  "wifi",
  "entertainment",
  "other",
]);

const PASSWORD_COLUMNS = `
  password_id, user_id, title, username, password, website, category, notes, tags,
  is_favorite, recovery_email, recovery_phone, two_factor_method, backup_codes,
  security_notes, domain, created_at, updated_at
`;

const asTags = (value) => {
  if (value == null) return [];
  if (!Array.isArray(value)) return null;
  const tags = [
    ...new Set(
      value
        .map((item) => String(item).trim())
        .filter(Boolean)
        .map((item) => item.slice(0, 40))
    ),
  ];
  return tags.slice(0, 20);
};

const parsePasswordInput = (body, { partial = false } = {}) => {
  const titleRaw = pick(body, "title");
  const title =
    titleRaw === undefined && partial
      ? { value: undefined }
      : clampText(titleRaw, { required: !partial, max: 200 });
  if (title.error) return { error: title.error };

  const usernameRaw = pick(body, "username");
  const username =
    usernameRaw === undefined && partial
      ? { value: undefined }
      : clampText(usernameRaw, { max: 255 });
  if (username.error) return { error: username.error };

  const passwordRaw = pick(body, "password");
  const password =
    passwordRaw === undefined && partial
      ? { value: undefined }
      : clampText(passwordRaw, { required: !partial, max: 2000 });
  if (password.error) return { error: password.error };

  const websiteRaw = pick(body, "website");
  const website =
    websiteRaw === undefined && partial
      ? { value: undefined }
      : clampText(websiteRaw, { max: 500 });
  if (website.error) return { error: website.error };

  const notesRaw = pick(body, "notes");
  const notes =
    notesRaw === undefined && partial
      ? { value: undefined }
      : clampText(notesRaw, { max: 5000 });
  if (notes.error) return { error: notes.error };

  const categoryValue = pick(body, "category");
  let category;
  if (categoryValue === undefined) category = undefined;
  else {
    category = String(categoryValue || "other");
    if (!PASSWORD_CATEGORIES.has(category)) return { error: "Invalid category" };
  }

  const tagsValue = pick(body, "tags");
  let tags;
  if (tagsValue === undefined) tags = undefined;
  else {
    tags = asTags(tagsValue);
    if (!tags) return { error: "Invalid tags" };
  }

  const domainRaw = pick(body, "domain");
  const domain =
    domainRaw === undefined && partial
      ? { value: undefined }
      : clampText(domainRaw, { max: 255 });
  if (domain.error) return { error: domain.error };

  return {
    title: title.value,
    username: username.value,
    password: password.value,
    website: website.value,
    category: partial ? category : category || "other",
    notes: notes.value,
    tags,
    isFavorite:
      pick(body, "isFavorite", "is_favorite") === undefined
        ? undefined
        : asBoolean(pick(body, "isFavorite", "is_favorite"), false),
    recoveryEmail: pick(body, "recoveryEmail", "recovery_email"),
    recoveryPhone: pick(body, "recoveryPhone", "recovery_phone"),
    twoFactorMethod: pick(body, "twoFactorMethod", "two_factor_method"),
    backupCodes: pick(body, "backupCodes", "backup_codes"),
    securityNotes: pick(body, "securityNotes", "security_notes"),
    domain: domain.value,
  };
};

const loadPassword = async (passwordId, authUserId) => {
  const result = await pool.query(
    `SELECT ${PASSWORD_COLUMNS}
     FROM passwords
     WHERE password_id = $1 AND user_id = $2`,
    [passwordId, authUserId]
  );
  return result.rows[0] || null;
};

const loadVaultPasscode = async (authUserId) => {
  const result = await pool.query(
    `SELECT vault_passcode FROM users WHERE user_id = $1`,
    [authUserId]
  );
  return result.rows[0]?.vault_passcode ?? null;
};

export const vaultStatus = async (req, res) => {
  try {
    const passcode = await loadVaultPasscode(userId(req));
    return ok(res, { setup: Boolean(passcode) });
  } catch (error) {
    console.error("Vault status error:", error);
    return fail(res, 500, "Could not load vault status");
  }
};

export const setupVault = async (req, res) => {
  try {
    const passcode = String(req.body.passcode || req.body.vaultPasscode || "").trim();
    if (passcode.length < 6) {
      return fail(res, 400, "Vault passcode must be at least 6 characters", "VALIDATION_ERROR");
    }

    const existing = await loadVaultPasscode(userId(req));
    if (existing) {
      return fail(res, 409, "Vault already set up", "VAULT_ALREADY_SETUP");
    }

    await pool.query(
      `UPDATE users
       SET vault_passcode = $1, updated_at = NOW()
       WHERE user_id = $2`,
      [passcode, userId(req)]
    );
    return ok(res, { setup: true }, { status: 201, message: "Vault created" });
  } catch (error) {
    console.error("Setup vault error:", error);
    return fail(res, 500, "Could not set up vault");
  }
};

export const unlockVault = async (req, res) => {
  try {
    const passcode = String(req.body.passcode || req.body.vaultPasscode || "").trim();
    if (!passcode) return fail(res, 400, "Vault passcode is required", "VALIDATION_ERROR");

    const stored = await loadVaultPasscode(userId(req));
    if (!stored) return fail(res, 404, "Vault is not set up", "VAULT_NOT_SETUP");
    if (stored !== passcode) {
      return fail(res, 401, "Wrong vault passcode", "INVALID_VAULT_PASSCODE");
    }
    return ok(res, { unlocked: true }, { message: "Vault unlocked" });
  } catch (error) {
    console.error("Unlock vault error:", error);
    return fail(res, 500, "Could not unlock vault");
  }
};

export const listPasswords = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT ${PASSWORD_COLUMNS}
       FROM passwords
       WHERE user_id = $1
       ORDER BY is_favorite DESC, updated_at DESC`,
      [userId(req)]
    );
    return ok(res, { passwords: result.rows.map(toCamel) });
  } catch (error) {
    console.error("List passwords error:", error);
    return fail(res, 500, "Could not load passwords");
  }
};

export const getPassword = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid password id");
    const row = await loadPassword(id, userId(req));
    if (!row) return fail(res, 404, "Password not found", "PASSWORD_NOT_FOUND");
    return ok(res, { password: toCamel(row) });
  } catch (error) {
    console.error("Get password error:", error);
    return fail(res, 500, "Could not load password");
  }
};

export const createPassword = async (req, res) => {
  try {
    const parsed = parsePasswordInput(req.body);
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    const created = await pool.query(
      `INSERT INTO passwords (
         user_id, title, username, password, website, category, notes, tags,
         is_favorite, recovery_email, recovery_phone, two_factor_method,
         backup_codes, security_notes, domain
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       RETURNING ${PASSWORD_COLUMNS}`,
      [
        userId(req),
        parsed.title,
        parsed.username || "",
        parsed.password || "",
        parsed.website || "",
        parsed.category,
        parsed.notes || "",
        parsed.tags || [],
        parsed.isFavorite ?? false,
        String(parsed.recoveryEmail || "").trim(),
        String(parsed.recoveryPhone || "").trim(),
        String(parsed.twoFactorMethod || "").trim(),
        String(parsed.backupCodes || "").trim(),
        String(parsed.securityNotes || "").trim(),
        parsed.domain || "",
      ]
    );
    return ok(
      res,
      { password: toCamel(created.rows[0]) },
      { status: 201, message: "Password saved" }
    );
  } catch (error) {
    console.error("Create password error:", error);
    return fail(res, 500, "Could not save password");
  }
};

export const updatePassword = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid password id");
    const existing = await loadPassword(id, userId(req));
    if (!existing) return fail(res, 404, "Password not found", "PASSWORD_NOT_FOUND");

    const parsed = parsePasswordInput(req.body, { partial: true });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    const updated = await pool.query(
      `UPDATE passwords
       SET title = $1,
           username = $2,
           password = $3,
           website = $4,
           category = $5,
           notes = $6,
           tags = $7,
           is_favorite = $8,
           recovery_email = $9,
           recovery_phone = $10,
           two_factor_method = $11,
           backup_codes = $12,
           security_notes = $13,
           domain = $14,
           updated_at = NOW()
       WHERE password_id = $15 AND user_id = $16
       RETURNING ${PASSWORD_COLUMNS}`,
      [
        parsed.title || existing.title,
        parsed.username === undefined ? existing.username : parsed.username,
        parsed.password === undefined ? existing.password : parsed.password,
        parsed.website === undefined ? existing.website : parsed.website,
        parsed.category || existing.category,
        parsed.notes === undefined ? existing.notes : parsed.notes,
        parsed.tags === undefined ? existing.tags : parsed.tags,
        parsed.isFavorite === undefined ? existing.is_favorite : parsed.isFavorite,
        parsed.recoveryEmail === undefined
          ? existing.recovery_email
          : String(parsed.recoveryEmail || "").trim(),
        parsed.recoveryPhone === undefined
          ? existing.recovery_phone
          : String(parsed.recoveryPhone || "").trim(),
        parsed.twoFactorMethod === undefined
          ? existing.two_factor_method
          : String(parsed.twoFactorMethod || "").trim(),
        parsed.backupCodes === undefined
          ? existing.backup_codes
          : String(parsed.backupCodes || "").trim(),
        parsed.securityNotes === undefined
          ? existing.security_notes
          : String(parsed.securityNotes || "").trim(),
        parsed.domain === undefined ? existing.domain : parsed.domain,
        id,
        userId(req),
      ]
    );
    return ok(res, { password: toCamel(updated.rows[0]) }, { message: "Password updated" });
  } catch (error) {
    console.error("Update password error:", error);
    return fail(res, 500, "Could not update password");
  }
};

export const deletePassword = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid password id");
    const deleted = await pool.query(
      `DELETE FROM passwords
       WHERE password_id = $1 AND user_id = $2
       RETURNING password_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) {
      return fail(res, 404, "Password not found", "PASSWORD_NOT_FOUND");
    }
    return ok(res, { deleted: true }, { message: "Password deleted" });
  } catch (error) {
    console.error("Delete password error:", error);
    return fail(res, 500, "Could not delete password");
  }
};
