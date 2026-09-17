import { Router } from "express";
import { requireAuth } from "../middleware/auth.js";
import {
  archiveTask,
  completeTask,
  createSubtask,
  createTask,
  createTaskCategory,
  deleteSubtask,
  deleteTask,
  deleteTaskCategory,
  getTask,
  listTaskCategories,
  listTasks,
  restoreTask,
  updateSubtask,
  updateTask,
  updateTaskCategory,
} from "../controllers/taskController.js";
import {
  archiveNote,
  createNote,
  createNoteCategory,
  deleteNote,
  deleteNoteCategory,
  favoriteNote,
  getNote,
  listNoteCategories,
  listNotes,
  pinNote,
  restoreNote,
  updateNote,
  updateNoteCategory,
} from "../controllers/noteController.js";
import {
  cancelReminder,
  completeReminder,
  createReminder,
  deleteReminder,
  getReminder,
  listReminders,
  snoozeReminder,
  updateReminder,
} from "../controllers/reminderController.js";
import {
  createCalendarEvent,
  deleteCalendarEvent,
  getCalendarEvent,
  listCalendarEvents,
  updateCalendarEvent,
} from "../controllers/calendarController.js";
import {
  plannerAgenda,
  plannerSearch,
  plannerSummary,
} from "../controllers/plannerController.js";

const router = Router();

router.use(requireAuth);

router.get("/summary", plannerSummary);
router.get("/search", plannerSearch);
router.get("/agenda", plannerAgenda);

router.get("/task-categories", listTaskCategories);
router.post("/task-categories", createTaskCategory);
router.patch("/task-categories/:id", updateTaskCategory);
router.delete("/task-categories/:id", deleteTaskCategory);

router.get("/note-categories", listNoteCategories);
router.post("/note-categories", createNoteCategory);
router.patch("/note-categories/:id", updateNoteCategory);
router.delete("/note-categories/:id", deleteNoteCategory);

router.get("/tasks", listTasks);
router.post("/tasks", createTask);
router.get("/tasks/:id", getTask);
router.patch("/tasks/:id", updateTask);
router.delete("/tasks/:id", deleteTask);
router.post("/tasks/:id/complete", completeTask);
router.post("/tasks/:id/archive", archiveTask);
router.post("/tasks/:id/restore", restoreTask);
router.post("/tasks/:id/subtasks", createSubtask);
router.patch("/tasks/:id/subtasks/:subtaskId", updateSubtask);
router.delete("/tasks/:id/subtasks/:subtaskId", deleteSubtask);

router.get("/notes", listNotes);
router.post("/notes", createNote);
router.get("/notes/:id", getNote);
router.patch("/notes/:id", updateNote);
router.delete("/notes/:id", deleteNote);
router.post("/notes/:id/pin", pinNote);
router.post("/notes/:id/favorite", favoriteNote);
router.post("/notes/:id/archive", archiveNote);
router.post("/notes/:id/restore", restoreNote);

router.get("/reminders", listReminders);
router.post("/reminders", createReminder);
router.get("/reminders/:id", getReminder);
router.patch("/reminders/:id", updateReminder);
router.delete("/reminders/:id", deleteReminder);
router.post("/reminders/:id/complete", completeReminder);
router.post("/reminders/:id/snooze", snoozeReminder);
router.post("/reminders/:id/cancel", cancelReminder);

router.get("/calendar", listCalendarEvents);
router.post("/calendar", createCalendarEvent);
router.get("/calendar/:id", getCalendarEvent);
router.patch("/calendar/:id", updateCalendarEvent);
router.delete("/calendar/:id", deleteCalendarEvent);

export default router;
