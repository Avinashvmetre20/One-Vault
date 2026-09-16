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
});

pool.on("error", (err) => {
  console.error("Unexpected PostgreSQL error:", err);
});

const connectDB = async () => {
  const client = await pool.connect();
  try {
    await client.query("SELECT 1");
    console.log("PostgreSQL connected");
  } finally {
    client.release();
  }
};

export { pool, connectDB };
