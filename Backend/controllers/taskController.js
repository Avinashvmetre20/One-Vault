import { pool } from "../config/db.js";
import { ensureDefaultPlannerData } from "../db/planner.js";
import {
  asBoolean,
  asDate,
  asInterval,
  asPriority,
  asRepeatType,
  asTaskStatus,
  asTime,
  clampText,
  fail,
  mapTask,
  nextDateOnly,
  ok,
  parseId,
  parsePagination,
  pick,
  toCamel,
} from "../utils/planner.js";

const userId = (req) => req.user.user_id;

const TASK_COLUMNS = `
  t.task_id, t.user_id, t.category_id, t.title, t.description, t.status, t.priority,
  t.due_date, t.due_time, t.repeat_type, t.repeat_interval, t.is_favorite,
  t.is_archived, t.created_at, t.updated_at, t.completed_at,
  c.name AS category_name
`;

const loadTask = async (taskId, authUserId) => {
  const result = await pool.query(
    `SELECT ${TASK_COLUMNS}
     FROM tasks t
     LEFT JOIN task_categories c ON c.task_category_id = t.category_id
     WHERE t.task_id = $1 AND t.user_id = $2`,
    [taskId, authUserId]
  );
  return result.rows[0] || null;
};

const loadSubtasks = async (taskId) => {
  const result = await pool.query(
    `SELECT task_subtask_id, task_id, title, is_completed, position, created_at, completed_at
     FROM task_subtasks
     WHERE task_id = $1
     ORDER BY position ASC, task_subtask_id ASC`,
    [taskId]
  );
  return result.rows;
};

const ownedCategory = async (categoryId, authUserId) => {
  if (!categoryId) return true;
  const result = await pool.query(
    `SELECT task_category_id FROM task_categories
     WHERE task_category_id = $1 AND user_id = $2`,
    [categoryId, authUserId]
  );
  return result.rowCount > 0;
};

export const listTaskCategories = async (req, res) => {
  try {
    await ensureDefaultPlannerData(userId(req));
    const result = await pool.query(
      `SELECT task_category_id, user_id, name, created_at, updated_at
       FROM task_categories
       WHERE user_id = $1
       ORDER BY name ASC`,
      [userId(req)]
    );
    return ok(res, { categories: result.rows.map(toCamel) });
  } catch (error) {
    console.error("List task categories error:", error);
    return fail(res, 500, "Could not load categories");
  }
};

export const createTaskCategory = async (req, res) => {
  try {
    const title = clampText(pick(req.body, "name"), { required: true, max: 80 });
    if (title.error) return fail(res, 400, title.error, "VALIDATION_ERROR");

    const created = await pool.query(
      `INSERT INTO task_categories (user_id, name)
       VALUES ($1, $2)
       RETURNING task_category_id, user_id, name, created_at, updated_at`,
      [userId(req), title.value]
    );
    return ok(res, { category: toCamel(created.rows[0]) }, { status: 201, message: "Category created" });
  } catch (error) {
    if (error.code === "23505") {
      return fail(res, 409, "Category already exists", "CATEGORY_EXISTS");
    }
    console.error("Create task category error:", error);
    return fail(res, 500, "Could not create category");
  }
};

export const updateTaskCategory = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid category id");

    const title = clampText(pick(req.body, "name"), { required: true, max: 80 });
    if (title.error) return fail(res, 400, title.error, "VALIDATION_ERROR");

    const updated = await pool.query(
      `UPDATE task_categories
       SET name = $1, updated_at = NOW()
       WHERE task_category_id = $2 AND user_id = $3
       RETURNING task_category_id, user_id, name, created_at, updated_at`,
      [title.value, id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Category not found", "CATEGORY_NOT_FOUND");
    return ok(res, { category: toCamel(updated.rows[0]) }, { message: "Category updated" });
  } catch (error) {
    if (error.code === "23505") {
      return fail(res, 409, "Category already exists", "CATEGORY_EXISTS");
    }
    console.error("Update task category error:", error);
    return fail(res, 500, "Could not update category");
  }
};

