# Suchi Companion architecture

Suchi Companion captures documents and reads a user-owned server archive. Flutter
owns the shared Android/iOS interface; native adapters handle scanning, device
storage protection and platform sharing. The app has no document relay,
analytics or remote crash-reporting service. The companion is still pre-release
and pins one exact compatible server revision.

The unpublished Companion now uses `page.suchi.companion` on Android and iOS;
its iOS Runner and Share Extension share `group.page.suchi.companion`.
This is a fresh install without migration from the old development identity.
All five Flutter/native channels use `page.suchi.companion/` with the
`pairing`, `documents`, `scan`, `share` and `storage` suffixes.

## Ownership

| Concern | Entry point |
| --- | --- |
| Startup, disposal and dependency wiring | `lib/main.dart`, `lib/app/app_services.dart` |
| Navigation and archive refresh | `lib/shell/shell.dart` |
| Origin verification and credential lifetime | `lib/auth/session_controller.dart`, `server_origin.dart`, `credential_vault.dart` |
| QR and pasted pairing links | `lib/auth/pairing_link.dart`, `pair_screen.dart`; Android/iOS `PairingChannel` adapters |
| HTTP requests, bounds and wire validation | `lib/api/suchi_client.dart`, `api_models.dart`, `api_error.dart` |
| Capture and durable queue | `lib/scan/scan_capture_controller.dart`, `scan_queue_store.dart`, `upload_coordinator.dart` |
| Native share and explicit Files/Photos intake | `lib/share/`, `ScanQueueScreen`, Android `ShareChannel`, iOS `ShareChannel`/Share Extension and `ios/Shared/` |
| Archive browsing, filing and retrieval | `lib/documents/`, `lib/inbox/`, `lib/search/`, `lib/detail/` |
| Server-backed Saved Views | `lib/search/saved_views.dart`, `lib/api/api_models.dart`, owned by the shell |
| Account-scoped offline documents | `lib/offline/offline_document_store.dart`, Documents/detail surfaces, native document channels |
| Common presentation | `lib/widgets/suchi_widgets.dart`, `lib/theme/suchi_theme.dart` |

Screens keep their own loading, pagination and error state. The shell owns the
small refresh revision used after a document changes. Detail reports successful
edits, filing, Trash and Undo through an explicit callback; Trash restoration
uses the same refresh path. Returning from viewing a document does not advance
the revision, so the existing Documents and Inbox state retains scroll position,
loaded pages, category and sort. Refresh callbacks ignore a changed session
client or a disposed shell. There is no general client cache or second
state-management framework.

`AppSettingsController` stores device-wide appearance, document view and capture
preferences in the existing Drift settings table, independently of archive identity. The root
observes the saved theme without replacing its navigator. `SuchiColors` is the
shared light/dark ThemeExtension; motion helpers respect reduced-motion settings.
More owns its settings sheets and removes account-bearing sheets on identity
transitions.
Documents and Inbox keep stable screen keys and receive an explicit refresh
revision. View changes rebuild rows in place, without invalidating loaded pages.

The shell owns the account-bound `SavedViewController`, which lists, creates and
deletes Views through `/api/saved_views/`; no View copy is persisted on-device.
The controller keeps the last successful server list across transient failures
and discards late reads or mutations after an identity transition. Opening a
View sends a revisioned request from Search to the existing Documents screen.
Documents applies the complete typed filter and its ordering as one scope;
choosing a JD category clears that scope. Unknown or malformed future filters
remain visible and fail closed before any document request.

`lib/trash/trash_screen.dart` uses the existing paginated document list and
restore API. More opens it through the shell, and successful restoration bumps
the archive refresh revision. Retention and restore permission remain server
decisions. The screen clears its rows on an account transition and ignores
late reads or restore results from the previous identity.

The detail screen opens `document_edit_screen.dart` for title, language and
existing-tag changes; Details owns sensitivity changes and conceals sensitive
previews immediately. The editor loads the server tag catalog by bounded pages
and submits staged tag IDs through `/api/documents/bulk_edit`, checking the
per-document result even on HTTP 200. Tag creation is not an editor operation.
Successful edits reload authoritative detail; after a partial failure the editor
reconciles server state before retrying, without replaying completed writes.
Reads and writes stop after an account transition. Documents sorting resets
pagination and invalidates older page responses while retaining the selected
filing category.

