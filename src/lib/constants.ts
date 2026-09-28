export const SCREENSHOTS_PREFIX = "screenshots/";

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

export const MAX_UPLOAD_MB = MAX_UPLOAD_BYTES / (1024 * 1024);

export const ALLOWED_IMAGE_TYPES = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
} as const;

export type AllowedImageType = keyof typeof ALLOWED_IMAGE_TYPES;

export const GALLERY_PAGE_SIZE = 24;

export const SESSION_COOKIE_NAME = "screenshotcloud_session";

export const SESSION_TTL_SECONDS = 60 * 60 * 24 * 7;

export const LOGIN_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;

export const LOGIN_RATE_LIMIT_MAX_ATTEMPTS = 10;
