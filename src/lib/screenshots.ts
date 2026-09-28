import { randomUUID } from "node:crypto";

import { list, put, del, type ListBlobResultBlob } from "@vercel/blob";

import {
  ALLOWED_IMAGE_TYPES,
  GALLERY_PAGE_SIZE,
  MAX_UPLOAD_BYTES,
  SCREENSHOTS_PREFIX,
  type AllowedImageType,
} from "@/lib/constants";
import { sniffImageType } from "@/lib/images";

export type ScreenshotItem = {
  url: string;
  pathname: string;
  filename: string;
  size: number;
  uploadedAt: string;
};

export type ScreenshotPage = {
  items: ScreenshotItem[];
  cursor: string | null;
  hasMore: boolean;
};

export type UploadSuccess = {
  url: string;
  pathname: string;
  size: number;
  uploadedAt: string;
  contentType: AllowedImageType;
};

export type UploadFailure =
  | { ok: false; status: number; error: string; message: string }
  | { ok: true; data: UploadSuccess };

function filenameFrom(pathname: string): string {
  const parts = pathname.split("/");
  return parts[parts.length - 1] || pathname;
}

function toItem(blob: ListBlobResultBlob): ScreenshotItem {
  return {
    url: blob.url,
    pathname: blob.pathname,
    filename: filenameFrom(blob.pathname),
    size: blob.size,
    uploadedAt:
      blob.uploadedAt instanceof Date
        ? blob.uploadedAt.toISOString()
        : new Date(blob.uploadedAt as unknown as string).toISOString(),
  };
}

export async function listScreenshots(
  cursor?: string | null,
  limit = GALLERY_PAGE_SIZE,
): Promise<ScreenshotPage> {
  const result = await list({
    prefix: SCREENSHOTS_PREFIX,
    limit,
    ...(cursor ? { cursor } : {}),
  });

  const items = result.blobs
    .map(toItem)
    .sort((a, b) => (a.uploadedAt < b.uploadedAt ? 1 : a.uploadedAt > b.uploadedAt ? -1 : 0));

  return {
    items,
    cursor: result.hasMore && result.cursor ? result.cursor : null,
    hasMore: result.hasMore,
  };
}

/** Only screenshots living in our own `screenshots/` folder on a Blob host may be deleted. */
export function isDeletableScreenshotUrl(raw: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return false;
  }

  if (parsed.protocol !== "https:") return false;
  if (!/(^|\.)blob\.vercel-storage\.com$/.test(parsed.hostname)) return false;
  if (!parsed.pathname.startsWith(`/${SCREENSHOTS_PREFIX}`)) return false;
  return true;
}

export async function deleteScreenshot(url: string): Promise<void> {
  await del(url);
}

export type UploadInput = {
  bytes: Uint8Array;
};

/**
 * Validates the payload and stores it in Vercel Blob under `screenshots/<uuid>.<ext>`.
 * The filename is always generated server-side; user supplied names are never trusted.
 */
export async function storeScreenshot(input: UploadInput): Promise<UploadFailure> {
  const { bytes } = input;

  if (bytes.length === 0) {
    return { ok: false, status: 400, error: "empty_file", message: "The uploaded file is empty." };
  }

  if (bytes.length > MAX_UPLOAD_BYTES) {
    return {
      ok: false,
      status: 413,
      error: "file_too_large",
      message: `Screenshot exceeds the ${MAX_UPLOAD_BYTES / (1024 * 1024)} MB limit.`,
    };
  }

  const sniffed = sniffImageType(bytes);
  if (!sniffed) {
    return {
      ok: false,
      status: 415,
      error: "unsupported_media_type",
      message: "Only PNG, JPEG and WebP images are accepted.",
    };
  }

  const extension = ALLOWED_IMAGE_TYPES[sniffed];
  const pathname = `${SCREENSHOTS_PREFIX}${randomUUID()}.${extension}`;

  try {
    const blob = await put(pathname, Buffer.from(bytes), {
      access: "public",
      contentType: sniffed,
      addRandomSuffix: false,
      allowOverwrite: false,
      cacheControlMaxAge: 60 * 60 * 24 * 30,
    });

    return {
      ok: true,
      data: {
        url: blob.url,
        pathname: blob.pathname,
        size: bytes.length,
        uploadedAt: new Date().toISOString(),
        contentType: sniffed,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown storage error.";
    return {
      ok: false,
      status: 502,
      error: "blob_upload_failed",
      message: `Vercel Blob rejected the upload: ${message}`,
    };
  }
}
