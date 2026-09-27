# Changelog

## Unreleased

### Changed

- Raise subdued text, semantic status colors and control outlines to WCAG AA
  contrast in light and dark themes, including actions on the camera surface.
- Keep document selectors and swipe actions at least 48 by 48 logical pixels
  and cover those platform touch-target dimensions in widget tests.
- Remove concealed app content from accessibility and pointer hit testing while
  the lifecycle privacy shield covers the screen.
- Embed required-reason privacy manifests in both iOS executables. Runner
  declares app-container file timestamps and disk capacity; the Share Extension
  declares its disk-capacity guard.
- Open Documents after a successful empty initial Inbox load, without
  overriding a failed load, a deliberate tab choice or a changed account.
- Round and clip Documents sorting and offline-copy option popups to match
  Scan's long-press mode picker on Android and iOS.
- Run iOS builds with an explicit environment allowlist, disable Xcode shell
  environment logging, and fail the native-build canary if inherited secret
  values reach activity logs or build-data attachments.
- Set the first-release floors to Android API 26 and iOS 16 while retaining
  Android target API 36. iOS distributes to iPhone only; Android remains
  resizable for large screens without claiming a tablet-specific interface.
- Regenerate Android legacy, adaptive and monochrome launcher icons plus the
  opaque iPhone and App Store catalog from committed canonical vectors. Remove
  iPad-only icon slots and validate generated icon dimensions and alpha modes.
- Persist the downloaded offline representation's MIME type, byte count and
  SHA-256 digest independently from remote source metadata. Rehash copies on
  startup and use payload metadata for filenames, previews and native handoff,
  including image sources archived by the server as PDF.
- Preserve a 512 MiB free-space reserve before bounded camera, picker/share,
  queue, temporary export and offline writes. Low-storage failures keep
  unresolved sources and previously verified offline copies available for
  retry instead of replacing or falsely completing them.
- Add account and device-wide storage totals to **More → Privacy & storage**,
  including queue bytes and free space. Users can explicitly remove current
  account or all offline copies without bulk-deleting unresolved uploads.
- Timestamp in-app picker ownership and reconcile it on cold start. Claims
  without a protected native batch expire after 24 hours; retained batches
  remain account-bound, and Android clears matching abandoned launch markers.
- Recover a complete abandoned Android Photo output into the protected capture
  store on cold resume, remove empty or invalid output, and retain valid bytes
  when storage recovery must be retried.
- Reject zero-byte payloads consistently across Android OS sharing and pickers,
  iOS Files/Photos/Share Extension intake, and the Dart native-manifest boundary.
- Prune successful queue history and completed share/capture duplicate receipts
  after 30 days or beyond the newest 20 records, including on cold start.
- Make sign-out transactional for offline copies: quarantine before credential
  deletion, restore on credential failure, and expose protected leftovers or
  expired-account copies for explicit cleanup in **Privacy & storage**.

- Promote the current Documents scope to its heading, with search and sort
  alongside, document/offline counts below, and **Saved offline** in the scope
  picker. The inline saved-copy count stays right-aligned and becomes
  **← All documents** when returning from saved copies is available.
  Documents' search action now focuses Search's input; ordinary tab selection
  does not.
- Match Android's launch mark to the iPhone's compact visual scale and keep the
  complete rounded silhouette inside Android 12 splash and circular launcher
  icon safe areas.
- Prepare free `1.0.0+1` release candidate without payments, purchases,
  upgrades or Saved View entitlement gates. Public store approval and source
  publication remain separate owner decisions.
- Require HTTPS for all non-debug server origins, including restored tokens.
  Debug-only localhost/private-LAN HTTP remains available for development;
  redirects never receive credentials, and refused origins leave queued files.
- Negotiate the server-declared `suchi-companion-v1` wire contract instead of
  comparing server and app release numbers. A server without an explicit
  declaration can proceed to scoped token verification; an explicit incompatible
  contract list is refused before credentials are sent.
- Restore the standard iOS left-edge back gesture while preserving the current
  document list, filter, sort and scroll position.
