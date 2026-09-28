# Changelog

## 0.1.0 (Unreleased)

Suchi Companion's first release brings secure mobile capture, upload, archive
browsing, and offline access to self-hosted Suchi accounts.

### Capture and upload

- Scan multi-page documents with the native Android and iOS document scanners,
  or capture a full-frame photo and convert it to a one-page PDF.
- Import PDFs and images from Files, Photos, Android sharing, and the iOS Share
  Extension into protected, account-bound staging.
- Track queued, uploading, processing, failed, and completed work across the
  app, with explicit retry, reassignment, and discard controls.
- Preserve unresolved files across restarts, connectivity loss, and account
  transitions without silently uploading them to another account.

### Documents

- Browse Inbox, document categories, Saved Views, Search, and Trash with
  Standard, Compact, or Detailed rows and configurable sorting.
- Open and share full documents, read extracted text, preview email bodies in a
  sandboxed WebView, and edit titles, filing, language, sensitivity, and tags.
- Swipe right on an online Documents row to save or update its offline copy;
  swipe left on a saved row to open confirmed local removal.
- Browse saved copies in **Offline documents**. A full left swipe opens removal
  confirmation, while a partial left swipe keeps a tappable Remove action.
- Keep offline files in protected, backup-excluded, account-scoped storage with
  atomic writes, restart verification, a 64 MiB per-file limit, and a 512 MiB
  free-space reserve.

### Pairing and offline use

- Pair by single-use QR/link, password, or scoped token after confirming the
  server origin and negotiating the `suchi-companion-v1` contract.
- Require HTTPS outside debug-only local development and never send credentials
  across redirects or to external URLs.
- Continue using Documents, Scan, and More with a verified account during a
  network outage; uploads resume only after authenticated recovery.
- Quarantine offline copies during sign-out and restore them if credential
  deletion fails, avoiding partial or falsely successful sign-out.

### Privacy and accessibility

- Require explicit reveal before showing or retaining sensitive document
  content, and clear transient content on backgrounding or identity changes.
- Protect the app switcher and accessibility tree while the app is inactive.
- Explain device-local storage in **Privacy & storage**, including account and
  device totals plus explicit cleanup controls.
- Meet WCAG AA contrast for semantic text and controls, support large text and
  reduced motion, and keep primary touch targets at least 48 logical pixels.
- Include Android ML Kit disclosures and the required iOS privacy manifests.

### App and platform

- Ship as **Suchi Companion** with application ID `page.suchi.companion`, the
  four-strike Companion icon, light/dark/system appearance, and iPhone-only iOS
  distribution.
- Target Android API 36 with API 31 as the minimum; require iOS 26.0.
- Keep **About** limited to the installed version, license notices, and the
  stable `https://suchi.page/` root.
- Pin the exact compatible Suchi server revision and mirrored API fixtures used
  to verify this build.

### Release verification

- Run formatting, static analysis, Flutter tests, API fixture checks, Android
  lint/build checks, isolated iOS builds, and secret-canary checks in CI.
- Retain physical-device gates for scanner, camera, picker/share imports,
  cancellation, backgrounding, queue recovery, and account transitions before
  store submission.
