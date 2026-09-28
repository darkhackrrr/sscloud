"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";

function LoginFormInner() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const body = (await response.json().catch(() => null)) as { message?: string } | null;

      if (!response.ok) {
        setError(body?.message ?? `Sign-in failed (HTTP ${response.status}).`);
        return;
      }

      setPassword("");
      const next = searchParams.get("next");
      router.replace(next && next.startsWith("/") ? next : "/dashboard");
      router.refresh();
    } catch {
      setError("Could not reach the server. Check your connection and try again.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} noValidate>
      {error && (
        <div className="alert alert--error" style={{ marginBottom: 16 }} role="alert">
          <span aria-hidden="true">⚠</span>
          <span>{error}</span>
        </div>
      )}

      <div className="field">
        <label className="field__label" htmlFor="admin-password">
          Administrator password
        </label>
        <input
          id="admin-password"
          className="input"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          placeholder="••••••••••••"
          required
          autoFocus
        />
      </div>

      <button
        type="submit"
        className="btn btn--primary btn--block"
        disabled={submitting || password.length === 0}
      >
        {submitting ? (
          <>
            <span className="spinner" aria-hidden="true" /> Signing in…
          </>
        ) : (
          "Sign in"
        )}
      </button>
    </form>
  );
}

export function LoginForm() {
  return (
    <Suspense fallback={null}>
      <LoginFormInner />
    </Suspense>
  );
}
