# Changelog

## Unreleased

### Changed

- Prepare free `1.0.0+1` release candidate without payments, purchases,
  upgrades or Saved View entitlement gates. Public store approval and source
  publication remain separate owner decisions.
- Require HTTPS for all non-debug server origins, including restored tokens.
  Debug-only localhost/private-LAN HTTP remains available for development;
  redirects never receive credentials, and refused origins leave queued files.
- Restore the standard iOS left-edge back gesture while preserving the current
  document list, filter, sort and scroll position.

- Rename the mobile app to **Suchi Companion** across Android/iOS app labels,
  Flutter branding and accessibility, permission descriptions and the iOS share
  extension. Suchi remains the server/web product name. Package and bundle IDs,
  app groups, pairing links and private storage identities are unchanged.
- Require the current server identity and pairing contracts. Account, queue,
  capture, share, search and Saved View boundaries now include the token's
  filing-system ID. Changing filing systems requires pairing again.
- Use a fresh-install local storage baseline for this unreleased app. Older
  queue databases and recovery manifests fail clearly and remain untouched;
  there is no mobile schema migration or silent reset path. Queue database,
  journals and temporary files now live with payloads in the protected,
  backup-excluded queue directory. Startup detects the former database location
  before reconciliation so existing pre-release queue files are not pruned.

### Added

- Import PDF or image files directly from **Scan → Files** and images from
  **Scan → Photos** through the system pickers. Native staging, durable
  per-account claims, receipts, partial rejection and explicit retry reuse the
  existing protected queue; account changes cannot adopt an open picker batch.
  Controls stay usable at large text without covering upload recovery.
- Add a visible **More → Privacy policy** link to the public HTTPS website.
  That draft needs deployment and a monitored owner privacy contact before
  any store submission; it is not a claim of store approval.
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
- Preview-first document detail with a softly translucent **Open** button at
  the preview's lower right, top-bar sharing and responsive reader/filing
  actions. The always-visible **Details** card includes added date and source,
  without exposing the blob ID; tapping its Sensitivity row changes
  classification directly. Sensitive choices immediately conceal the preview.
  File type, size and offline controls stay with the preview; stale refreshes
  remain explicit.
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
- Keep selected full documents available offline in protected,
  backup-excluded, account-scoped storage with atomic updates, restart
  reconciliation, 64 MiB limits and no persistent previews or extracted text.
  Swipe left on an online Documents row for Make/Update offline copy; a fresh
  detail fetch checks classification before retention. Documents and More expose
  offline copies; verified saved sessions can enter a local-only Documents/More
  shell after network failure and explicitly retry the anonymous handshake.
  Sensitive retention/handoff requires confirmation, and sign-out removes
  offline copies before credentials.
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
