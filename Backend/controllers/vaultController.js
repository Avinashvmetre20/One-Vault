import { pool } from "../config/db.js";
import { fail, ok, pick, toCamel } from "../utils/planner.js";

const userId = (req) => req.user.user_id;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const parseUuid = (value) => {
  const id = String(value || "").trim();
  return UUID_RE.test(id) ? id : null;
};

const asPositiveInt = (value, fallback) => {
  if (value == null || value === "") return fallback;
  const n = Number.parseInt(value, 10);
  return Number.isInteger(n) && n > 0 ? n : null;
};

const requireCiphertext = (value, label) => {
  const text = String(value || "").trim();
  if (!text) return { error: `${label} is required` };
  if (text.length > 200000) return { error: `${label} is too large` };
  return { value: text };
};

export const getVaultMeta = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT user_id, kdf, kdf_memory, kdf_iterations, kdf_parallelism,
              salt, wrapped_dek, wrapped_dek_nonce, created_at, updated_at
       FROM vault_meta
       WHERE user_id = $1`,
      [userId(req)]
    );
    if (!result.rowCount) {
      return ok(res, { meta: null });
    }
    return ok(res, { meta: toCamel(result.rows[0]) });
  } catch (error) {
    console.error("Get vault meta error:", error);
    return fail(res, 500, "Could not load vault");
  }
};

export const putVaultMeta = async (req, res) => {
  try {
    const salt = requireCiphertext(pick(req.body, "salt"), "Salt");
    if (salt.error) return fail(res, 400, salt.error, "VALIDATION_ERROR");
    const wrappedDek = requireCiphertext(
      pick(req.body, "wrappedDek", "wrapped_dek"),
      "Wrapped key"
    );
    if (wrappedDek.error) return fail(res, 400, wrappedDek.error, "VALIDATION_ERROR");
    const wrappedNonce = requireCiphertext(
      pick(req.body, "wrappedDekNonce", "wrapped_dek_nonce"),
      "Wrapped key nonce"
    );
    if (wrappedNonce.error) {
      return fail(res, 400, wrappedNonce.error, "VALIDATION_ERROR");
    }

    const kdf = String(pick(req.body, "kdf") || "argon2id");
    if (kdf !== "argon2id") return fail(res, 400, "Unsupported KDF", "VALIDATION_ERROR");

    const memory = asPositiveInt(pick(req.body, "kdfMemory", "kdf_memory"), 8192);
    const iterations = asPositiveInt(
      pick(req.body, "kdfIterations", "kdf_iterations"),
      3
    );
    const parallelism = asPositiveInt(
      pick(req.body, "kdfParallelism", "kdf_parallelism"),
      1
    );
    if (!memory || !iterations || !parallelism) {
      return fail(res, 400, "Invalid KDF parameters", "VALIDATION_ERROR");
    }

    const existing = await pool.query(
      `SELECT user_id FROM vault_meta WHERE user_id = $1`,
      [userId(req)]
    );

    if (existing.rowCount) {
      const updated = await pool.query(
        `UPDATE vault_meta
         SET kdf = $2,
             kdf_memory = $3,
             kdf_iterations = $4,
             kdf_parallelism = $5,
             salt = $6,
             wrapped_dek = $7,
             wrapped_dek_nonce = $8,
             updated_at = NOW()
         WHERE user_id = $1
         RETURNING user_id, kdf, kdf_memory, kdf_iterations, kdf_parallelism,
                   salt, wrapped_dek, wrapped_dek_nonce, created_at, updated_at`,
        [
          userId(req),
          kdf,
          memory,
          iterations,
          parallelism,
          salt.value,
          wrappedDek.value,
          wrappedNonce.value,
        ]
      );
      return ok(res, { meta: toCamel(updated.rows[0]) }, { message: "Vault updated" });
    }

    const created = await pool.query(
      `INSERT INTO vault_meta (
         user_id, kdf, kdf_memory, kdf_iterations, kdf_parallelism,
         salt, wrapped_dek, wrapped_dek_nonce
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING user_id, kdf, kdf_memory, kdf_iterations, kdf_parallelism,
                 salt, wrapped_dek, wrapped_dek_nonce, created_at, updated_at`,
      [
        userId(req),
        kdf,
        memory,
        iterations,
        parallelism,
        salt.value,
        wrappedDek.value,
        wrappedNonce.value,
      ]
    );
    return ok(
      res,
      { meta: toCamel(created.rows[0]) },
      { status: 201, message: "Vault created" }
    );
  } catch (error) {
    console.error("Put vault meta error:", error);
    return fail(res, 500, "Could not save vault");
  }
};

export const listVaultCredentials = async (req, res) => {
  try {
    const includeDeleted =
      String(req.query.includeDeleted || req.query.include_deleted || "")
        .toLowerCase() === "true";
    const result = await pool.query(
      `SELECT credential_id, user_id, encrypted_payload, nonce, version,
              created_at, updated_at, deleted_at
       FROM vault_credentials
       WHERE user_id = $1
         ${includeDeleted ? "" : "AND deleted_at IS NULL"}
       ORDER BY updated_at DESC`,
      [userId(req)]
    );
    return ok(res, { credentials: result.rows.map(toCamel) });
  } catch (error) {
    console.error("List vault credentials error:", error);
    return fail(res, 500, "Could not load credentials");
  }
};

export const upsertVaultCredential = async (req, res) => {
  try {
    const id = parseUuid(req.params.id);
    if (!id) return fail(res, 400, "Invalid credential id");

    const payload = requireCiphertext(
      pick(req.body, "encryptedPayload", "encrypted_payload"),
      "Encrypted payload"
    );
    if (payload.error) return fail(res, 400, payload.error, "VALIDATION_ERROR");
    const nonce = requireCiphertext(pick(req.body, "nonce"), "Nonce");
    if (nonce.error) return fail(res, 400, nonce.error, "VALIDATION_ERROR");

    const version = asPositiveInt(pick(req.body, "version"), 1);
    if (!version) return fail(res, 400, "Invalid version", "VALIDATION_ERROR");

    const deletedRaw = pick(req.body, "deletedAt", "deleted_at");
    const deletedAt = deletedRaw ? new Date(deletedRaw) : null;
    if (deletedRaw && Number.isNaN(deletedAt?.getTime())) {
      return fail(res, 400, "Invalid deletedAt", "VALIDATION_ERROR");
    }

    const existing = await pool.query(
      `SELECT version FROM vault_credentials
       WHERE credential_id = $1 AND user_id = $2`,
      [id, userId(req)]
    );

    if (existing.rowCount && existing.rows[0].version > version) {
      return fail(
        res,
        409,
        "A newer version of this credential already exists",
        "VERSION_CONFLICT"
      );
    }

    const saved = await pool.query(
      `INSERT INTO vault_credentials (
         credential_id, user_id, encrypted_payload, nonce, version, deleted_at
       ) VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (credential_id) DO UPDATE
         SET encrypted_payload = EXCLUDED.encrypted_payload,
             nonce = EXCLUDED.nonce,
             version = EXCLUDED.version,
             deleted_at = EXCLUDED.deleted_at,
             updated_at = NOW()
         WHERE vault_credentials.user_id = $2
           AND vault_credentials.version <= EXCLUDED.version
       RETURNING credential_id, user_id, encrypted_payload, nonce, version,
                 created_at, updated_at, deleted_at`,
      [id, userId(req), payload.value, nonce.value, version, deletedAt]
    );

    if (!saved.rowCount) {
      return fail(res, 409, "Credential could not be saved", "VERSION_CONFLICT");
    }

    return ok(res, { credential: toCamel(saved.rows[0]) });
  } catch (error) {
    console.error("Upsert vault credential error:", error);
    return fail(res, 500, "Could not save credential");
  }
};

export const deleteVaultCredential = async (req, res) => {
  try {
    const id = parseUuid(req.params.id);
    if (!id) return fail(res, 400, "Invalid credential id");

    const deleted = await pool.query(
      `UPDATE vault_credentials
       SET deleted_at = NOW(),
           version = version + 1,
           updated_at = NOW()
       WHERE credential_id = $1 AND user_id = $2 AND deleted_at IS NULL
       RETURNING credential_id, version, deleted_at`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) {
      return fail(res, 404, "Credential not found", "CREDENTIAL_NOT_FOUND");
    }
    return ok(res, { deleted: true, credential: toCamel(deleted.rows[0]) });
  } catch (error) {
    console.error("Delete vault credential error:", error);
    return fail(res, 500, "Could not delete credential");
  }
};
