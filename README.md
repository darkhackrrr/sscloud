# ScreenshotCloud

Take a screenshot of your Windows PC from PowerShell, upload it to your own Vercel-hosted
site, and get a public link printed straight back into your terminal — without opening a
browser.

The website is a Next.js (App Router, TypeScript) app that stores screenshots in **Vercel
Blob** under a `screenshots/` prefix and gives you a dark, responsive gallery to browse,
copy, open and delete them.

```
Screenshot.ps1  ──POST /api/upload──▶  Next.js on Vercel  ──▶  Vercel Blob
                                          ▲                        │
                                          │                        ▼
                                     /dashboard  ◀── public blob URL ──┘
```

---

## Table of contents

1. [Project overview](#1-project-overview)
2. [Local development setup](#2-local-development-setup)
3. [Vercel account, project and Blob store](#3-vercel-account-project-and-blob-store)
4. [Environment variables](#4-environment-variables)
5. [Deploying](#5-deploying)
6. [PowerShell uploader configuration](#6-powershell-uploader-configuration)
7. [Installing the `ScreenshotCloud` command](#7-installing-the-screenshotcloud-command)
8. [Using the gallery](#8-using-the-gallery)
9. [Security model](#9-security-model)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Project overview

### Features

| Area | What you get |
| --- | --- |
| Homepage | Explains the capture → upload → link flow with copy-paste command examples |
| Upload API | `POST /api/upload`, bearer-token protected, server-side type and size validation |
| Storage | `@vercel/blob` `put()` into `screenshots/<uuid>.<ext>` (public access) |
| Gallery | Lists real Blob objects: thumbnail, filename, upload date, size |
| Gallery actions | Copy link, open full size, delete with confirmation |
| Admin auth | Password login → signed HTTP-only session cookie (separate from the upload key) |
| PowerShell | `Screenshot.ps1` for Windows PowerShell 5.1 and PowerShell 7 |
| Installer | `Install-ScreenshotCloud.ps1` copies the script and optionally adds a profile function |

### Tech stack

- Next.js 16 (App Router) + TypeScript + React 19
- Vercel deployment, Vercel Blob storage
- `@vercel/blob` SDK v2 (`put`, `list`, `del`)
- Windows PowerShell 5.1 / PowerShell 7 compatible uploader (`.NET System.Drawing`)

### Repository layout

```
ScreenshotCloud/
├─ .env.example                      # documented environment variable placeholders
├─ next.config.ts                    # remote image host allow-list for Blob thumbnails
├─ scripts/
│  ├─ Screenshot.ps1                 # capture + upload + print public URL
│  └─ Install-ScreenshotCloud.ps1    # per-user installer
└─ src/
   ├─ app/
   │  ├─ page.tsx                    # homepage
   │  ├─ login/page.tsx              # admin sign in
   │  ├─ dashboard/page.tsx          # gallery (auth gated, server rendered)
   │  └─ api/
   │     ├─ upload/route.ts          # POST, bearer auth, validation, blob put
   │     ├─ screenshots/route.ts     # GET list + DELETE (admin session)
   │     └─ auth/{login,logout}/route.ts
   ├─ components/                    # Gallery, ScreenshotCard, CopyButton, forms
   └─ lib/                           # auth/session, validation, blob wrappers
```

---

## 2. Local development setup

### Prerequisites

- Node.js 20.9+ (developed against Node 26)
- npm 10+
- Windows 10/11 for the PowerShell uploader

### Install dependencies

```powershell
cd ScreenshotCloud
npm install
```

### Configure local environment

```powershell
copy .env.example .env.local
notepad .env.local
```

Fill in the four required values described in [section 4](#4-environment-variables).

The easiest way to get real Blob credentials locally is the Vercel CLI:

```powershell
npx vercel login          # if you are not authenticated yet
npx vercel link           # link this folder to your Vercel project
npx vercel env pull       # writes .env.local including BLOB_READ_WRITE_TOKEN
```

`vercel env pull` will not create `SCREENSHOT_UPLOAD_KEY` or `ADMIN_PASSWORD` for you —
add those by hand (or with `npx vercel env add`).

### Run

```powershell
npm run dev        # http://localhost:3000
npm run lint       # ESLint
npm run typecheck  # tsc --noEmit
npm run build      # production build
npm start          # serve the production build locally
```

---

## 3. Vercel account, project and Blob store

### Create an account

1. Go to <https://vercel.com/signup> and sign up (GitHub is the quickest path).
2. Verify your email if prompted.

### Create the project

1. In the Vercel dashboard click **Add New… → Project**.
2. Choose **Import** next to your GitHub repository (`darkhackrrr/sscloud`).
3. Framework preset: **Next.js** (auto-detected). No build or output settings need changing.
4. Do **not** add environment variables yet — create the Blob store first (next step), then
   come back to **Settings → Environment Variables**.

### Create and connect the Vercel Blob store

1. Open your project in the Vercel dashboard.
2. Go to the **Storage** tab → **Create Storage** → **Blob**.
3. Click **Continue**.
4. **Access: Public** — this is required. The gallery embeds thumbnails and the PowerShell
   script returns a direct link that anyone with the URL can open. Private stores are not
   compatible with this project.
5. Give it a name, e.g. `screenshotcloud`.
6. Under environments, keep **Production** and **Preview** selected and also tick
   **Development** if you want `vercel env pull` to work locally.
7. Click **Create a new Blob store**.
8. Connect it to your project if the wizard did not do it automatically:
   **Storage → your store → Projects tab → Connect to Project**.

What Vercel adds for you:

| Variable | Purpose |
| --- | --- |
| `BLOB_STORE_ID` | Store identifier used with OIDC (not a secret) |
| `BLOB_READ_WRITE_TOKEN` | Long-lived read/write token (a secret) |
| `VERCEL_OIDC_TOKEN` | Issued and rotated by Vercel; you never handle it |

On Vercel the SDK prefers OIDC automatically; `BLOB_READ_WRITE_TOKEN` is the fallback and
is what you use locally.

---

## 4. Environment variables

Set these under **Project Settings → Environment Variables** (tick Production, Preview and
Development as appropriate).

| Name | Required | Where the value comes from | Used by |
| --- | --- | --- | --- |
| `BLOB_READ_WRITE_TOKEN` | Yes for local dev / non-Vercel | Created by Vercel when you make the Blob store. Copy it from **Storage → your store → Settings**, or run `npx vercel env pull`. | Server only |
| `BLOB_STORE_ID` | Auto | Added by Vercel when the store is connected. | Server only |
| `SCREENSHOT_UPLOAD_KEY` | **Yes** | You invent it. Generate a long random value, e.g. in PowerShell: `[guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")` | Server only (checked by `POST /api/upload`) |
| `ADMIN_PASSWORD` | **Yes** | You invent it. Used to sign in to `/dashboard`. | Server only |
| `SESSION_SECRET` | Recommended | You invent it. Signs the session cookie. If empty, a fallback is derived from `ADMIN_PASSWORD`. | Server only |
| `NEXT_PUBLIC_SITE_URL` | Optional | `https://your-site.vercel.app` | Metadata only |

Rules:

- None of these are `NEXT_PUBLIC_*` (except the optional site URL). Client-side JavaScript
  never receives `BLOB_READ_WRITE_TOKEN`, `SCREENSHOT_UPLOAD_KEY` or `ADMIN_PASSWORD`.
- Never commit `.env.local` — it is already in `.gitignore`.
- **Generate a different value for `SCREENSHOT_UPLOAD_KEY` and `ADMIN_PASSWORD`.**
  The upload key can only upload; it must never be able to delete.

### `.env.example`

`.env.example` contains documented placeholders only. There are no real secrets in this
repository.

---

## 5. Deploying

> **Deployment status:** this project has **not** been deployed yet. No Vercel
> authentication was available while it was being built, so no production URL exists.
> Follow one of the two paths below and only then claim the site is live.

### Option A — Vercel dashboard

1. Push the repository to GitHub (already configured for `https://github.com/darkhackrrr/sscloud.git`).
2. <https://vercel.com/new> → import the repository → **Deploy**.
3. After the first deploy: **Storage → create/connect the Blob store** (section 3).
4. **Settings → Environment Variables** → add every variable from section 4 → **Save**.
5. **Deployments → ⋯ → Redeploy** (env vars are only applied to new deployments).
6. Open the production URL and sign in at `/dashboard`.

### Option B — Vercel CLI

```powershell
npx vercel login                 # authenticate (only you can do this)
npx vercel link                  # associate this folder with a project
npx vercel env add SCREENSHOT_UPLOAD_KEY       # paste the value when prompted
npx vercel env add ADMIN_PASSWORD
npx vercel env add SESSION_SECRET
npx vercel blob store create --name screenshotcloud --access public   # if you have not made one
npx vercel --prod
```

Check your login status at any time with:

```powershell
npx vercel whoami
```

If that command does not return your account, run `npx vercel login` first and wait for the
confirmation to finish before deploying.

---

## 6. PowerShell uploader configuration

`scripts/Screenshot.ps1` captures the **entire primary monitor** as a PNG, uploads it to
`<Site>/api/upload`, parses the JSON response and prints the public URL.

### Configuration precedence

1. `-Site` / `-UploadKey` command-line parameters
2. `$Site` / `$UploadKey` variables at the top of `Screenshot.ps1`
3. `SCREENSHOTCLOUD_SITE` / `SCREENSHOTCLOUD_UPLOAD_KEY` environment variables
4. `%LOCALAPPDATA%\ScreenshotCloud\config.ps1` (written by the installer)

### Run directly

```powershell
cd .\scripts\
.\Screenshot.ps1 -Site "https://my-site.vercel.app" -UploadKey "MY_SECRET"
```

### Expected output

```
ScreenshotCloud
  [ok] Captured 1843.2 KB
  [ok] Uploaded via curl.exe (HTTP 201)

Screenshot uploaded successfully!

Screenshot link:
https://xxxxx.public.blob.vercel-storage.com/screenshots/6f1c....png
```

The success block is written to the **output stream** while progress goes to the host, so
you can capture just the link:

```powershell
$link = .\Screenshot.ps1 | Select-Object -Last 1
Set-Clipboard $link
```

### Behavior notes

- Works on Windows 10/11 with Windows PowerShell 5.1 and PowerShell 7+.
- Uses `curl.exe` when available (the upload key is passed to curl via a temporary
  config file, so it never appears on the command line); falls back to
  `Invoke-WebRequest` otherwise.
- No WSL, Linux tools, Python or browser required. **It never opens a browser.**
- The temporary PNG and response files are always deleted, even on failure.
- The upload key is never printed.
- Nothing runs automatically — no scheduled task, no startup entry, no background capture.

### Help

```powershell
.\Screenshot.ps1 -Help
```

---

## 7. Installing the `ScreenshotCloud` command

From the project's `scripts` folder:

```powershell
cd .\scripts\
.\Install-ScreenshotCloud.ps1
```

The installer:

1. Verifies it is running on Windows.
2. Creates `%LOCALAPPDATA%\ScreenshotCloud`.
3. Copies `Screenshot.ps1` there.
4. Prompts for your site URL and (masked) upload key.
5. Writes `%LOCALAPPDATA%\ScreenshotCloud\config.ps1` and restricts its permissions to your
   account plus `SYSTEM`.
6. **Asks before** adding a `ScreenshotCloud` function to your PowerShell profile.

Unattended example:

```powershell
.\Install-ScreenshotCloud.ps1 -Site "https://my-site.vercel.app" -AddToProfile
```

> Passing `-UploadKey` on the command line can leave the secret in your shell history —
> prefer the masked prompt.

### Using it

Open a **new** PowerShell window (or reload your profile):

```powershell
. $PROFILE          # only needed in the current session
ScreenshotCloud
```

Also supported:

```powershell
ScreenshotCloud -Help
ScreenshotCloud -Site "https://another-site.vercel.app"
ScreenshotCloud -Site "https://..." -UploadKey "..."
```

The profile block only **defines** a function. Installing it does not capture anything and
does not run at logon.

### Uninstall

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\ScreenshotCloud"
# then delete the block between "# >>> ScreenshotCloud >>>" and "# <<< ScreenshotCloud <<<"
# from your PowerShell profile.
```

---

## 8. Using the gallery

1. Visit `/dashboard`. You are redirected to `/login` if you are not signed in.
2. Sign in with `ADMIN_PASSWORD`.
3. Screenshots are listed live from the `screenshots/` prefix of your Blob store,
   24 per page, each page sorted newest first. Use **Load more** to continue.
4. Every card shows the thumbnail, generated filename, upload date and size, plus:
   - **Copy link** — copies the public URL to the clipboard
   - **Open** — opens the full-size image in a new tab
   - **Delete** — confirmation dialog, then `DELETE /api/screenshots`
5. **Refresh** re-reads the store; **Sign out** clears the session cookie.

There are no fake/seeded records: the dashboard only ever renders objects that exist in
Vercel Blob. An empty store shows an empty state.

---

## 9. Security model

| Credential | Grants | Stored |
| --- | --- | --- |
| `SCREENSHOT_UPLOAD_KEY` | Upload a screenshot (`POST /api/upload`) only | Server env var + your local config file |
| `ADMIN_PASSWORD` | Sign in to `/dashboard` | Server env variable only |
| Session cookie | List + delete screenshots | HTTP-only, `SameSite=Lax`, `Secure` on HTTPS, HMAC-signed, 7 days |
| `BLOB_READ_WRITE_TOKEN` | Read/write the Blob store | Server env variable only — never sent to the browser |

Other guarantees:

- Filenames are generated server-side with `crypto.randomUUID()`; uploaded names are ignored.
- File type is verified by magic bytes (PNG/JPEG/WebP), not by the `Content-Type` header.
- Size is checked from `Content-Length` **and** from the actual payload (10 MB max).
- `DELETE /api/screenshots` requires an admin session and only accepts URLs under the
  `screenshots/` prefix of a `*.blob.vercel-storage.com` host. **The upload key does not
  grant delete access.**
- Login attempts are rate limited (10 per 15 minutes per client, best effort in memory).
- Secrets are never returned in API responses.

---

## 10. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `HTTP 401` from the uploader | Wrong or missing `SCREENSHOT_UPLOAD_KEY`. Compare with **Settings → Environment Variables** on Vercel. Redeploy after changing it. |
| `HTTP 503 The server is not configured` | `SCREENSHOT_UPLOAD_KEY` is not set in the deployment's environment variables. |
| `HTTP 413 file_too_large` | Screenshot over 10 MB. Note Vercel's own request-body limit (~4.5 MB on the Hobby plan) may reject large bodies first — see the next row. |
| Upload fails around 4–5 MB with no useful body | Vercel serverless request-body limit. Lower your resolution, upgrade the plan, or reduce the capture size. |
| `HTTP 415 unsupported_media_type` | The payload was not a real PNG/JPEG/WebP. The script always writes PNG, so this usually means a proxy modified the body. |
| `HTTP 502 blob_upload_failed` | Blob credentials are wrong, the store is not connected to the project, or the store is **private**. The store must be **Public**. |
| Gallery says "Could not reach Vercel Blob" | Same as above — check `BLOB_STORE_ID` / `BLOB_READ_WRITE_TOKEN` and that the store is connected. |
| `HTTP 401 unauthorized` on the dashboard | Session expired. Sign in again at `/login`. |
| `HTTP 401 invalid_password` | Wrong `ADMIN_PASSWORD`. |
| `Could not resolve the host name` / `Could not connect` (curl exit 6/7) | No internet, wrong `-Site` URL, or the deployment has not finished deploying. |
| "The site returned an HTML page instead of JSON" | A proxy, captive portal or Vercel deployment page answered. Check the URL and try again after the deployment finishes. |
| `curl.exe not found - falling back to Invoke-WebRequest` | Harmless. `curl.exe` ships with Windows 10 1803+; the fallback is used otherwise. |
| `Screenshot capture failed` | No interactive desktop session (e.g. over some remote/headless sessions). Run it in your normal desktop session. |
| Thumbnails not loading | The Blob store must be **Public**, and `next.config.ts` must allow `*.blob.vercel-storage.com`. |
| `Session signing secret missing` | Set `SESSION_SECRET` or `ADMIN_PASSWORD`. |

### Verify your secrets are not in git

```powershell
git check-ignore -v .env.local     # should match a .gitignore rule
git status --porcelain             # .env.local must not be listed
```

---

## Not tested yet

The following could not be verified in the build environment and need a real Vercel
account:

- An actual `put()` / `list()` / `del()` against a live Vercel Blob store.
- A real production deployment (no Vercel authentication was available).
- PowerShell 7 (`pwsh`) — it is not installed on the build machine. `Screenshot.ps1` is
  written for both editions and is syntax-checked under Windows PowerShell 5.1, but the
  7.x runtime has not been executed.

API authentication, validation (401/400/413/415), the admin session flow, the production
build, ESLint and `tsc` were all run locally — see the project notes for the results.
