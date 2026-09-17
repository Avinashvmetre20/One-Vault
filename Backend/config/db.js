import "./env.js";
import { Pool } from "pg";

const rawConnectionString = process.env.databaseurl || process.env.DATABASE_URL;

if (!rawConnectionString) {
  throw new Error("Missing database URL. Set databaseurl in the .env file.");
}

const dbUrl = new URL(rawConnectionString);
const sslMode = dbUrl.searchParams.get("sslmode");

if (sslMode === "prefer" || sslMode === "require" || sslMode === "verify-ca") {
  dbUrl.searchParams.set("sslmode", "verify-full");
}

const pool = new Pool({
  connectionString: dbUrl.toString(),
  options: "-c timezone=UTC",
});

pool.on("error", (err) => {
  console.error("Unexpected PostgreSQL error:", err);
});

const connectDB = async () => {
  const client = await pool.connect();
  try {
    const result = await client.query("SELECT current_database() AS database");
    console.log(`Database connected: ${result.rows[0].database}`);
  } finally {
    client.release();
  }
};

export { pool, connectDB };
