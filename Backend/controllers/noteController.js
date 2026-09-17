import { pool } from "../config/db.js";
import { ensureDefaultPlannerData } from "../db/planner.js";
import {
  asBoolean,
  clampText,
  fail,
  ok,
  parseId,
  parsePagination,
  pick,
  toCamel,
} from "../utils/planner.js";

const userId = (req) => req.user.user_id;

const noteSelect = `
  SELECT n.note_id, n.user_id, n.category_id, n.title, n.content,
         n.is_pinned, n.is_favorite, n.is_archived, n.created_at, n.updated_at,
         c.name AS category_name,
         COALESCE((
           SELECT json_agg(t.name ORDER BY t.name)
           FROM note_tag_mapping m
           JOIN note_tags t ON t.note_tag_id = m.note_tag_id
           WHERE m.note_id = n.note_id
         ), '[]'::json) AS tags
  FROM notes n
  LEFT JOIN note_categories c ON c.note_category_id = n.category_id
`;

const loadNote = async (noteId, authUserId) => {
  const result = await pool.query(
    `${noteSelect} WHERE n.note_id = $1 AND n.user_id = $2`,
    [noteId, authUserId]
  );
  return result.rows[0] || null;
};

const ownedNoteCategory = async (categoryId, authUserId) => {
  if (!categoryId) return true;
  const result = await pool.query(
    `SELECT note_category_id FROM note_categories
     WHERE note_category_id = $1 AND user_id = $2`,
    [categoryId, authUserId]
  );
  return result.rowCount > 0;
};

