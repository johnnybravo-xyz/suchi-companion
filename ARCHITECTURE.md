# Suchi Companion architecture

Suchi Companion is a Flutter client for capturing documents and using a
self-hosted Suchi archive. Flutter owns the shared Android and iOS interface.
Native adapters own camera/scanner integration, protected platform storage,
sharing, and file viewing.

The application ID is `page.suchi.companion` on Android and iOS. The iOS Runner
and Share Extension share `group.page.suchi.companion`. Platform channels use
the `page.suchi.companion/` prefix with `pairing`, `documents`, `scan`, `share`,
and `storage` suffixes. Android targets API 36 with API 31 as its minimum. iOS
targets iPhone with iOS 26.0 as its minimum.

## Ownership

| Concern                               | Owner                                                                                       |
| ------------------------------------- | ------------------------------------------------------------------------------------------- |
| Startup, dependency lifetime, cleanup | `lib/main.dart`, `lib/app/app_services.dart`                                                |
| Navigation and archive refresh        | `lib/shell/shell.dart`                                                                      |
| Origin validation and sessions        | `lib/auth/session_controller.dart`, `server_origin.dart`, `credential_vault.dart`           |
| Pairing links and native QR input     | `lib/auth/pairing_link.dart`, `pair_screen.dart`, native `PairingChannel` adapters          |
| HTTP contracts and response bounds    | `lib/api/suchi_client.dart`, `api_models.dart`, `api_error.dart`                            |
| Capture, queueing, and upload         | `lib/scan/scan_capture_controller.dart`, `scan_queue_store.dart`, `upload_coordinator.dart` |
| Share and picker intake               | `lib/share/`, `ScanQueueScreen`, native `ShareChannel` adapters, `ios/Shared/`              |
| Archive screens and document detail   | `lib/documents/`, `lib/inbox/`, `lib/search/`, `lib/detail/`, `lib/trash/`                  |
| Saved Views                           | `lib/search/saved_views.dart`, shell-owned `SavedViewController`                            |
| Document and date approval review     | `lib/approvals/`, shell-owned `ApprovalsController`                                         |
| Offline documents                     | `lib/offline/offline_document_store.dart` and native document channels                      |
| Settings and presentation             | `lib/more/`, `lib/widgets/suchi_widgets.dart`, `lib/theme/suchi_theme.dart`                 |

Screens own their loading, paging, error, and selection state. The shell passes
explicit revision counters after successful mutations. Opening and closing a
document does not refresh lists, which preserves loaded pages, scope, sorting,
and scroll position. Async callbacks verify their client, account identity, and
widget lifetime before publishing state.

`AppSettingsController` stores device-wide appearance, document-row density,
and capture mode in Drift. `SuchiColors` supplies the shared light/dark palette,
and motion helpers honor reduced-motion settings. More owns focused settings,
account, privacy, and About sheets and closes account-bearing sheets when the
identity changes.

## Trust and account boundary

Pairing calls `/api/handshake` without credentials and verifies the resulting
mobile token with `/api/whoami`. An explicit `mobile_contracts` response must
include `suchi-companion-v1`. Product identity, required mobile scopes, user ID,
and filing-system ID are validated before credentials are stored. App and server
release numbers do not define wire compatibility.

`ServerOrigin` requires HTTPS in profile and release builds. Debug builds may
use localhost or private-LAN HTTP. Redirects are refused, and credentials are
never sent until the unauthenticated origin check succeeds. Platform secure
storage contains the token and a bounded verified user snapshot; passwords and
pairing codes are never persisted.

An account identity is the normalized origin, server user ID, and filing-system
ID. Capture, imports, queued uploads, downloads, offline files, Saved Views, and
in-memory readers bind to this tuple. Identity changes invalidate async work and
prevent files or results from being adopted by another account.

A verified snapshot permits `SessionState.offline` only for network and timeout
failures. Authentication rejection, redirects, invalid origins, malformed
responses, or missing scopes fail closed. Offline mode provides Documents,
Scan, and More without constructing an authenticated API client. Inbox, Search,
and Trash return after **Retry** completes a fresh anonymous handshake and
authenticated identity check. Connectivity alone never starts uploads.

