"use client";

import Image from "next/image";

import { CopyButton } from "@/components/CopyButton";
import type { ScreenshotItem } from "@/lib/screenshots";

type Props = {
  item: ScreenshotItem;
  onDelete: (item: ScreenshotItem) => void;
};

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

/**
 * Server and browser time zones can differ, so the text is rendered with
 * `suppressHydrationWarning` instead of being deferred to an effect.
 */
function FormattedDate({ iso }: { iso: string }) {
  const date = new Date(iso);
  const text = Number.isNaN(date.getTime()) ? "Unknown date" : date.toLocaleString();
  return <span suppressHydrationWarning>{text}</span>;
}

export function ScreenshotCard({ item, onDelete }: Props) {
  return (
    <article className="shot">
      <a
        className="shot__thumb"
        href={item.url}
        target="_blank"
        rel="noopener noreferrer"
        title={`Open ${item.filename}`}
      >
        <Image src={item.url} alt={item.filename} fill sizes="(max-width: 720px) 45vw, 280px" />
        <span className="shot__badge">{formatBytes(item.size)}</span>
      </a>

      <div className="shot__body">
        <span className="shot__name" title={item.pathname}>
          {item.filename}
        </span>
        <span className="shot__meta">
          <FormattedDate iso={item.uploadedAt} />
        </span>
      </div>

      <div className="shot__actions">
        <CopyButton value={item.url} size="sm" />
        <a
          className="btn btn--ghost btn--sm"
          href={item.url}
          target="_blank"
          rel="noopener noreferrer"
        >
          Open
        </a>
        <button
          type="button"
          className="btn btn--danger btn--sm"
          onClick={() => onDelete(item)}
          aria-label={`Delete ${item.filename}`}
        >
          Delete
        </button>
      </div>
    </article>
  );
}
