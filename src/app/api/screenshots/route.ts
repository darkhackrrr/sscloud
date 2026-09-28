import type { NextRequest } from "next/server";

import { jsonError, jsonOk } from "@/lib/api";
import { hasValidSession } from "@/lib/auth";
import { GALLERY_PAGE_SIZE } from "@/lib/constants";
import { deleteScreenshot, isDeletableScreenshotUrl, listScreenshots } from "@/lib/screenshots";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function unauthorized(): Response {
  return jsonError(
    401,
    "unauthorized",
    "Sign in to the dashboard to manage screenshots.",
    { "www-authenticate": "Cookie" },
  );
}

export async function GET(request: NextRequest) {
  if (!hasValidSession(request)) return unauthorized();

  const cursor = request.nextUrl.searchParams.get("cursor");
  const limitParam = request.nextUrl.searchParams.get("limit");

  let limit = GALLERY_PAGE_SIZE;
  if (limitParam) {
    const parsed = Number(limitParam);
    if (!Number.isFinite(parsed) || parsed < 1 || parsed > GALLERY_PAGE_SIZE) {
      return jsonError(400, "invalid_limit", `limit must be between 1 and ${GALLERY_PAGE_SIZE}.`);
    }
    limit = Math.floor(parsed);
  }

  try {
    const page = await listScreenshots(cursor, limit);
    return jsonOk({
      items: page.items,
      cursor: page.cursor,
      hasMore: page.hasMore,
      pageSize: limit,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to list screenshots.";
    return jsonError(502, "blob_list_failed", `Vercel Blob listing failed: ${message}`);
  }
}

export async function DELETE(request: NextRequest) {
  if (!hasValidSession(request)) return unauthorized();

  let target: string | null = request.nextUrl.searchParams.get("url");

  if (!target) {
    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      return jsonError(400, "missing_url", "Provide the screenshot URL to delete.");
    }
    try {
      const body = (await request.json()) as { url?: unknown };
      if (typeof body.url === "string") target = body.url;
    } catch {
      return jsonError(400, "invalid_json", "The request body is not valid JSON.");
    }
  }

  if (!target) {
    return jsonError(400, "missing_url", "Provide the screenshot URL to delete.");
  }

  if (!isDeletableScreenshotUrl(target)) {
    return jsonError(
      400,
      "invalid_url",
      "Only screenshots stored under the screenshots/ prefix of this Blob store can be deleted.",
    );
  }

  try {
    await deleteScreenshot(target);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to delete the screenshot.";
    return jsonError(502, "blob_delete_failed", `Vercel Blob delete failed: ${message}`);
  }

  return jsonOk({ ok: true, deleted: target });
}