Sign-out pauses account work, quarantines verified offline directories, and then
deletes the credential. A credential-deletion failure rolls the quarantine back
and restores the session. A cleanup failure after credential deletion keeps the
data inaccessible and exposes it only through confirmed storage cleanup.
Queued uploads are never deleted as a side effect of sign-out.

### Pairing inputs

`PairingLink.parse` accepts only
`suchi://pair?v=1&server=<encoded-origin>&code=<one-time-code>`. It rejects
unexpected or repeated parameters, outer userinfo, ports, paths, and fragments,
then applies the standard origin policy. The user confirms the normalized server
and an editable device name before token exchange.

Android uses Google Play services Code Scanner with auto-zoom and install-time
`barcode_ui` delivery. iOS uses AVFoundation. QR contents are returned as text;
native adapters do not open URLs or handle account credentials. Device-name
lookup is time-bounded and introduces no hardware identifier or local cache.
Paste reads the clipboard only after an explicit user action. Manual pairing
stays available when camera, scanner, device-name, or clipboard access fails.

## Capture, import, and upload

The Scan dock starts the saved Scanner or Photo mode. Long press opens the mode
picker without starting capture. Native capture writes protected local files,
then Dart validates and stages them in the SQLite-backed queue before
acknowledging handoff.

Android document scanning uses Google Play services ML Kit for page capture,
edge detection, perspective correction, rotation, filters, and review. Android
copies scanner content-provider results and full-size camera output into the
protected capture store on a dedicated serial I/O thread before replying to
Dart. iOS uses VisionKit for document scanning and the system still-camera
picker for Photo. Neither platform writes captures to the user's photo library.
Photo pages enter the shared PDF, OCR, recovery, and upload pipeline.

Android Photo uses a non-exported `PhotoCaptureProvider` and a single full-size
output URI. URI grants are revoked on return. A valid interrupted photo can be
recovered on activity resume; empty, invalid, linked, oversized, or out-of-root
files are refused. Capture receipts hash resolved directories and commit
atomically with queue staging.

Files, Photos, Android sharing, and the iOS Share Extension use one inspected
import boundary per platform. An in-app picker records its UUIDv4 batch ID,
creation time, and account identity before native UI opens. Native adapters
allow at most 20 PDF or image items, require positive byte counts, cap each item
at 64 MiB, and request no broad photo or storage permission. Each receipt becomes
durable before native bytes are discarded. Unsupported items are reported.
Claims without native data expire after 24 hours; a retained native batch keeps
its assigned owner.

`ScanQueueStore` is the sole durable upload path. Its database, journals,
payloads, OCR text, and recovery manifests share a protected, backup-excluded
directory. Schema and recovery manifest version mismatches fail explicitly and
leave files untouched. Unassigned files require explicit assignment, and
foreign-account rows stay durable but hidden.

`UploadCoordinator` sends durable idempotency keys and distinguishes byte
transfer, server acceptance, processing, filing, duplication, and failure.
Network loss pauses work. Failed items stay until the user retries or discards
them. Successful history and deduplication receipts are limited to the newest
20 and 30 days. The shell observes account-scoped completion transitions to
refresh archive lists without treating historical results as new activity.

## Archive and document state

Inbox, Documents, Search, Saved Views, and Trash use server-authoritative
metadata and permissions. List requests do not download document bodies.
Documents sorting resets paging while retaining its filing scope. Saved Views
are fetched from the server and applied as complete typed filters; malformed or
unsupported filters remain visible but fail before a document request.

Inbox uses full horizontal gestures for File and Trash. Online Documents rows
use the same gesture model: a full right swipe saves or updates the offline
copy, and a full left swipe opens confirmed removal when a copy exists. Rows
without an offline copy do not accept a left action.

**Offline documents** is a Documents scope backed entirely by verified local
manifests. A full left swipe opens removal confirmation. A partial left swipe
keeps a tappable Remove action visible. Offline rows never contact the server
to open or remove a local copy.

Document detail loads metadata first. Opening, sharing, extracted-text reading,
and email previewing are separate bounded requests. Editing title, language,
filing, sensitivity, or tags reloads authoritative detail and verifies each
bulk-edit result. Tag creation is not a mobile operation. Sensitivity changes
conceal revealed content before the next frame.