export const deleteTaskCategory = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid category id");

    const deleted = await pool.query(
      `DELETE FROM task_categories
       WHERE task_category_id = $1 AND user_id = $2
       RETURNING task_category_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Category not found", "CATEGORY_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Category deleted" });
  } catch (error) {
    console.error("Delete task category error:", error);
    return fail(res, 500, "Could not delete category");
  }
};

export const listTasks = async (req, res) => {
  try {
    const { limit, offset } = parsePagination(req.query);
    const authUserId = userId(req);
    const filters = ["t.user_id = $1"];
    const params = [authUserId];

    const status = req.query.status ? asTaskStatus(req.query.status) : null;
    if (req.query.status && !status) return fail(res, 400, "Invalid status");
    if (status) {
      params.push(status);
      filters.push(`t.status = $${params.length}`);
    } else if (req.query.scope !== "archived") {
      filters.push(`t.is_archived = FALSE`);
      filters.push(`t.status <> 'archived'`);
    }

    const priority = req.query.priority ? asPriority(req.query.priority) : null;
    if (req.query.priority && !priority) return fail(res, 400, "Invalid priority");
    if (priority) {
      params.push(priority);
      filters.push(`t.priority = $${params.length}`);
    }

    const categoryId = req.query.categoryId || req.query.category_id;
    if (categoryId) {
      const id = parseId(categoryId);
      if (!id) return fail(res, 400, "Invalid category id");
      params.push(id);
      filters.push(`t.category_id = $${params.length}`);
    }

    if (asBoolean(req.query.favorite ?? req.query.isFavorite, false)) {
      filters.push("t.is_favorite = TRUE");
    }

    const search = String(req.query.search || req.query.q || "").trim();
    if (search) {
      params.push(`%${search}%`);
      filters.push(`(t.title ILIKE $${params.length} OR t.description ILIKE $${params.length})`);
    }

    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    if (from === undefined || to === undefined) return fail(res, 400, "Invalid date range");
    if (from) {
      params.push(from);
      filters.push(`t.due_date >= $${params.length}`);
    }
    if (to) {
      params.push(to);
      filters.push(`t.due_date <= $${params.length}`);
    }

    const scope = String(req.query.scope || req.query.due || "").toLowerCase();
    if (scope === "today") {
      filters.push("t.due_date = CURRENT_DATE");
      filters.push("t.status = 'pending'");
    } else if (scope === "upcoming") {
      filters.push("t.due_date > CURRENT_DATE");
      filters.push("t.status = 'pending'");
    } else if (scope === "overdue") {
      filters.push("t.due_date < CURRENT_DATE");
      filters.push("t.status = 'pending'");
    } else if (scope === "completed" || scope === "done") {
      filters.push("t.status = 'completed'");
    } else if (scope === "archived") {
      filters.push("(t.status = 'archived' OR t.is_archived = TRUE)");
    }

    const where = filters.join(" AND ");
    const count = await pool.query(
      `SELECT COUNT(*)::int AS total FROM tasks t WHERE ${where}`,
      params
    );

    params.push(limit, offset);
    const result = await pool.query(
      `SELECT ${TASK_COLUMNS}
       FROM tasks t
       LEFT JOIN task_categories c ON c.task_category_id = t.category_id
       WHERE ${where}
       ORDER BY
         CASE t.priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
         t.due_date NULLS LAST,
         t.created_at DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return ok(res, {
      tasks: result.rows.map((row) => mapTask(row)),
      pagination: { limit, offset, total: count.rows[0].total },
    });
  } catch (error) {
    console.error("List tasks error:", error);
    return fail(res, 500, "Could not load tasks");
  }
};

export const getTask = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid task id");

    const task = await loadTask(id, userId(req));
    if (!task) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");
    const subtasks = await loadSubtasks(id);
    return ok(res, { task: mapTask(task, subtasks.map(toCamel)) });
  } catch (error) {
    console.error("Get task error:", error);
    return fail(res, 500, "Could not load task");
  }
};