- Saving document title, language, filing, sensitivity or tag changes clears
  classifier-owned `needs-review` on the server while preserving user-owned
  review tags; partial-save retries do not re-add a cleared marker.

- Rename the mobile app to **Suchi Companion** across Android/iOS app labels,
  Flutter branding and accessibility, permission descriptions and the iOS share
  extension. Suchi remains the server/web product name. Replace the unpublished
  development-only app ID with `page.suchi.companion` on Android and iOS;
  the iOS extension and Runner use `group.page.suchi.companion`. This is a
  fresh install without migration or aliases. The Dart package `suchi_mobile`,
  pairing links and logical private-storage keys remain unchanged.
- Require the current server identity and pairing contracts. Account, queue,
  capture, share, search and Saved View boundaries now include the token's
  filing-system ID. Changing filing systems requires pairing again.
- Rebase the unreleased queue database schema and recovery manifest to version
  1. Older pre-release formats fail clearly and remain untouched; there is no
  mobile schema migration or silent reset path. Queue database,
  journals and temporary files now live with payloads in the protected,
  backup-excluded queue directory. Startup detects the former database location
  before reconciliation so existing pre-release queue files are not pruned.

### Added

- Show byte progress while saving a document offline, both in document detail
  and in the persistent Documents activity bar after a swipe save. The indicator
  stays in a finishing state until the protected copy is verified; Cancel
  abandons the transfer without replacing an existing saved copy.
- Import PDF or image files directly from **Scan → Files** and images from
  **Scan → Photos** through the system pickers. Native staging, durable
  per-account claims, receipts, partial rejection and explicit retry reuse the
  existing protected queue; account changes cannot adopt an open picker batch.
  Controls stay usable at large text without covering upload recovery.
- Link **More → Explore Suchi** to the fixed public `https://suchi.page`
  website, distinct from the paired web app. **Privacy & storage** still
  explains local behavior; a public policy and monitored privacy contact
  remain separate requirements before store submission.
- Tap the raised centre camera button to use the last mode; long-press for a
  nearby Scanner/Photo picker that remembers the choice and starts capture.
  The tiny label below the icon is removed; haptic hold feedback, a spoken
  button label and the Camera mode setting retain the alternative controls.
  Release the hold, then tap a mode—release alone never captures. The picker
  respects reduced motion.
  More's Camera mode preference uses the same bottom-sheet presentation as
  Appearance and Document view, without starting capture.
  Ordinary photos retain the full frame as a one-page PDF
  and reuse protected capture storage, OCR, recovery and the upload queue.
- Persistent System/Light/Dark appearance with Suchi's signature palette,
  reduced-motion-aware transitions, and grouped More settings. Account and
  privacy details stay available in focused sheets.
- Compact More groups with inline preference values, shorter rows and a combined
  header using the Suchi mark, Suchi Companion name and “Capture on your phone.
  Keep it in your archive.” tagline. Larger text stacks
  values and remains scrollable; full explanations stay in the detail sheets.
- Standard, Compact and Detailed document views selected in More, with preserved
  browsing position, cleaner archive controls and metadata-only sensitive rows.
- Truthful shared-import and upload activity across the app, including secure
  staging, byte transfer, server processing and retained retry/account warnings.
  View opens the queue without capture; new completions refresh archive lists.
- Open accepted Scan uploads and split child documents through the existing
  document viewer, with account-bound pickers and independent recovery actions.
- Preview-first document detail with a filled **Open** action and outlined
  **Save offline** beside it (stacked at larger text). Type, size and offline
  status now sit inside the preview well; a compact options menu exposes
  stale-copy update and confirmed removal without competing with Open.
  Top-bar sharing and responsive reader/filing actions remain. The always-visible
  **Details** card includes added date and source, without exposing the blob ID;
  tapping its Sensitivity row changes classification directly. Sensitive choices
  immediately conceal the preview; stale refreshes remain explicit.
- Render email bodies inline through a sandboxed, credential-free WebView.
  JavaScript, navigation, forms, frames and remote resources stay blocked;
  sensitive email still requires Reveal and full-file handoff uses `.eml`.
