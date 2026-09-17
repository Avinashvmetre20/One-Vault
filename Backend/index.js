import "./config/env.js";
import express from "express";
import cors from "cors";
import { pool, connectDB } from "./config/db.js";
import { initSchema } from "./db/init.js";
import { loadTimeZones } from "./utils/time.js";
import authRoutes from "./routes/auth.js";
import plannerRoutes from "./routes/planner.js";
import vaultRoutes from "./routes/vault.js";

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());
app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on("finish", () => {
    console.log(`${req.method} ${req.originalUrl} ${Date.now() - startedAt}ms`);
  });
  next();
});

app.get("/", (req, res) => {
  res.json({
    name: "OneVault API",
    status: "running",
    auth: {
      register: "POST /api/auth/register",
      login: "POST /api/auth/login",
      refresh: "POST /api/auth/refresh",
      logout: "POST /api/auth/logout",
      me: "GET /api/auth/me",
    },
    planner: {
      summary: "GET /api/v1/planner/summary",
      search: "GET /api/v1/planner/search",
      tasks: "/api/v1/planner/tasks",
      notes: "/api/v1/planner/notes",
      reminders: "/api/v1/planner/reminders",
      calendar: "/api/v1/planner/calendar",
    },
    vault: {
      passwords: "/api/v1/vault/passwords",
    },
  });
});

app.get("/health", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW() AS now");
    res.json({
      status: "ok",
      database: "connected",
      time: new Date(result.rows[0].now).toISOString(),
    });
  } catch (error) {
    res.status(500).json({
      status: "error",
      database: "disconnected",
      message: error.message,
    });
  }
});

app.use("/api/auth", authRoutes);
app.use("/api/v1/planner", plannerRoutes);
app.use("/api/v1/vault", vaultRoutes);

app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: "Route not found",
  });
});

app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  res.status(500).json({
    success: false,
    message: "Internal server error",
  });
});

try {
  await connectDB();
  await initSchema();
  await loadTimeZones();
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`OneVault API listening on http://localhost:${PORT}`);
  });
} catch (error) {
  console.error("Failed to start server:", error.message);
  process.exit(1);
}