const parseTaskInput = async (body, authUserId, { partial = false } = {}) => {
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

  const priorityValue = pick(body, "priority");
  const priority = priorityValue == null ? (partial ? undefined : "medium") : asPriority(priorityValue);
  if (priorityValue != null && !priority) return { error: "Invalid priority" };

  const repeatValue = pick(body, "repeatType", "repeat_type");
  const repeatType = repeatValue == null ? (partial ? undefined : "none") : asRepeatType(repeatValue);
  if (repeatValue != null && !repeatType) return { error: "Invalid repeat type" };

  const intervalValue = pick(body, "repeatInterval", "repeat_interval");
  const repeatInterval = intervalValue == null ? (partial ? undefined : 1) : asInterval(intervalValue);
  if (intervalValue != null && !repeatInterval) return { error: "Invalid repeat interval" };

  const dueDateValue = pick(body, "dueDate", "due_date");
  const dueDate = dueDateValue === undefined ? undefined : asDate(dueDateValue);
  if (dueDate === undefined && dueDateValue !== undefined) return { error: "Invalid due date" };

  const dueTimeValue = pick(body, "dueTime", "due_time");
  const dueTime = dueTimeValue === undefined ? undefined : asTime(dueTimeValue);
  if (dueTime === undefined && dueTimeValue !== undefined) return { error: "Invalid due time" };

  const categoryValue = pick(body, "categoryId", "category_id");
  let categoryId;
  if (categoryValue === undefined) categoryId = undefined;
  else if (categoryValue == null || categoryValue === "") categoryId = null;
  else categoryId = parseId(categoryValue);
  if (categoryValue != null && categoryValue !== "" && !categoryId) return { error: "Invalid category" };
  if (categoryId && !(await ownedCategory(categoryId, authUserId))) {
    return { error: "Category not found" };
  }

  const isFavorite = pick(body, "isFavorite", "is_favorite");

  return {
    title: title.value,
    description: description.value,
    priority,
    repeatType,
    repeatInterval,
    dueDate,
    dueTime,
    categoryId,
    isFavorite: isFavorite === undefined ? undefined : asBoolean(isFavorite, false),
  };
};

export const createTask = async (req, res) => {
  const client = await pool.connect();
  try {
    const parsed = await parseTaskInput(req.body, userId(req));
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    await client.query("BEGIN");
    const created = await client.query(
      `INSERT INTO tasks (
         user_id, category_id, title, description, priority, due_date, due_time,
         repeat_type, repeat_interval, is_favorite
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING task_id`,
      [
        userId(req),
        parsed.categoryId ?? null,
        parsed.title,
        parsed.description,
        parsed.priority,
        parsed.dueDate ?? null,
        parsed.dueTime ?? null,
        parsed.repeatType,
        parsed.repeatInterval,
        parsed.isFavorite ?? false,
      ]
    );
    const taskId = created.rows[0].task_id;
    const subtasks = Array.isArray(req.body.subtasks) ? req.body.subtasks : [];
    for (let i = 0; i < subtasks.length; i += 1) {
      const item = subtasks[i];
      const title = clampText(typeof item === "string" ? item : item?.title, {
        required: true,
        max: 200,
      });
      if (title.error) {
        await client.query("ROLLBACK");
        return fail(res, 400, title.error, "VALIDATION_ERROR");
      }
      await client.query(
        `INSERT INTO task_subtasks (task_id, title, position)
         VALUES ($1, $2, $3)`,
        [taskId, title.value, i]
      );
    }
    await client.query("COMMIT");

    const task = await loadTask(taskId, userId(req));
    const loadedSubtasks = await loadSubtasks(taskId);
    return ok(
      res,
      { task: mapTask(task, loadedSubtasks.map(toCamel)) },
      { status: 201, message: "Task created" }
    );
  } catch (error) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("Create task error:", error);
    return fail(res, 500, "Could not create task");
  } finally {
    client.release();
  }
};

export const updateTask = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid task id");
    const existing = await loadTask(id, userId(req));
    if (!existing) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");

    const parsed = await parseTaskInput(req.body, userId(req), { partial: true });
    if (parsed.error) return fail(res, 400, parsed.error, "VALIDATION_ERROR");

    const next = {
      title: parsed.title || existing.title,
      description: parsed.description === undefined ? existing.description : parsed.description,
      priority: parsed.priority ?? existing.priority,
      dueDate: parsed.dueDate === undefined ? existing.due_date : parsed.dueDate,
      dueTime: parsed.dueTime === undefined ? existing.due_time : parsed.dueTime,
      repeatType: parsed.repeatType ?? existing.repeat_type,
      repeatInterval: parsed.repeatInterval ?? existing.repeat_interval,
      categoryId: parsed.categoryId === undefined ? existing.category_id : parsed.categoryId,
      isFavorite: parsed.isFavorite === undefined ? existing.is_favorite : parsed.isFavorite,
    };

    await pool.query(
      `UPDATE tasks
       SET title = $1, description = $2, priority = $3, due_date = $4, due_time = $5,
           repeat_type = $6, repeat_interval = $7, category_id = $8, is_favorite = $9,
           updated_at = NOW()
       WHERE task_id = $10 AND user_id = $11`,
      [
        next.title,
        next.description,
        next.priority,
        next.dueDate,
        next.dueTime,
        next.repeatType,
        next.repeatInterval,
        next.categoryId,
        next.isFavorite,
        id,
        userId(req),
      ]
    );

    const task = await loadTask(id, userId(req));
    const subtasks = await loadSubtasks(id);
    return ok(res, { task: mapTask(task, subtasks.map(toCamel)) }, { message: "Task updated" });
  } catch (error) {
    console.error("Update task error:", error);
    return fail(res, 500, "Could not update task");
  }
};

