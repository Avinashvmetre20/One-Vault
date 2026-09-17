import bcrypt from "bcryptjs";
import { pool } from "../config/db.js";
import {
  findValidRefreshToken,
  issueTokenPair,
  revokeRefreshToken,
  verifyRefreshToken,
} from "../utils/tokens.js";
import { publicUser } from "../utils/user.js";
import { ensureDefaultPlannerData } from "../db/planner.js";

const USER_COLUMNS =
  'user_id, name, email, phone, password, created_at, updated_at';
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SALT_ROUNDS = 10;

const normalizeEmail = (email = "") => email.trim().toLowerCase();

const validateRegister = ({ name, email, phone, password }) => {
  const errors = [];

  if (!name || String(name).trim().length < 2) {
    errors.push("Name must be at least 2 characters");
  }

  if (!email || !EMAIL_REGEX.test(String(email).trim())) {
    errors.push("A valid email is required");
  }

  if (!password || String(password).length < 6) {
    errors.push("Password must be at least 6 characters");
  }

  if (phone && String(phone).replace(/\D/g, "").length < 10) {
    errors.push("Phone must have at least 10 digits");
  }

  return errors;
};

export const register = async (req, res) => {
  try {
    const name = String(req.body.name || "").trim();
    const email = normalizeEmail(req.body.email);
    const phone = req.body.phone ? String(req.body.phone).trim() : null;
    const password = String(req.body.password || "");

    const errors = validateRegister({ name, email, phone, password });
    if (errors.length) {
      return res.status(400).json({
        success: false,
        message: errors[0],
        errors,
      });
    }

    const existing = await pool.query(
      "SELECT user_id FROM users WHERE LOWER(email) = $1",
      [email]
    );

    if (existing.rowCount > 0) {
      return res.status(409).json({
        success: false,
        message: "Email already registered",
      });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const created = await pool.query(
      `INSERT INTO users (name, email, phone, password)
       VALUES ($1, $2, $3, $4)
       RETURNING user_id, name, email, phone, created_at, updated_at`,
      [name, email, phone, passwordHash]
    );

    const user = created.rows[0];
    await ensureDefaultPlannerData(user.user_id);
    const tokens = await issueTokenPair(user);

    return res.status(201).json({
      success: true,
      message: "Account created successfully",
      data: {
        user: publicUser(user),
        tokens,
      },
    });
  } catch (error) {
    if (error.code === "23505") {
      return res.status(409).json({
        success: false,
        message: "Email already registered",
      });
    }

    console.error("Register error:", error);
    return res.status(500).json({
      success: false,
      message: "Could not create account",
    });
  }
};

export const login = async (req, res) => {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password || "");

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: "Email and password are required",
      });
    }

    const result = await pool.query(
      `SELECT ${USER_COLUMNS} FROM users WHERE LOWER(email) = $1`,
      [email]
    );
    const user = result.rows[0];

    if (!user) {
      return res.status(401).json({
        success: false,
        message: "Invalid email or password",
      });
    }

    const ok = await bcrypt.compare(password, user.password);
    if (!ok) {
      return res.status(401).json({
        success: false,
        message: "Invalid email or password",
      });
    }

    const tokens = await issueTokenPair(user);

    return res.json({
      success: true,
      message: "Login successful",
      data: {
        user: publicUser(user),
        tokens,
      },
    });
  } catch (error) {
    console.error("Login error:", error);
    return res.status(500).json({
      success: false,
      message: "Could not log in",
    });
  }
};

export const refresh = async (req, res) => {
  try {
    const refreshToken = req.body.refreshToken;

    if (!refreshToken) {
      return res.status(400).json({
        success: false,
        message: "Refresh token is required",
      });
    }

    let decoded;
    try {
      decoded = verifyRefreshToken(refreshToken);
    } catch {
      return res.status(401).json({
        success: false,
        message: "Invalid or expired refresh token",
      });
    }

    if (decoded.type !== "refresh") {
      return res.status(401).json({
        success: false,
        message: "Invalid refresh token",
      });
    }

    const stored = await findValidRefreshToken(refreshToken);
    if (!stored) {
      return res.status(401).json({
        success: false,
        message: "Refresh token has been revoked",
      });
    }

    const userResult = await pool.query(
      `SELECT ${USER_COLUMNS} FROM users WHERE user_id = $1`,
      [decoded.sub]
    );
    const user = userResult.rows[0];

    if (!user) {
      return res.status(401).json({
        success: false,
        message: "User not found",
      });
    }

    await revokeRefreshToken(refreshToken);
    const tokens = await issueTokenPair(user);

    return res.json({
      success: true,
      message: "Token refreshed",
      data: { tokens },
    });
  } catch (error) {
    console.error("Refresh error:", error);
    return res.status(500).json({
      success: false,
      message: "Could not refresh token",
    });
  }
};

export const logout = async (req, res) => {
  try {
    const refreshToken = req.body.refreshToken;

    if (!refreshToken) {
      return res.status(400).json({
        success: false,
        message: "Refresh token is required",
      });
    }

    await revokeRefreshToken(refreshToken);

    return res.json({
      success: true,
      message: "Logged out successfully",
    });
  } catch (error) {
    console.error("Logout error:", error);
    return res.status(500).json({
      success: false,
      message: "Could not log out",
    });
  }
};

export const me = async (req, res) => {
  return res.json({
    success: true,
    data: {
      user: publicUser(req.user),
    },
  });
};
