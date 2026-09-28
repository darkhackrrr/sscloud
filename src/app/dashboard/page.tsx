import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { Gallery } from "@/components/Gallery";
import { SignOutButton } from "@/components/SignOutButton";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { verifySessionToken } from "@/lib/auth";
import { SESSION_COOKIE_NAME } from "@/lib/constants";
import { listScreenshots, type ScreenshotItem } from "@/lib/screenshots";

export const metadata: Metadata = {
  title: "Dashboard",
};

export const dynamic = "force-dynamic";

type InitialState = {
  items: ScreenshotItem[];
  cursor: string | null;
  hasMore: boolean;
  error: string | null;
};

async function loadInitialPage(): Promise<InitialState> {
  try {
    const page = await listScreenshots();
    return {
      items: page.items,
      cursor: page.cursor,
      hasMore: page.hasMore,
      error: null,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown storage error.";
    return {
      items: [],
      cursor: null,
      hasMore: false,
      error: `Could not reach Vercel Blob: ${message}. Check that the Blob store is connected and BLOB_READ_WRITE_TOKEN / OIDC credentials are configured.`,
    };
  }
}

export default async function DashboardPage() {
  const cookieStore = await cookies();
  const session = cookieStore.get(SESSION_COOKIE_NAME)?.value;

  if (!verifySessionToken(session)) {
    redirect("/login?next=/dashboard");
  }

  const initial = await loadInitialPage();

  return (
    <>
      <SiteHeader />

      <main style={{ flex: 1 }}>
        <div className="container">
          <div className="page-head">
            <h1 className="page-head__title">Screenshot gallery</h1>
            <p className="page-head__lead">
              Everything below is listed live from the <span className="mono">screenshots/</span>{" "}
              prefix of your Vercel Blob store. The write token never leaves the server.
            </p>
          </div>

          <Gallery
            initialItems={initial.items}
            initialCursor={initial.cursor}
            initialHasMore={initial.hasMore}
            initialError={initial.error}
          />

          <div className="load-more" style={{ paddingBottom: 48 }}>
            <SignOutButton />
          </div>
        </div>
      </main>

      <SiteFooter />
    </>
  );
}