The shell-owned `ApprovalsController` loads supported document-change approvals
(title, filing category, and tag) and pending date intelligence independently
for the active online account. Inbox shows one manila approvals card above its
document list only while supported approvals are pending; the account avatar
remains an inert identity indicator on every screen. The approvals route
captures its originating identity and client, removes itself on an account
transition, and never publishes late reads or mutations from a previous
account. Rows remain until a mutation is confirmed; stale or conflicting
reviews trigger an authoritative reload. Unsupported server approval types stay
hidden rather than creating a second generic workflow.

`message/rfc822` previews receive bounded authenticated HTML from Dart and load
it into a credential-free WebView. JavaScript, navigation, forms, frames, and
remote resources are disabled by a restrictive CSP. Email HTML stays in memory
and is cleared on Hide, backgrounding, memory pressure, disposal, or identity
change.

`lib/detail/document_text_screen.dart` fetches extracted text only after the
reader opens. It shares the API's 8 MiB JSON limit and pages at 12,000 UTF-16
units without splitting surrogate pairs. Text is rendered literally and kept
only in memory. Sensitive metadata and server-side reclassification require
explicit confirmation.

## Offline files and storage

`OfflineDocumentStore` owns `suchi-offline-documents` in protected,
backup-excluded application support. Each committed `offline-<UUID>/` contains
one payload and a bounded versioned manifest with account identity, remote
metadata, response MIME type, filename, byte count, SHA-256 digest, and save
time. Startup follows no links, rehashes payloads, discards malformed entries,
and selects one verified copy per document.

Downloads are account-bound, cancellable, and capped at 64 MiB. Payload and
manifest are flushed in staging before an atomic directory rename publishes the
copy. A failed update leaves the committed copy intact. The app defines no
aggregate offline quota. Camera, picker/share, queue, PDF composition, export,
and offline writers reserve 512 MiB of free space before publication.

Temporary document exports live under protected application support, are capped
at 64 MiB, and are removed on failure, cancellation, sign-out, startup, or after
24 hours. Native document channels accept only regular non-linked files at the
expected depth beneath export or committed offline roots. Android shares
read-only FileProvider URIs; iOS uses Quick Look and the share sheet. Recipient
apps may keep their own copies.

**Privacy & storage** reports account, quarantined, device-wide offline, queue,
and free-space totals. Offline cleanup requires confirmation. Queue items remain
individually managed in Scan. The pairing screen exposes confirmed offline-copy
cleanup when no account can open More.

## Privacy, platform, and public links

Sensitive previews, text, offline retention, and local handoff require explicit
reveal or confirmation. Thumbnails are memory-bounded. Extracted text, email
HTML, and sensitive previews do not enter persistent caches.

When inactive, Flutter removes live content from pointer and semantics trees and
adds a blurred tinted privacy surface. iOS adds a native material cover before
the app-switcher snapshot. Android 12+ blurs the window and tints Recents.
Android 8–11 uses `FLAG_SECURE`, which also disables screenshots and recording,
because the system may snapshot before pause callbacks.

The Runner and Share Extension embed `PrivacyInfo.xcprivacy`. Both declare disk
capacity checks for the free-space reserve; Runner also declares app-container
timestamp access. Android disclosures cover Google Play services ML Kit
diagnostics, usage analytics, identifiers, and pairing auto-zoom data. Suchi
operates no ads, crash-reporting service, or document relay.

About displays the installed version, application license, dependency notices,
bundled font licenses, and one fixed external URL: `https://suchi.page/`. It
does not embed repository, privacy, security, support, or email destinations.
**Privacy & storage** owns the in-app privacy explanation.

## Verification

- `make check` runs formatting, static analysis, and Flutter tests.
- `make api-check SERVER_ROOT=/path/to/suchi` verifies mirrored fixtures against
  the exact server revision in `tool/toolchain.json`.
- `make android` and `make ios` validate native integration builds.
- Tests live beside their feature under `test/`; native adapter tests cover path,
  link, depth, size, and manifest validation.
- Simulator and mock tests do not establish physical scanner, camera, picker,
  share, lifecycle, or signed-distribution behavior. Those gates require the
  device evidence listed in [RELEASE.md](RELEASE.md).
