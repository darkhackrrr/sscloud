"use client";

import { useState } from "react";

type Props = {
  value: string;
  className?: string;
  size?: "sm" | "md";
};

async function copyText(value: string): Promise<boolean> {
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      return true;
    }
  } catch {
    // fall through to the legacy path
  }

  try {
    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    document.body.removeChild(textarea);
    return copied;
  } catch {
    return false;
  }
}

export function CopyButton({ value, className, size = "md" }: Props) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");

  const handleClick = async () => {
    const copied = await copyText(value);
    setState(copied ? "copied" : "failed");
    window.setTimeout(() => setState("idle"), 1800);
  };

  const label =
    state === "copied" ? "Copied!" : state === "failed" ? "Copy failed" : "Copy link";

  return (
    <button
      type="button"
      onClick={handleClick}
      className={[
        "btn",
        "btn--ghost",
        size === "sm" ? "btn--sm" : "",
        state === "copied" ? "btn--icon" : "",
        className ?? "",
      ]
        .filter(Boolean)
        .join(" ")}
      aria-label={`Copy public link for ${value}`}
      title={value}
    >
      {state === "copied" ? "✓" : state === "failed" ? "!" : "⧉"} {label}
    </button>
  );
}