export const deleteTask = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid task id");
    const deleted = await pool.query(
      `DELETE FROM tasks WHERE task_id = $1 AND user_id = $2 RETURNING task_id`,
      [id, userId(req)]
    );
    if (!deleted.rowCount) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Task deleted" });
  } catch (error) {
    console.error("Delete task error:", error);
    return fail(res, 500, "Could not delete task");
  }
};

export const completeTask = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid task id");
    const existing = await loadTask(id, userId(req));
    if (!existing) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");

    const reopen = asBoolean(pick(req.body, "reopen"), existing.status === "completed");
    if (reopen) {
      await pool.query(
        `UPDATE tasks
         SET status = 'pending', is_archived = FALSE, completed_at = NULL, updated_at = NOW()
         WHERE task_id = $1 AND user_id = $2`,
        [id, userId(req)]
      );
    } else if (existing.repeat_type && existing.repeat_type !== "none") {
      const baseDate = existing.due_date
        ? String(existing.due_date).slice(0, 10)
        : new Date().toISOString().slice(0, 10);
      const nextDue = nextDateOnly(baseDate, existing.repeat_type, existing.repeat_interval);
      await pool.query(
        `UPDATE tasks
         SET status = 'pending', due_date = $1, completed_at = NULL, updated_at = NOW()
         WHERE task_id = $2 AND user_id = $3`,
        [nextDue, id, userId(req)]
      );
    } else {
      await pool.query(
        `UPDATE tasks
         SET status = 'completed', completed_at = NOW(), updated_at = NOW()
         WHERE task_id = $1 AND user_id = $2`,
        [id, userId(req)]
      );
      await pool.query(
        `UPDATE reminders
         SET status = 'cancelled', snoozed_until = NULL, updated_at = NOW()
         WHERE task_id = $1 AND user_id = $2 AND status = 'pending'`,
        [id, userId(req)]
      );
    }

    const task = await loadTask(id, userId(req));
    const subtasks = await loadSubtasks(id);
    return ok(res, { task: mapTask(task, subtasks.map(toCamel)) }, { message: "Task updated" });
  } catch (error) {
    console.error("Complete task error:", error);
    return fail(res, 500, "Could not update task");
  }
};

export const archiveTask = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid task id");
    const updated = await pool.query(
      `UPDATE tasks
       SET status = 'archived', is_archived = TRUE, updated_at = NOW()
       WHERE task_id = $1 AND user_id = $2
       RETURNING task_id`,
      [id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");
    const task = await loadTask(id, userId(req));
    const subtasks = await loadSubtasks(id);
    return ok(res, { task: mapTask(task, subtasks.map(toCamel)) }, { message: "Task archived" });
  } catch (error) {
    console.error("Archive task error:", error);
    return fail(res, 500, "Could not archive task");
  }
};

export const restoreTask = async (req, res) => {
  try {
    const id = parseId(req.params.id);
    if (!id) return fail(res, 400, "Invalid task id");
    const updated = await pool.query(
      `UPDATE tasks
       SET status = 'pending', is_archived = FALSE, completed_at = NULL, updated_at = NOW()
       WHERE task_id = $1 AND user_id = $2
       RETURNING task_id`,
      [id, userId(req)]
    );
    if (!updated.rowCount) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");
    const task = await loadTask(id, userId(req));
    const subtasks = await loadSubtasks(id);
    return ok(res, { task: mapTask(task, subtasks.map(toCamel)) }, { message: "Task restored" });
  } catch (error) {
    console.error("Restore task error:", error);
    return fail(res, 500, "Could not restore task");
  }
};