## Account and network boundary

Pairing checks `/api/handshake` without credentials, then verifies a scoped
token with `/api/whoami`. The client requires the Suchi product and accepts an
explicit `mobile_contracts` list only when it contains `suchi-companion-v1`.
An absent declaration proceeds to the existing token scope/system checks;
an explicit incompatible list does not send credentials. Server and app release
numbers do not gate compatibility. The client accepts only supported origins
and refuses redirects. Password exchange obtains a mobile token; the app stores
the token in platform secure storage, never a password or a browser credential.

After a successful `/api/whoami`, secure storage also records the bounded,
validated `UserSelf` snapshot needed to identify offline data. Restoration may
enter `SessionState.offline` only when that snapshot has both mobile scopes and
the anonymous handshake or authenticated whoami fails with network/timeout.
Authentication rejection, redirects, malformed responses, invalid origins and
legacy credentials without a snapshot never unlock offline data. **Retry**
repeats the anonymous handshake before constructing a token-bearing client.

`AppServices` owns one production `NetworkMonitor` shared by uploads and
Documents. Known loss of connectivity, or a Documents network/timeout failure,
selects the account's Offline collection. Connectivity returning does not
implicitly switch back. A restored offline session builds a local-only shell
with Documents, Scan and More, without a `SuchiClient` or category store; Inbox,
Search and Trash remain unavailable. Scan uses the existing native capture,
protected queue and original account snapshot, not an unauthenticated upload
path. Network recovery alone never starts uploads: **Retry** repeats the
anonymous handshake and whoami first, then a same-account queue may resume and
the full navigation returns. Sign-out cancels account-bound work and removes
that account's offline directories before secure credential deletion. Any
protected cleanup failure restores the prior signed-in/offline state instead
of reporting a successful sign-out.

`ServerOrigin` permits localhost/private-LAN HTTP only in debug builds. Profile
and release pairing, manual entry and stored-credential restoration require
HTTPS before any token-bearing request. The first unauthenticated handshake
precedes credential exchange; redirect responses are refused.

The `page.suchi.companion/pairing` method channel's `scan` operation returns a QR
string or null on cancellation. Android uses the Google Play services code
scanner; iOS uses AVFoundation. Neither adapter opens URLs or handles account
credentials. The channel also exposes `deviceName` without opening the scanner:
Android reads `Settings.Global.DEVICE_NAME` with `Build.MODEL` fallback;
iOS uses `UIDevice.current.name`. iOS 16+ may return a generic name without
Apple's user-assigned-device-name entitlement; no entitlement is added.
Name discovery is bounded to two seconds, ignores results after a session
transition, and falls back to an editable platform label. The confirmation form
owns the transient name and validates it before connecting. No hardware IDs or
device-name cache are introduced. Camera denial or an unavailable scanner leaves Paste pairing link
and manual pairing available. Clipboard reads occur only after the user chooses
Paste pairing link, and text entry remains available if clipboard access fails.

`PairingLink.parse` accepts only the version-1
`suchi://pair?v=1&server=<encoded-origin>&code=<one-time-code>` contract. It
rejects unexpected or repeated parameters, nonempty paths, userinfo, ports and
fragments in the outer URL, and applies the ordinary server-origin policy.
The user confirms the normalized server address before any pairing request.
`SessionController.pairWithLink` then performs the unauthenticated handshake,
posts the code to `/api/mobile/pairing/exchange`, verifies the returned token
with whoami and saves it in secure storage. Codes are never persisted or sent
in HTTP request URLs. The server enforces their five-minute, single-use lifetime.
Late scan, device-name lookup or token-exchange responses cannot replace a
changed session. Link pairing always probes the selected origin, then sends the
current exchange shape with both `code` and `device_name`. The server saves the confirmed name on the paired token,
which the web account settings already render. The name is sent only to the
confirmed server and is not saved with credentials.

An account identity includes the normalized origin, server user ID, and bound
filing-system ID. Capture and share import snapshot it before staging. Uploads cannot adopt a different
account during a retry. Unassigned captures require explicit assignment;
foreign-account queue entries remain durable but hidden from the current user.
Session transitions pause uploads and invalidate retained memory state. API
authorization still happens on every request at the server.

