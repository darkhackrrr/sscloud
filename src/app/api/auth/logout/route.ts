import { NextRequest } from "next/server";

import { jsonOk } from "@/lib/api";
import { isSecureRequest } from "@/lib/auth";
import { SESSION_COOKIE_NAME } from "@/lib/constants";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const response = jsonOk({ ok: true });
  response.headers.append(
    "set-cookie",
    [
      `${SESSION_COOKIE_NAME}=`,
      "Path=/",
      "Max-Age=0",
      "HttpOnly",
      "SameSite=Lax",
      isSecureRequest(request) ? "Secure" : "",
    ]
      .filter(Boolean)
      .join("; "),
  );

  return response;
}