const syncTags = async (client, authUserId, noteId, tags) => {
  await client.query(`DELETE FROM note_tag_mapping WHERE note_id = $1`, [noteId]);
  const names = [...new Set(tags.map((tag) => String(tag).trim().toLowerCase()).filter(Boolean))];
  for (const name of names) {
    const existing = await client.query(
      `SELECT note_tag_id FROM note_tags WHERE user_id = $1 AND LOWER(name) = $2`,
      [authUserId, name]
    );
    let tagId = existing.rows[0]?.note_tag_id;
    if (!tagId) {
      const created = await client.query(
        `INSERT INTO note_tags (user_id, name) VALUES ($1, $2)
         RETURNING note_tag_id`,
        [authUserId, name]
      );
      tagId = created.rows[0].note_tag_id;
    }
    await client.query(
      `INSERT INTO note_tag_mapping (note_id, note_tag_id)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [noteId, tagId]
    );
  }
};

export const listNoteCategories = async (req, res) => {
  try {
    await ensureDefaultPlannerData(userId(req));
    const result = await pool.query(
      `SELECT note_category_id, user_id, name, created_at, updated_at
       FROM note_categories
       WHERE user_id = $1
       ORDER BY name ASC`,
      [userId(req)]
    );
    return ok(res, { categories: result.rows.map(toCamel) });
  } catch (error) {
    console.error("List note categories error:", error);
    return fail(res, 500, "Could not load categories");
  }
};

export const createNoteCategory = async (req, res) => {
  try {
    const title = clampText(pick(req.body, "name"), { required: true, max: 80 });
    if (title.error) return fail(res, 400, title.error, "VALIDATION_ERROR");
    const created = await pool.query(
      `INSERT INTO note_categories (user_id, name)
       VALUES ($1, $2)
       RETURNING note_category_id, user_id, name, created_at, updated_at`,
      [userId(req), title.value]
    );
    return ok(res, { category: toCamel(created.rows[0]) }, { status: 201, message: "Category created" });
  } catch (error) {
    if (error.code === "23505") return fail(res, 409, "Category already exists", "CATEGORY_EXISTS");
    console.error("Create note category error:", error);
    return fail(res, 500, "Could not create category");
  }
};

export const updateNoteCategory = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid category id");
    const title = clampText(pick(req.body, "name"), { required: true, max: 80 });
    if (title.error) return fail(res, 400, title.error, "VALIDATION_ERROR");
    const updated = await pool.query(
      `UPDATE note_categories
       SET name = $1, updated_at = NOW()
       WHERE note_category_id = $2 AND user_id = $3
       RETURNING note_category_id, user_id, name, created_at, updated_at`,
      [title.value, id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Category not found", "CATEGORY_NOT_FOUND");
    return ok(res, { category: toCamel(updated.rows[0]) }, { message: "Category updated" });
  } catch (error) {
    if (error.code === "23505") return fail(res, 409, "Category already exists", "CATEGORY_EXISTS");
    console.error("Update note category error:", error);
    return fail(res, 500, "Could not update category");
  }
};

export const deleteNoteCategory = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid category id");
    const deleted = await pool.query(
      `DELETE FROM note_categories
       WHERE note_category_id = $1 AND user_id = $2
       RETURNING note_category_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Category not found", "CATEGORY_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Category deleted" });
  } catch (error) {
    console.error("Delete note category error:", error);
    return fail(res, 500, "Could not delete category");
  }
};

export const listNotes = async (req, res) => {
  try {
    const { limit, offset } = parsePagination(req.query);
    const authUserId = userId(req);
    const filters = ["n.user_id = $1"];
    const params = [authUserId];

    const archived = String(req.query.scope || "").toLowerCase() === "archived";
    if (archived) filters.push("n.is_archived = TRUE");
    else filters.push("n.is_archived = FALSE");

    if (asBoolean(req.query.pinned ?? req.query.isPinned, false)) filters.push("n.is_pinned = TRUE");
    if (asBoolean(req.query.favorite ?? req.query.isFavorite, false)) filters.push("n.is_favorite = TRUE");

    const categoryId = req.query.categoryId || req.query.category_id;
    if (categoryId) {
      const id = parseId(categoryId);
      if (!id) return fail(res, 400, "Invalid category id");
      params.push(id);
      filters.push(`n.category_id = $${params.length}`);
    }

    const search = String(req.query.search || req.query.q || "").trim();
    if (search) {
      params.push(`%${search}%`);
      filters.push(`(
        n.title ILIKE $${params.length}
        OR n.content ILIKE $${params.length}
        OR EXISTS (
          SELECT 1 FROM note_tag_mapping m
          JOIN note_tags t ON t.note_tag_id = m.note_tag_id
          WHERE m.note_id = n.note_id AND t.name ILIKE $${params.length}
        )
      )`);
    }

    const where = filters.join(" AND ");
    const count = await pool.query(
      `SELECT COUNT(*)::int AS total FROM notes n WHERE ${where}`,
      params
    );
    params.push(limit, offset);
    const result = await pool.query(
      `${noteSelect}
       WHERE ${where}
       ORDER BY n.is_pinned DESC, n.updated_at DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return ok(res, {
      notes: result.rows.map(toCamel),
      pagination: { limit, offset, total: count.rows[0].total },
    });
  } catch (error) {
    console.error("List notes error:", error);
    return fail(res, 500, "Could not load notes");
  }
};

export const getNote = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid note id");
    const note = await loadNote(id, userId(req));
    if (!note) return fail(res, 404, "Note not found", "NOTE_NOT_FOUND");
    return ok(res, { note: toCamel(note) });
  } catch (error) {
    console.error("Get note error:", error);
    return fail(res, 500, "Could not load note");
  }
};

const parseNoteInput = async (body, authUserId, { partial = false } = {}) => {
  const titleRaw = pick(body, "title");
  const title = titleRaw === undefined && partial
    ? { value: undefined }
    : clampText(titleRaw, { required: !partial, max: 200 });
  if (title.error) return { error: title.error };
  const contentRaw = pick(body, "content");
  const content = contentRaw === undefined && partial
    ? { value: undefined }
    : clampText(contentRaw, { max: 20000 });
  if (content.error) return { error: content.error };

  const categoryValue = pick(body, "categoryId", "category_id");
  let categoryId;
  if (categoryValue === undefined) categoryId = undefined;
  else if (categoryValue == null || categoryValue === "") categoryId = null;
  else categoryId = parseId(categoryValue);
  if (categoryValue != null && categoryValue !== "" && !categoryId) return { error: "Invalid category" };
  if (categoryId && !(await ownedNoteCategory(categoryId, authUserId))) {
    return { error: "Category not found" };
  }

  return {
    title: title.value,
    content: content.value,
    categoryId,
    tags: Array.isArray(body.tags) ? body.tags : undefined,
  };
};

export const createNote = async (req, res) => {
  const client = await pool.connect();
  try {
    const parsed = await parseNoteInput(req.body, userId(req));
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    await client.query("BEGIN");
    const created = await client.query(
      `INSERT INTO notes (user_id, category_id, title, content)
       VALUES ($1, $2, $3, $4)
       RETURNING note_id`,
      [userId(req), parsed.categoryId ?? null, parsed.title, parsed.content]
    );
    const noteId = created.rows[0].note_id;
    if (parsed.tags) await syncTags(client, userId(req), noteId, parsed.tags);
    await client.query("COMMIT");

    const note = await loadNote(noteId, userId(req));
    return ok(res, { note: toCamel(note) }, { status: 201, message: "Note created" });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("Create note error:", error);
    return fail(res, 500, "Could not create note");
  } finally {
    client.release();
  }
};

export const updateNote = async (req, res) => {
  const client = await pool.connect();
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid note id");
    const existing = await loadNote(id, userId(req));
    if (!existing) return fail(res, 404, "Note not found", "NOTE_NOT_FOUND");

    const parsed = await parseNoteInput(req.body, userId(req), { partial: true });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    await client.query("BEGIN");
    await client.query(
      `UPDATE notes
       SET title = $1, content = $2, category_id = $3, updated_at = NOW()
       WHERE note_id = $4 AND user_id = $5`,
      [
        parsed.title || existing.title,
        parsed.content === undefined ? existing.content : parsed.content,
        parsed.categoryId === undefined ? existing.category_id : parsed.categoryId,
        id,
        userId(req),
      ]
    );
    if (parsed.tags) await syncTags(client, userId(req), id, parsed.tags);
    await client.query("COMMIT");

    const note = await loadNote(id, userId(req));
    return ok(res, { note: toCamel(note) }, { message: "Note updated" });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("Update note error:", error);
    return fail(res, 500, "Could not update note");
  } finally {
    client.release();
  }
};

export const deleteNote = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid note id");
    const deleted = await pool.query(
      `DELETE FROM notes WHERE note_id = $1 AND user_id = $2 RETURNING note_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Note not found", "NOTE_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Note deleted" });
  } catch (error) {
    console.error("Delete note error:", error);
    return fail(res, 500, "Could not delete note");
  }
};

const toggleFlag = async (req, res, column) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid note id");
    const existing = await loadNote(id, userId(req));
    if (!existing) return fail(res, 404, "Note not found", "NOTE_NOT_FOUND");

    const next = !existing[column];
    await pool.query(
      `UPDATE notes SET ${column} = $1, updated_at = NOW()
       WHERE note_id = $2 AND user_id = $3`,
      [next, id, userId(req)]
    );
    const note = await loadNote(id, userId(req));
    return ok(res, { note: toCamel(note) });
  } catch (error) {
    console.error("Toggle note flag error:", error);
    return fail(res, 500, "Could not update note");
  }
};

export const pinNote = (req, res) => toggleFlag(req, res, "is_pinned");
export const favoriteNote = (req, res) => toggleFlag(req, res, "is_favorite");

export const archiveNote = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid note id");
    const updated = await pool.query(
      `UPDATE notes SET is_archived = TRUE, updated_at = NOW()
       WHERE note_id = $1 AND user_id = $2 RETURNING note_id`,
      [id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Note not found", "NOTE_NOT_FOUND");
    const note = await loadNote(id, userId(req));
    return ok(res, { note: toCamel(note) }, { message: "Note archived" });
  } catch (error) {
    console.error("Archive note error:", error);
    return fail(res, 500, "Could not archive note");
  }
};

export const restoreNote = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid note id");
    const updated = await pool.query(
      `UPDATE notes SET is_archived = FALSE, updated_at = NOW()
       WHERE note_id = $1 AND user_id = $2 RETURNING note_id`,
      [id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Note not found", "NOTE_NOT_FOUND");
    const note = await loadNote(id, userId(req));
    return ok(res, { note: toCamel(note) }, { message: "Note restored" });
  } catch (error) {
    console.error("Restore note error:", error);
    return fail(res, 500, "Could not restore note");
  }
};
