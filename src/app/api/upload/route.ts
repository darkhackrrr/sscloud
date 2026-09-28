import type { NextRequest } from "next/server";

import { jsonError, jsonOk } from "@/lib/api";
import { verifyUploadKey } from "@/lib/auth";
import { MAX_UPLOAD_BYTES } from "@/lib/constants";
import { storeScreenshot } from "@/lib/screenshots";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MULTI_PART_PATTERN = /^multipart\/form-data/i;

async function readPayload(request: NextRequest): Promise<
  { ok: true; bytes: Uint8Array } | { ok: false; response: Response }
> {
  const contentType = request.headers.get("content-type") ?? "";

  if (MULTI_PART_PATTERN.test(contentType)) {
    let form: FormData;
    try {
      form = await request.formData();
    } catch {
      return {
        ok: false,
        response: jsonError(400, "invalid_form", "The multipart form body could not be parsed."),
      };
    }

    const file = form.get("file");
    if (!file || typeof file === "string") {
      return {
        ok: false,
        response: jsonError(
          400,
          "missing_file",
          'No image was found. Send the screenshot in a "file" form field.',
        ),
      };
    }

    const buffer = new Uint8Array(await file.arrayBuffer());
    return { ok: true, bytes: buffer };
  }

  const buffer = new Uint8Array(await request.arrayBuffer());
  return { ok: true, bytes: buffer };
}

export async function POST(request: NextRequest) {
  const auth = verifyUploadKey(request.headers.get("authorization"));

  if (auth === "unconfigured") {
    return jsonError(
      503,
      "upload_not_configured",
      "The server is missing the SCREENSHOT_UPLOAD_KEY environment variable.",
    );
  }

  if (auth !== "ok") {
    return jsonError(
      401,
      auth === "missing" ? "missing_token" : "invalid_token",
      "Provide the upload key as an Authorization: Bearer <key> header.",
      { "www-authenticate": "Bearer" },
    );
  }

  const declaredLength = request.headers.get("content-length");
  if (declaredLength) {
    const parsed = Number(declaredLength);
    if (Number.isFinite(parsed) && parsed > MAX_UPLOAD_BYTES) {
      return jsonError(
        413,
        "file_too_large",
        `Screenshot exceeds the ${MAX_UPLOAD_BYTES / (1024 * 1024)} MB limit.`,
      );
    }
  }

  let payload: Awaited<ReturnType<typeof readPayload>>;
  try {
    payload = await readPayload(request);
  } catch {
    return jsonError(400, "invalid_body", "The request body could not be read.");
  }

  if (!payload.ok) return payload.response;

  const result = await storeScreenshot({ bytes: payload.bytes });

  if (!result.ok) {
    return jsonError(result.status, result.error, result.message);
  }

  return jsonOk({ url: result.data.url }, 201);
}

export function GET(): Response {
  return jsonError(405, "method_not_allowed", "Use POST to upload a screenshot.");
}