The queue database and recovery manifest use only the current unreleased format.
There is no schema migration path. Opening an older format fails with an explicit
reset/reinstall message and leaves queue files untouched.
The queue directory is protected and excluded from backup before its database is
opened. SQLite state and sidecars therefore stay under the same boundary as
payloads, OCR text and recovery manifests instead of the default Documents
directory. Startup checks that former Documents location before opening the new
database; finding an older database stops recovery without changing either
location.

## Capture and processing

The dock starts capture in the saved mode on tap; long press anchors a
Scanner/Photo picker immediately above it. Selection persists the preference
before capture, with stale-session and unresolved-capture guards in the shell.
More changes the same preference through its existing settings bottom sheet,
without capture. The activity strip's View action still opens only the queue.
`AppSettingsController` persists `capture_mode` as a device preference.
The capture channel accepts `mode: scanner|photo` (missing means scanner).
iOS Photo uses the native still-camera picker without editing. Android Photo
uses a camera intent with one full-size output URI through a separate,
non-exported `PhotoCaptureProvider`, scoped to `suchi-photo-capture/`.
Its temporary read/write grants are revoked on return. Successful captures are
copied into the existing native capture store before temporary output is removed;
restored activity results have no account assignment until explicitly resolved.
Neither mode writes to the user's photo library. The existing pipeline wraps
photo pages as PDFs and owns account binding, OCR, receipts, recovery and uploads.

Native scanning first writes protected local files. Dart validates and stages
them in the SQLite-backed queue before acknowledging native handoff. Android
uses the platform scanner and server OCR fallback; iOS can attach validated
Vision text. The Server OCR only setting omits device-recognized text from
new upload attempts.

The native scanner is also the image-quality boundary. Android uses ML Kit's
full scanner mode for automatic capture and edge detection, perspective and
rotation correction, filters, lighting cleanup and document cleaning. iOS uses
VisionKit's document camera and retains its reviewed page images. Dart does not
crop or enhance those results again; it only combines returned pages when a
native PDF is absent. "Flattening" here means correcting the perspective of a
planar or mildly wrinkled sheet. Strong book-spine curvature and pixels hidden
by severe glare require a reviewed retake and are not reconstructed.

Camera receipt IDs hash the resolved capture directory, so native paths and
restart recovery agree across Apple system-directory aliases. Every receipt
input must be a regular, non-symlink file in that same resolved directory;
native manifest recovery retains its root-containment checks. Receipts still
commit atomically with queue staging before native files are discarded.

Share import is single-flight and starts after the first app frame. OS share
batches use the account captured at lookup. In-app Files/Photos pickers first
allocate a UUIDv4 in Dart and persist its original account identity in the
queue database's existing `AppSettings` table; only then can the native picker
open. `page.suchi.companion/share` handles `pick` with `{source: files|photos,
batch_id: UUIDv4}`, returning the same ID after protected staging or null on
cancel. Native adapters enforce 20 items and 64 MiB per item, with no broad
photo/storage permission. On resume/restart, claimed batches stage only for
their owner, remain hidden from other accounts, and remove their claim only
after each receipt is durable and native files are discarded. Corrupt claims
fail closed; unsupported items are reported, never silently counted as filed.
Each pass exposes checking/staging phases and commits receipts before discard.
Empty follow-up checks retain meaningful attention notices; dismissal clears
presentation only. Service shutdown awaits import completion before closing
the queue.

The upload coordinator uses durable idempotency keys and polls server work to
distinguish accepted bytes from finished processing. It respects connectivity,
account binding and explicit retry. Successfully completed entries have age
and count bounds; failed uploads and processing failures stay until resolved.
The existing queue is the sole durable upload path. Background execution remains
subject to platform scheduling limits.

The shell retains one queue subscription for activity and completion transitions,
scoped to the current identity. Initial historical successes do not refresh the
archive; new filed/duplicate transitions refresh both retained lists. The strip
uses payload bytes only during transfer, then shows acceptance/processing without
a fabricated percentage. Its View action selects Scan without invoking capture.

