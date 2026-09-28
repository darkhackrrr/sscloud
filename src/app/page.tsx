import Link from "next/link";

import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";

const STEPS = [
  {
    title: "Press the shortcut",
    text: "Run the PowerShell command on your Windows PC. The whole primary monitor is captured as a PNG in a few hundred milliseconds.",
  },
  {
    title: "Uploads itself",
    text: "The script POSTs the image to /api/upload with your bearer upload key. Validation happens on the server before anything is stored.",
  },
  {
    title: "Paste the link",
    text: "The public Vercel Blob URL is printed straight back into your terminal. No browser tab, no drag-and-drop, no third-party host.",
  },
];

const FEATURES = [
  {
    icon: "🔐",
    title: "Two separate credentials",
    text: "A bearer upload key protects POST /api/upload. A different admin password gates the dashboard and every delete operation.",
  },
  {
    icon: "🗂️",
    title: "Real Blob storage",
    text: "Screenshots live under the screenshots/ prefix in Vercel Blob with server-generated UUID filenames. Nothing is kept on the app server.",
  },
  {
    icon: "⚡",
    title: "Built for PowerShell",
    text: "Works on Windows 10 and 11 with Windows PowerShell 5.1 and PowerShell 7, using curl.exe or Invoke-WebRequest as a fallback.",
  },
  {
    icon: "📱",
    title: "Responsive dashboard",
    text: "Thumbnails, file sizes, upload dates, copy-link, open and confirmed delete - on a dark UI that works on phone and desktop.",
  },
  {
    icon: "🧾",
    title: "Clear error messages",
    text: "401, 413, 415, offline and malformed responses all surface as readable text instead of a raw stack trace.",
  },
  {
    icon: "🚫",
    title: "Explicit by design",
    text: "No stealth capture, no keylogging, no background timers. A screenshot only happens when you run the command.",
  },
];

export default function HomePage() {
  return (
    <>
      <SiteHeader />

      <main>
        <section className="hero">
          <div className="container">
            <span className="hero__eyebrow">
              <span aria-hidden="true">⌘</span> Windows · PowerShell · Vercel Blob
            </span>

            <h1 className="hero__title">
              Screenshot to <em>shareable link</em> in one command.
            </h1>

            <p className="hero__subtitle">
              ScreenshotCloud captures your primary monitor from PowerShell, uploads it to your own
              Vercel-hosted site, and prints a public URL you can paste anywhere - without ever
              opening a browser.
            </p>

            <div className="hero__actions">
              <Link className="btn btn--primary" href="#setup">
                How it works
              </Link>
              <Link className="btn btn--ghost" href="/dashboard">
                Open the dashboard
              </Link>
            </div>
          </div>
        </section>

        <section className="section" id="setup">
          <div className="container">
            <div className="section__head">
              <span className="section__kicker">The flow</span>
              <h2 className="section__title">Three steps, zero browser tabs</h2>
              <p className="section__lead">
                Everything runs from your terminal. The website is only there to store the images
                and give you a gallery to manage them.
              </p>
            </div>

            <div className="steps">
              {STEPS.map((step, index) => (
                <div className="step" key={step.title}>
                  <span className="step__num">{index + 1}</span>
                  <h3 className="step__title">{step.title}</h3>
                  <p className="step__text">{step.text}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="section">
          <div className="container">
            <div className="grid grid--2">
              <div className="code">
                <div className="code__bar">
                  <span>powershell · upload</span>
                  <span>one-liner</span>
                </div>
                <pre>
                  <code>
                    <span className="tok-cmd">.\Screenshot.ps1</span> <span className="tok-flag">-Site</span>{" "}
                    <span className="tok-str">&quot;https://my-site.vercel.app&quot;</span>{" "}
                    <span className="tok-flag">-UploadKey</span> <span className="tok-str">&quot;MY_SECRET&quot;</span>
                  </code>
                </pre>
              </div>

              <div className="code">
                <div className="code__bar">
                  <span>powershell · after install</span>
                  <span>profile function</span>
                </div>
                <pre>
                  <code>
                    <span className="tok-cmd">ScreenshotCloud</span>
                    {"\n"}
                    <span className="tok-comment"># Screenshot uploaded successfully!</span>
                    {"\n"}
                    <span className="tok-comment"># https://xxxx.public.blob.vercel-storage.com/…</span>
                  </code>
                </pre>
              </div>
            </div>
          </div>
        </section>

        <section className="section">
          <div className="container">
            <div className="section__head">
              <span className="section__kicker">Under the hood</span>
              <h2 className="section__title">Production ready, not a demo</h2>
            </div>

            <div className="grid grid--3">
              {FEATURES.map((feature) => (
                <div className="card card--hover" key={feature.title}>
                  <span className="card__icon" aria-hidden="true">
                    {feature.icon}
                  </span>
                  <h3 className="card__title">{feature.title}</h3>
                  <p className="card__text">{feature.text}</p>
                </div>
              ))}
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
    </>
  );
}
