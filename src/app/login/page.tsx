import type { Metadata } from "next";
import Link from "next/link";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { LoginForm } from "@/components/LoginForm";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { verifySessionToken } from "@/lib/auth";
import { SESSION_COOKIE_NAME } from "@/lib/constants";

export const metadata: Metadata = {
  title: "Sign in",
};

export const dynamic = "force-dynamic";

export default async function LoginPage() {
  const cookieStore = await cookies();
  if (verifySessionToken(cookieStore.get(SESSION_COOKIE_NAME)?.value)) {
    redirect("/dashboard");
  }

  return (
    <>
      <SiteHeader />

      <main className="auth-wrap">
        <div className="auth-card">
          <h1 className="auth-card__title">Admin sign in</h1>
          <p className="auth-card__lead">
            The gallery stores, lists and deletes screenshots, so it is protected by its own
            password - separate from the PowerShell upload key.
          </p>

          <LoginForm />

          <p className="auth-card__lead" style={{ marginTop: 20 }}>
            Need the upload key instead? It is configured on the{" "}
            <Link href="/#setup" style={{ textDecoration: "underline" }}>
              setup page
            </Link>
            .
          </p>
        </div>
      </main>

      <SiteFooter />
    </>
  );
}