Scan owns one account-bound split-picker route. Accepted rows use the shell's
existing document route; local-only rows never expose staging paths. Durable
split child IDs restrict selection, and `SuchiClient.splitDocuments` shares
bounded pagination/completeness validation with the upload coordinator.
Account transitions immediately conceal and remove only the owned picker.

## Reading and privacy

The server remains authoritative for document state, ACLs, filing and Trash
retention. List/detail calls avoid downloading extracted content unnecessarily.
Thumbnails remain in bounded memory and sensitive previews require a reveal
decision. When the app becomes inactive, Flutter blurs and lightly tints its
live content without storing a separate last-screen image. iOS `SceneDelegate`
adds a native material blur before the switcher snapshot. Android 12+ also
blurs the Flutter window and tints its Recents card; older Android can capture
before pause callbacks, so `MainActivity` keeps `FLAG_SECURE` set there and
Recents uses an empty system card instead. This also disables screenshots and
screen recording on Android 7–11. Native covers and blur effects are removed
on resume. Native exports use scoped requests and protected local files;
viewers and share targets receive file handles, not server credentials.

`OfflineDocumentStore` owns `suchi-offline-documents` under protected,
backup-excluded application support. Each committed `offline-<UUID>/` contains
exactly one full payload and a bounded, versioned `manifest.json` with canonical
origin, user ID, filing-system ID, complete metadata, original-blob digest,
payload name, size and save time. Downloads use the full `/download` endpoint,
are account-bound, cancellable and capped at 64 MiB. Payload and manifest are
staged and flushed before the directory rename publishes them; a failed update
leaves the previous verified copy intact. Startup follows no links, deletes
staging/malformed/unknown entries and retains only the newest valid duplicate.
Thumbnails, email HTML and extracted text are never persisted there.

`SuchiClient.downloadDocument` reports bytes written to its protected
temporary file. The store owns account-bound save progress, throttles change
notifications to whole percentages and clears it on cancellation or an identity
transition. Document detail renders progress beside its Cancel control; the
shell's existing upload activity area renders a persistent bar for Documents
swipe saves. Receipt of the final byte enters an indeterminate finishing state
until validation and the atomic commit publish the copy. Stale-account callbacks
cannot restore a cleared indicator or publish a copy.

Documents owns the only saved-copy library entry point. **Saved offline** is a
scope in the same picker as all documents and categories. Its inline,
account-scoped count toggles between saved copies and All documents when a
client is available. The offline library sorts manifest-backed rows without HTTP
and opens the local payload even when a client is available.
Swiping right on an online row exposes Make/Update; swiping left on a saved
row (including the local-only library) exposes confirmed removal without
contacting the server.
Actions collapse when tapped. Saving fetches current detail, asks
consent if classification is newly sensitive, and rejects results after an
identity change. Network/timeout detail failures may fall back only to the
matching account manifest in read-only mode; authorization and malformed
responses cannot. Detail compares `original_blob` for Update and places
fresh/stale status plus update/remove options in the preview caption. Sensitive
retention and local handoff require confirmation. More retains retry, not a
second document library.

Document detail owns a preview-first workspace. The preview card couples the
openable page with friendly type, exact byte size and saved-copy status. Its
action row places the account-scoped Save offline control left of right-aligned
Open until a copy exists; Share, Edit and Trash remain route actions.
Responsive reader/filing actions lead into an always-visible metadata card.
Its sender is the first `sender` correspondent, falling back to the first
correspondent. Missing fields render explicitly rather than being inferred.
Provenance displays added time and first source label/kind; the validated
`original_blob` stays internal to offline freshness checks and manifests.
Ordinary preview states may fade; sensitive concealment replaces
the whole animation subtree and evicts revealed bytes before the next frame. A
failed metadata refresh retains clearly labelled stale information with Retry.

The server's metadata PATCH and bulk edit transactions clear only classifier-owned
`needs-review` tags after a write. The edit screen reconciles a server-cleared
marker before retrying partial saves, rather than re-adding it as a manual tag.

