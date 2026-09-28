import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import type { NextRequest } from "next/server";

import {
  LOGIN_RATE_LIMIT_MAX_ATTEMPTS,
  LOGIN_RATE_LIMIT_WINDOW_MS,
  SESSION_COOKIE_NAME,
  SESSION_TTL_SECONDS,
} from "@/lib/constants";

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

/**
 * The session signing secret. SESSION_SECRET is preferred; when it is missing we
 * derive a stable secret from ADMIN_PASSWORD so a single environment variable is
 * enough to get started. Setting SESSION_SECRET explicitly is recommended.
 */
export function getSessionSecret(): string | null {
  const explicit = process.env.SESSION_SECRET?.trim();
  if (explicit) return explicit;

  const adminPassword = process.env.ADMIN_PASSWORD;
  if (adminPassword && adminPassword.length > 0) {
    return `screenshotcloud-session::${sha256(adminPassword)}`;
  }

  return null;
}

export function getAdminPassword(): string | null {
  const password = process.env.ADMIN_PASSWORD;
  if (!password || password.length === 0) return null;
  return password;
}

export function getUploadKey(): string | null {
  const key = process.env.SCREENSHOT_UPLOAD_KEY;
  if (!key || key.length === 0) return null;
  return key;
}

/** Length-safe constant time comparison. */
export function timingSafeEqualStrings(a: string, b: string): boolean {
  const digestA = createHash("sha256").update(a, "utf8").digest();
  const digestB = createHash("sha256").update(b, "utf8").digest();
  return timingSafeEqual(digestA, digestB);
}

export function verifyUploadKey(authorizationHeader: string | null): "ok" | "missing" | "invalid" | "unconfigured" {
  const expected = getUploadKey();
  if (!expected) return "unconfigured";
  if (!authorizationHeader) return "missing";

  const match = /^Bearer\s+(.+)$/i.exec(authorizationHeader.trim());
  if (!match) return "invalid";

  return timingSafeEqualStrings(match[1].trim(), expected) ? "ok" : "invalid";
}

function sign(expiration: number, secret: string): string {
  return createHmac("sha256", secret)
    .update(`screenshotcloud:session:${expiration}`, "utf8")
    .digest("base64url");
}

/** Creates the signed session token: `<epochSeconds>.<hmac>`. */
export function createSessionToken(): { value: string; expiresAt: Date } | null {
  const secret = getSessionSecret();
  if (!secret) return null;

  const expiresAt = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
  return {
    value: `${expiresAt}.${sign(expiresAt, secret)}`,
    expiresAt: new Date(expiresAt * 1000),
  };
}

export function verifySessionToken(token: string | undefined | null): boolean {
  if (!token) return false;
  const secret = getSessionSecret();
  if (!secret) return false;

  const separator = token.indexOf(".");
  if (separator <= 0) return false;

  const expirationRaw = token.slice(0, separator);
  const providedSignature = token.slice(separator + 1);
  if (!/^\d+$/.test(expirationRaw) || providedSignature.length === 0) return false;

  const expiration = Number(expirationRaw);
  if (!Number.isFinite(expiration)) return false;
  if (expiration * 1000 <= Date.now()) return false;

  const expectedSignature = sign(expiration, secret);
  if (expectedSignature.length !== providedSignature.length) return false;

  return timingSafeEqualStrings(providedSignature, expectedSignature);
}

export function hasValidSession(request: NextRequest): boolean {
  return verifySessionToken(request.cookies.get(SESSION_COOKIE_NAME)?.value);
}

export function isSecureRequest(request: NextRequest): boolean {
  const forwardedProto = request.headers.get("x-forwarded-proto");
  if (forwardedProto) return forwardedProto.split(",")[0].trim() === "https";
  return request.nextUrl.protocol === "https:";
}

type AttemptRecord = { count: number; resetAt: number };

const loginAttempts = new Map<string, AttemptRecord>();

/**
 * Best effort in-memory limiter. Serverless instances do not share memory, so this
 * is a speed bump rather than a hard guarantee - the real defence is the password.
 */
export function registerLoginAttempt(key: string): { allowed: boolean; retryAfterSeconds: number } {
  const now = Date.now();
  const existing = loginAttempts.get(key);

  if (!existing || existing.resetAt <= now) {
    loginAttempts.set(key, { count: 1, resetAt: now + LOGIN_RATE_LIMIT_WINDOW_MS });
    return { allowed: true, retryAfterSeconds: 0 };
  }

  existing.count += 1;
  if (loginAttempts.size > 500) {
    for (const [mapKey, record] of loginAttempts) {
      if (record.resetAt <= now) loginAttempts.delete(mapKey);
    }
  }

  if (existing.count > LOGIN_RATE_LIMIT_MAX_ATTEMPTS) {
    return {
      allowed: false,
      retryAfterSeconds: Math.max(1, Math.ceil((existing.resetAt - now) / 1000)),
    };
  }

  return { allowed: true, retryAfterSeconds: 0 };
}

export function resetLoginAttempts(key: string): void {
  loginAttempts.delete(key);
}