- Slightly larger raised Scan action with real hit-test/upload-strip clearance,
  subtle navigation motion, readable queue states and keyboard-aware JD sheets.
- Compact pairing and Search introductions without changing trust or query flows.
- Synchronize Saved Views through the paired Suchi server on Android and iOS.
  Named queries can be created, opened as an exact Documents scope and deleted;
  flat legacy and snapshot filters are preserved, while unsupported future
  filters remain visible and fail closed without a partial document request.
- Keep selected full documents in protected, backup-excluded, account-scoped
  storage. Atomic retention, restart reconciliation and 64 MiB bounds protect
  verified files without persisting previews or extracted text. Native viewers
  receive only committed payloads, never staging files or manifests.
  Swipe right on an online Documents row to save or update a copy; swipe
  left on a saved row, including the offline library, to confirm local removal.
  Actions close when tapped and can be reopened to inspect or cancel work.
  Documents' **Saved offline** scope and tappable inline count open copies
  locally, including while connected. More does not duplicate that library.
  A verified saved account can use Documents, Scan and More after network
  failure. Scans enter the same protected, account-bound queue; uploads stay
  paused until authenticated retry succeeds, not merely until connectivity
  returns. Inbox, Search and Trash then return. Sensitive retention/handoff
  requires confirmation, and sign-out removes offline copies before credentials.
- Document capture keeps each platform's full native scanner pipeline for edge
  detection, perspective straightening, rotation, lighting cleanup, page edits
  and review before the shared upload flow.
- Read extracted text from document detail without exporting the file. Sensitive
  text asks for confirmation, including server-side reclassification. The
  memory-only reader clears on background or account changes, supports retry
  and pages long text while keeping ordinary detail requests metadata-only.
- Pair by scanning a single-use QR code or pasting its link from the web app.
  Confirm the server address before exchange; manual password/token pairing and
  text entry remain available when camera or clipboard access is unavailable.
- Edit document titles, language overrides and existing tag assignments;
  search the server tag catalog to add or remove tags without creating new ones.
  Sensitivity changes live in Details. Clearing languages resumes automatic
  detection.
- Sort archive documents by newest, oldest, title or recent updates while
  retaining the selected filing category.
- More → Trash keeps recently deleted documents available for recovery, with
  paging, pull-to-refresh, retry and archive refresh after restoration. The
  server enforces the 30-day recovery window.
- Open full documents in the device viewer or share a downloaded copy. Sensitive
  files require confirmation; downloads use scoped credentials and protected
  temporary storage with cancellation and a 64 MiB size limit.

### Fixed

- Show a strongly blurred, tinted live screen instead of a plain app-switcher
  card on iOS and Android 12+. Android 8–11 uses a blank Recents card and
  disables screenshots because it can snapshot before pause callbacks.
  Returning to the app restores its readable screen.
- Keep ML Kit's manifest-discovered component registrar constructors in
  Android release shrinking so the optimized app launches and scanning
  dependencies initialize.

- Detect PDF/HEIC signatures without decoding binary PNG/JPEG header bytes as
  ASCII, so supported picker images can enter the protected queue.
- QR/link pairing fills in the device name and lets it be edited before
  connecting, so the server shows that name under Mobile app. iOS can
  provide a generic name; unavailable name lookup keeps pairing usable.
- Preserve Documents and Inbox scroll position and loaded pages when returning
  from viewing a document, including the Documents category and sort order.
  Refresh lists only after successful changes; Trash Undo now refreshes them too.
- Give shared cards a Material surface so list tiles paint visible touch feedback
  and satisfy Flutter's background checks.
- Normalize capture receipt paths so a committed camera capture is not staged
  twice after restart when Apple system paths have different spellings. Linked
  capture files remain refused without modifying their targets.
- Ignore late scanning and credential-exchange results after a session change.
- Account changes cancel downloads and remove temporary document copies.
  Sign-out reports local cleanup failures without claiming success.

### Development

- Pin the exact compatible server revision and refresh mirrored API contracts,
  including token filing-system identity.
- One Make entry point for analysis, tests, fixture checks and native builds,
  with explicit architecture and agent instructions for feature ownership,
  account isolation and the later mobile release.
