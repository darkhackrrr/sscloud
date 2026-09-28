"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

import { ScreenshotCard } from "@/components/ScreenshotCard";
import type { ScreenshotItem } from "@/lib/screenshots";

type Props = {
  initialItems: ScreenshotItem[];
  initialCursor: string | null;
  initialHasMore: boolean;
  initialError: string | null;
};

type ApiFailure = { error: string; message: string };

async function readJson(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

function failureFrom(body: unknown, status: number): ApiFailure {
  if (body && typeof body === "object" && "message" in body) {
    const message = (body as { message?: unknown }).message;
    if (typeof message === "string" && message) return { error: `http_${status}`, message };
  }
  return { error: `http_${status}`, message: `Request failed with status ${status}.` };
}

export function Gallery({
  initialItems,
  initialCursor,
  initialHasMore,
  initialError,
}: Props) {
  const [items, setItems] = useState<ScreenshotItem[]>(initialItems);
  const [cursor, setCursor] = useState<string | null>(initialCursor);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [error, setError] = useState<string | null>(initialError);
  const [loading, setLoading] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<ScreenshotItem | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [unauthorized, setUnauthorized] = useState(false);

  const showToast = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast((current) => (current === message ? null : current)), 2400);
  }, []);

  const fetchPage = useCallback(async (nextCursor: string | null) => {
    const url = nextCursor
      ? `/api/screenshots?cursor=${encodeURIComponent(nextCursor)}`
      : "/api/screenshots";

    const response = await fetch(url, { cache: "no-store" });
    const body = await readJson(response);

    if (response.status === 401) {
      setUnauthorized(true);
      throw new Error("Your dashboard session has expired. Sign in again to continue.");
    }

    if (!response.ok) {
      throw new Error(failureFrom(body, response.status).message);
    }

    if (!body || typeof body !== "object") {
      throw new Error("The server returned an unexpected response.");
    }

    const payload = body as {
      items?: ScreenshotItem[];
      cursor?: string | null;
      hasMore?: boolean;
    };

    return {
      items: Array.isArray(payload.items) ? payload.items : [],
      cursor: typeof payload.cursor === "string" ? payload.cursor : null,
      hasMore: Boolean(payload.hasMore),
    };
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const page = await fetchPage(null);
      setItems(page.items);
      setCursor(page.cursor);
      setHasMore(page.hasMore);
      showToast("Gallery refreshed");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to refresh the gallery.");
    } finally {
      setLoading(false);
    }
  }, [fetchPage, showToast]);

  const loadMore = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const page = await fetchPage(cursor);
      setItems((current) => {
        const seen = new Set(current.map((item) => item.url));
        return [...current, ...page.items.filter((item) => !seen.has(item.url))];
      });
      setCursor(page.cursor);
      setHasMore(page.hasMore);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to load more screenshots.");
    } finally {
      setLoading(false);
    }
  }, [cursor, fetchPage]);

  const confirmDelete = useCallback(async () => {
    if (!pendingDelete) return;
    setDeleting(true);
    setError(null);

    try {
      const response = await fetch("/api/screenshots", {
        method: "DELETE",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ url: pendingDelete.url }),
      });
      const body = await readJson(response);

      if (response.status === 401) {
        setUnauthorized(true);
        throw new Error("Your dashboard session has expired. Sign in again to delete.");
      }

      if (!response.ok) {
        throw new Error(failureFrom(body, response.status).message);
      }

      setItems((current) => current.filter((item) => item.url !== pendingDelete.url));
      showToast("Screenshot deleted");
      setPendingDelete(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to delete the screenshot.");
      setPendingDelete(null);
    } finally {
      setDeleting(false);
    }
  }, [pendingDelete, showToast]);

  useEffect(() => {
    if (!pendingDelete) return undefined;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setPendingDelete(null);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [pendingDelete]);

  return (
    <>
      <div className="toolbar">
        <span className="toolbar__meta">
          {items.length === 0
            ? "No screenshots loaded"
            : `${items.length} screenshot${items.length === 1 ? "" : "s"} shown`}
        </span>
        <button type="button" className="btn btn--ghost" onClick={refresh} disabled={loading}>
          {loading ? <span className="spinner spinner--light" aria-hidden="true" /> : "↻"} Refresh
        </button>
      </div>

      {unauthorized && (
        <div className="alert alert--error" style={{ marginTop: 18 }} role="alert">
          <span aria-hidden="true">🔒</span>
          <span>
            Your session has expired.{" "}
            <Link href="/login" style={{ textDecoration: "underline" }}>
              Sign in again
            </Link>{" "}
            to manage screenshots.
          </span>
        </div>
      )}

      {error && !unauthorized && (
        <div className="alert alert--error" style={{ marginTop: 18 }} role="alert">
          <span aria-hidden="true">⚠</span>
          <span>{error}</span>
        </div>
      )}

      <div style={{ marginTop: 24 }}>
        {loading && items.length === 0 ? (
          <div className="gallery">
            {Array.from({ length: 8 }).map((_, index) => (
              <div className="skeleton" key={index}>
                <div className="skeleton skeleton--thumb" />
                <div style={{ padding: "0 15px 15px" }}>
                  <div className="skeleton skeleton--line" />
                  <div className="skeleton skeleton--line" style={{ width: "55%" }} />
                </div>
              </div>
            ))}
          </div>
        ) : items.length === 0 ? (
          <div className="state">
            <span className="state__icon" aria-hidden="true">
              🖼️
            </span>
            <h2 className="state__title">No screenshots yet</h2>
            <p className="state__text">
              Run <span className="mono">ScreenshotCloud</span> on your PC, or{" "}
              <span className="mono">.\Screenshot.ps1</span>, and the upload will appear here
              within seconds.
            </p>
            <Link className="btn btn--primary" href="/#setup">
              See setup steps
            </Link>
          </div>
        ) : (
          <div className="gallery">
            {items.map((item) => (
              <ScreenshotCard key={item.url} item={item} onDelete={setPendingDelete} />
            ))}
          </div>
        )}
      </div>

      {hasMore && items.length > 0 && (
        <div className="load-more">
          <button type="button" className="btn btn--ghost" onClick={loadMore} disabled={loading}>
            {loading ? (
              <>
                <span className="spinner spinner--light" aria-hidden="true" /> Loading…
              </>
            ) : (
              "Load more"
            )}
          </button>
        </div>
      )}

      {pendingDelete && (
        <div
          className="modal-backdrop"
          role="presentation"
          onClick={(event) => {
            if (event.target === event.currentTarget) setPendingDelete(null);
          }}
        >
          <div
            className="modal"
            role="alertdialog"
            aria-modal="true"
            aria-labelledby="delete-title"
          >
            <h2 className="modal__title" id="delete-title">
              Delete this screenshot?
            </h2>
            <p className="modal__text">
              <span className="mono">{pendingDelete.filename}</span> will be permanently removed
              from Vercel Blob. The public link will stop working.
            </p>
            <div className="modal__actions">
              <button
                type="button"
                className="btn btn--ghost"
                onClick={() => setPendingDelete(null)}
                disabled={deleting}
              >
                Cancel
              </button>
              <button
                type="button"
                className="btn btn--danger"
                onClick={confirmDelete}
                disabled={deleting}
                autoFocus
              >
                {deleting ? (
                  <>
                    <span className="spinner" aria-hidden="true" /> Deleting…
                  </>
                ) : (
                  "Delete permanently"
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {toast && (
        <div className="toast" role="status" aria-live="polite">
          <span aria-hidden="true">✓</span>
          {toast}
        </div>
      )}
    </>
  );
}