`message/rfc822` previews use a separate bounded `text/html; charset=utf-8`
request. Dart authenticates that request, injects a restrictive CSP at the start
of the server-generated head, then loads the result into a credential-free
WebView with JavaScript and navigation disabled. The WebView receives no base
URL, headers or cookies and cannot fetch network resources. Email HTML remains
in memory only; Hide, account transitions, backgrounding, memory pressure and
disposal replace the page and clear WebView cache and local storage. Opening or
sharing still uses the protected native file handoff, with `message/rfc822`
saved as `.eml`.

`lib/detail/document_text_screen.dart` is an explicit, memory-only reader.
Ordinary `document()` reads and `DocumentDetail` continue to require
`include_content=0`. Only entering the reader calls `documentText()` with
`include_content=1`; it validates the document ID, content and sensitivity
without expanding the metadata model. The response shares the existing 8 MiB
JSON-byte cap. Reader pages bound text layout to 12,000 UTF-16 units while
preserving surrogate pairs. Text is rendered literally, not as HTML.

Sensitive metadata requires confirmation before fetching text. A response that
reports newly sensitive content requires confirmation before display. Account
changes, backgrounding, memory pressure and disposal clear retained reader text
and invalidate pending responses. Returning to the app never reloads it
automatically. No text cache or disk copy is added; text the user explicitly
copies belongs to the system clipboard and can outlive the reader.

`lib/detail/document_files.dart` streams one document at a time into a protected
`suchi-document-exports` directory under application support. The
`page.suchi.companion/documents` native channel opens or shares only a regular,
non-linked payload at the exact expected depth under either temporary exports
or `suchi-offline-documents`. For saved copies it also requires a committed
`offline-<UUIDv4>/document-<id>.<extension>` path, never a staging directory
or manifest. Links, nested paths and files over 64 MiB are refused. Android
exposes both roots through read-only FileProvider URI grants; iOS uses Quick
Look and its share sheet. Temporary downloads are bounded to 64 MiB; failure
or cancellation removes partials. Sign-out and cold startup clear export
copies, and later exports prune copies older than 24 hours. Another app may
retain a shared copy outside Suchi Companion's control.

More's **Explore Suchi** action opens the fixed public HTTPS
`https://suchi.page` address, never the paired origin or credentials; it
remains available when the paired server is offline. **Privacy & storage**
describes device-local behavior. A public privacy policy with a monitored
contact remains an owner-controlled store-release dependency, not a server
operator's policy; the in-app explanation does not replace it.

## Verification

`make check` covers Dart formatting, analysis and Flutter behavior tests. Tests
remain beside the relevant feature under `test/`. Mirrored JSON transcripts
and their checksum manifest are checked with `make api-check`; this compares
fixtures, so verify real server behavior separately before pinning a revision.

For pairing changes, run `flutter test test/auth test/api/api_contract_test.dart`.
These tests cover URL refusal, origin confirmation, handshake/exchange ordering,
camera and clipboard fallback, native-name fallback/editing/timeouts, current
request validation, expired codes and late results. Widget tests
exercise the production pairing screen at 200% text on both target platforms;
the separate visual fixtures do not establish real camera behavior.

For document navigation, run `flutter test test/shell/document_navigation_test.dart`.
The production shell regressions cover repeated back navigation through loaded
pages, category and sort retention, errors/retry, refused edits, successful
mutations, stale-account reads and 200% text on Android/iOS layouts.

For offline retention, run `flutter test test/offline`, plus
`test/auth/session_controller_test.dart` and
`test/auth/credential_vault_test.dart`.
These cover atomic discovery and cleanup, account isolation, cancellation, size
bounds, verified-snapshot restoration,
anonymous retry ordering, network selection, read-only detail fallback and
sensitive confirmation. Native adapter tests additionally enforce both allowed
roots, exact depth, link refusal and the 64 MiB limit.

For explicit text reads, run `flutter test test/detail test/api/api_contract_test.dart`.
The reader regressions cover metadata-only navigation, sensitivity changes,
consent, errors/retry, empty text, identity/lifecycle transitions, response
bounds, Unicode paging and 200% text on Android/iOS layouts.

`make android` and `make ios` check native integration builds. Platform-channel
tests and simulator runs validate adapters, not physical camera acquisition,
real share recipients or signed distribution. Physical-device and signed-release
evidence is tracked in `design/scanner-feasibility.json`.
