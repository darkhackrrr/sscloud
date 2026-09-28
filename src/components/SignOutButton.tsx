"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  const handleClick = async () => {
    setBusy(true);
    try {
      await fetch("/api/auth/logout", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      });
    } finally {
      router.replace("/login");
      router.refresh();
    }
  };

  return (
    <button type="button" className="btn btn--ghost btn--sm" onClick={handleClick} disabled={busy}>
      {busy ? (
        <>
          <span className="spinner spinner--light" aria-hidden="true" /> Signing out…
        </>
      ) : (
        "Sign out"
      )}
    </button>
  );
}
