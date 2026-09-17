import jwt from "jsonwebtoken";
import { pool } from "../config/db.js";

const accessSecret = () => {
  const secret = process.env.JWT_ACCESS_SECRET;
  if (!secret) {
    throw new Error("Missing JWT_ACCESS_SECRET in .env");
  }
  return secret;
};

const refreshSecret = () => {
  const secret = process.env.JWT_REFRESH_SECRET;
  if (!secret) {
    throw new Error("Missing JWT_REFRESH_SECRET in .env");
  }
  return secret;
};

export const ACCESS_TOKEN_EXPIRES_IN =
  process.env.ACCESS_TOKEN_EXPIRES_IN || "15m";
export const REFRESH_TOKEN_EXPIRES_IN =
  process.env.REFRESH_TOKEN_EXPIRES_IN || "30d";

export const signAccessToken = (user) => {
  return jwt.sign(
    {
      sub: user.user_id,
      email: user.email,
      type: "access",
    },
    accessSecret(),
    { expiresIn: ACCESS_TOKEN_EXPIRES_IN }
  );
};

export const signRefreshToken = (user) => {
  return jwt.sign(
    {
      sub: user.user_id,
      email: user.email,
      type: "refresh",
    },
    refreshSecret(),
    { expiresIn: REFRESH_TOKEN_EXPIRES_IN }
  );
};

export const verifyAccessToken = (token) => {
  return jwt.verify(token, accessSecret());
};

export const verifyRefreshToken = (token) => {
  return jwt.verify(token, refreshSecret());
};

export const saveRefreshToken = async (userId, token) => {
  const decoded = jwt.decode(token);
  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token, expires_at)
     VALUES ($1, $2, to_timestamp($3))`,
    [userId, token, decoded.exp]
  );
};

export const issueTokenPair = async (user) => {
  const accessToken = signAccessToken(user);
  const refreshToken = signRefreshToken(user);
  await saveRefreshToken(user.user_id, refreshToken);

  return {
    accessToken,
    refreshToken,
    tokenType: "Bearer",
    accessTokenExpiresIn: ACCESS_TOKEN_EXPIRES_IN,
    refreshTokenExpiresIn: REFRESH_TOKEN_EXPIRES_IN,
  };
};

export const revokeRefreshToken = async (token) => {
  const result = await pool.query(
    `DELETE FROM refresh_tokens WHERE token = $1 RETURNING refresh_token_id`,
    [token]
  );
  return result.rowCount > 0;
};

export const findValidRefreshToken = async (token) => {
  const result = await pool.query(
    `SELECT * FROM refresh_tokens
     WHERE token = $1 AND expires_at > NOW()`,
    [token]
  );
  return result.rows[0] || null;
};