export const createSubtask = async (req, res) => {
  try {
    const taskId = parseId(req.params.id);
    if (!taskId) return fail(res, 400, "Invalid task id");
    const task = await loadTask(taskId, userId(req));
    if (!task) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");

    const title = clampText(pick(req.body, "title"), { required: true, max: 200 });
    if (title.error) return fail(res, 400, title.error, "VALIDATION_ERROR");

    const positionValue = pick(req.body, "position");
    const maxPos = await pool.query(
      `SELECT COALESCE(MAX(position), -1) AS max FROM task_subtasks WHERE task_id = $1`,
      [taskId]
    );
    const position =
      Number.isInteger(Number(positionValue)) ? Number(positionValue) : maxPos.rows[0].max + 1;

    const created = await pool.query(
      `INSERT INTO task_subtasks (task_id, title, position)
       VALUES ($1, $2, $3)
       RETURNING task_subtask_id, task_id, title, is_completed, position, created_at, completed_at`,
      [taskId, title.value, position]
    );
    return ok(res, { subtask: toCamel(created.rows[0]) }, { status: 201, message: "Subtask added" });
  } catch (error) {
    console.error("Create subtask error:", error);
    return fail(res, 500, "Could not add subtask");
  }
};

export const updateSubtask = async (req, res) => {
  try {
    const taskId = parseId(req.params.id);
    const subtaskId = parseId(req.params.subtaskId);
    if (!taskId || !subtaskId) return fail(res, 400, "Invalid id");

    const task = await loadTask(taskId, userId(req));
    if (!task) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");

    const existing = await pool.query(
      `SELECT * FROM task_subtasks WHERE task_subtask_id = $1 AND task_id = $2`,
      [subtaskId, taskId]
    );
    if (!existing.rowCount) return fail(res, 404, "Subtask not found", "SUBTASK_NOT_FOUND");

    const current = existing.rows[0];
    const titleValue = pick(req.body, "title");
    const title = titleValue === undefined
      ? current.title
      : clampText(titleValue, { required: true, max: 200 });
    if (title.error) return fail(res, 400, title.error, "VALIDATION_ERROR");

    const isCompletedValue = pick(req.body, "isCompleted", "is_completed");
    const isCompleted =
      isCompletedValue === undefined ? current.is_completed : asBoolean(isCompletedValue, false);
    const positionValue = pick(req.body, "position");
    const position =
      positionValue === undefined ? current.position : Number.parseInt(positionValue, 10);
    if (!Number.isInteger(position) || position < 0) return fail(res, 400, "Invalid position");

    const updated = await pool.query(
      `UPDATE task_subtasks
       SET title = $1,
           is_completed = $2,
           position = $3,
           completed_at = CASE
             WHEN $2 = TRUE AND is_completed = FALSE THEN NOW()
             WHEN $2 = FALSE THEN NULL
             ELSE completed_at
           END
       WHERE task_subtask_id = $4 AND task_id = $5
       RETURNING task_subtask_id, task_id, title, is_completed, position, created_at, completed_at`,
      [typeof title === "string" ? title : title.value, isCompleted, position, subtaskId, taskId]
    );
    return ok(res, { subtask: toCamel(updated.rows[0]) }, { message: "Subtask updated" });
  } catch (error) {
    console.error("Update subtask error:", error);
    return fail(res, 500, "Could not update subtask");
  }
};

export const deleteSubtask = async (req, res) => {
  try {
    const taskId = parseId(req.params.id);
    const subtaskId = parseId(req.params.subtaskId);
    if (!taskId || !subtaskId) return fail(res, 400, "Invalid id");

    const task = await loadTask(taskId, userId(req));
    if (!task) return fail(res, 404, "Task not found", "TASK_NOT_FOUND");

    const deleted = await pool.query(
      `DELETE FROM task_subtasks
       WHERE task_subtask_id = $1 AND task_id = $2
       RETURNING task_subtask_id`,
      [subtaskId, taskId]
    );
    if (!deleted.rowCount) return fail(res, 404, "Subtask not found", "SUBTASK_NOT_FOUND");
    return ok(res, { deleted: true }, { message: "Subtask deleted" });
  } catch (error) {
    console.error("Delete subtask error:", error);
    return fail(res, 500, "Could not delete subtask");
  }
};
