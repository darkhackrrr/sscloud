import { NextRequest } from "next/server";

import { jsonError, jsonOk } from "@/lib/api";
import {
  createSessionToken,
  getAdminPassword,
  isSecureRequest,
  registerLoginAttempt,
  resetLoginAttempts,
  timingSafeEqualStrings,
} from "@/lib/auth";
import { SESSION_COOKIE_NAME, SESSION_TTL_SECONDS } from "@/lib/constants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function clientKey(request: NextRequest): string {
  return request.headers.get("x-forwarded-for")?.split(",")[0].trim() || "unknown";
}

export async function POST(request: NextRequest) {
  const adminPassword = getAdminPassword();
  if (!adminPassword) {
    return jsonError(
      503,
      "admin_not_configured",
      "The ADMIN_PASSWORD environment variable is not set on this server.",
    );
  }

  const rate = registerLoginAttempt(clientKey(request));
  if (!rate.allowed) {
    return jsonError(
      429,
      "rate_limited",
      "Too many sign-in attempts. Try again later.",
      { "retry-after": String(rate.retryAfterSeconds) },
    );
  }

  let password: unknown;
  try {
    const body = (await request.json()) as { password?: unknown };
    password = body.password;
  } catch {
    return jsonError(400, "invalid_json", "The request body is not valid JSON.");
  }

  if (typeof password !== "string" || password.length === 0) {
    return jsonError(400, "missing_password", "Enter the administrator password.");
  }

  if (!timingSafeEqualStrings(password, adminPassword)) {
    return jsonError(401, "invalid_password", "That password is not correct.");
  }

  const session = createSessionToken();
  if (!session) {
    return jsonError(
      503,
      "session_not_configured",
      "No SESSION_SECRET or ADMIN_PASSWORD is available to sign sessions.",
    );
  }

  resetLoginAttempts(clientKey(request));

  const response = jsonOk({ ok: true });
  response.headers.append(
    "set-cookie",
    [
      `${SESSION_COOKIE_NAME}=${session.value}`,
      "Path=/",
      `Max-Age=${SESSION_TTL_SECONDS}`,
      "HttpOnly",
      "SameSite=Lax",
      isSecureRequest(request) ? "Secure" : "",
    ]
      .filter(Boolean)
      .join("; "),
  );

  return response;
}
