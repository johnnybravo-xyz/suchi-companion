# Suchi Companion

Suchi Companion is the v0.1.0 Flutter client for a user-owned Suchi document archive. It includes
native document capture and sharing, an offline-safe upload queue, Inbox filing,
document browsing, search, and privacy-gated previews.

The Android/iOS app and share surfaces use **Suchi Companion** under the new
`page.suchi.companion` app ID; iOS Runner and Share Extension share only
`group.page.suchi.companion`. This v0.1.0 identity starts with empty local data,
not an update or migration from the old development identity. The repository
and Dart package remain `suchi-mobile` and `suchi_mobile`; `suchi://pair` stays.

The first tap on the raised centre camera button opens Scanner directly.
Later taps use your last-picked mode. Touch and hold the button for a light
haptic cue and nearby choices; release, then tap **Scanner** (clean up pages)
or **Photo** (keep the full frame) to save the mode and open the camera.
Releasing the hold alone does not start capture. Tap outside to cancel.
**More → Camera mode** changes the same device preference in a bottom sheet,
like Appearance and Document view, without opening the camera. Scanner
detects and cleans up pages; Photo keeps the
full frame as a one-page PDF without document cropping or cleanup. Both use the
same protected queue, OCR and retry flow. Queue payloads, OCR text and the SQLite
state that identifies their archive stay together in the device-protected,
backup-excluded queue directory. Unresolved captures must be retried or discarded
before starting another capture. A pre-release queue database or recovery
manifest other than version 1 is detected before recovery starts; the app leaves
the database and queue files untouched and asks for a reset or reinstall.

If Android stops while the Photo camera owns its private output, the next cold
resume validates that output before continuing. A complete JPEG moves into the
recoverable capture store; an empty or invalid file is removed. A valid photo
that cannot yet be retained stays private for a later retry.

Scanner mode opens the platform document scanner. It detects
page edges, straightens perspective, corrects rotation, improves lighting and
lets you crop, filter, retake or remove pages before saving. Review the
result and retake a page when glare or deep curvature still hides content.

The **Scan** header also offers **Files** and **Photos** imports. Files accepts
PDF, JPEG, PNG and HEIC/HEIF through the system document picker; Photos uses the
system photo picker for images. Select up to 20 items at a time; each staged
file is limited to 64 MiB and must contain bytes matching its declared type.
Selections enter the same protected upload queue as camera captures and OS
shares. Empty files are rejected by Android OS sharing and pickers and by the
iOS Files, Photos and share-extension paths. The app saves the originating
account before opening either picker: switching accounts while the picker is
open never sends its selected files to the new account. Unsupported items are
reported, and failed queue files remain available for retry or explicit
discard. The app does not request broad photo-library or storage access.

Picker ownership survives activity or process recreation. On cold start, Suchi
Companion removes a picker claim only when it is at least 24 hours old and no
protected native batch exists; retained batches keep their original owner
regardless of age. Android applies the same bound to its picker-launch marker,
so an abandoned picker cannot block later imports indefinitely.

The activity strip distinguishes checking a share, secure staging, real file-byte
transfer and server processing. **View** opens the upload queue without starting
the camera. Failures and files needing an account remain visible until resolved;
an empty background share check does not dismiss them. Uploads resume while
Suchi Companion is open and the archive is reachable; closing the app does not
guarantee progress.

Tap an accepted upload in **Scan → Uploads** to open its document. Split uploads
show their remaining child documents by title, never the superseded parent.
Retry, account assignment and discard remain separate actions.
Successful upload history and completed share/capture duplicate guards are kept
for at most 30 days and the newest 20 records of each kind. Failed uploads and
processing failures remain until you retry or discard them.

Pair from the Suchi web app's Settings: generate a mobile pairing code, then
choose **Scan QR code** in the mobile app. **Paste pairing link** also works
when the camera is unavailable; you can paste or enter the copied link.
Review the displayed server address and **Device name** before confirming.
The app fills in the platform-provided name; edit it to recognize this phone
under **Mobile app** in the web settings. iOS may return only “iPhone” or “iPad.”
Re-pair an existing connection to update its recorded name or change its filing
system. **More → Account details** shows the filing system bound to this device.
Codes expire after
five minutes and can be used once. Manual server/password or scoped API-token
pairing remains available below these actions.

Production, profile and release builds require HTTPS for every server origin,
including saved credentials restored after an update. Localhost and private
LAN HTTP work only in debug builds for self-hosted development. A release build
refuses an older saved HTTP origin before sending its token; existing queued
files remain protected. Redirects never carry mobile credentials.

Document detail can open the full file or share a copy through the device's
viewer/share sheet. Sensitive documents ask for confirmation first. Downloads
are limited to 64 MiB; use the web app for larger files. Temporary copies are
removed when signing out or on the next cold launch, and older copies are
pruned during later exports.

Choose **Save offline** in document detail, or swipe right on an online
Documents row to reveal Save/Update. Swipe left on a saved row to reveal
**Remove offline copy**, which asks for confirmation and deletes only the
device copy. Saving checks current server metadata before retaining and hashing
the exact downloaded representation in protected, backup-excluded app storage.
The response MIME type and byte count drive its filename, preview metadata and
native handoff, so an archived PDF remains a PDF even when its source was an
image. The server's original-blob digest is used only to detect a newer remote
version. **Offline copy options** offers **Update offline copy** when stale and
**Remove offline copy**. Each payload remains subject to the 64 MiB limit;
sensitive files ask before retention and again before handoff to another app.
Previews, email HTML and extracted text are never written into the offline
store.

While a file downloads, document detail shows its byte progress and Documents
keeps a persistent progress bar, including after a swipe action closes. The
display switches to **Finishing offline copy** until the protected copy is
verified; only then does it appear as saved. **Cancel** abandons an in-flight
copy without replacing a previously saved version.

Before camera, picker, share, queue, temporary export, or offline payload writes,
Suchi Companion checks the destination volume can complete the bounded write
while leaving at least 512 MiB free. A low-storage refusal keeps the original
capture/share source and any previously verified offline copy for retry instead
of turning an unresolved item into a successful import or replacing durable
data.

**More → Privacy & storage** reports the current account’s offline-copy usage,
all offline copies on the device, protected queue usage and available device
space. It can remove current-account copies or copies left by signed-out and
expired accounts, including unfinished sign-out cleanup, after confirmation.
Queued items remain managed individually in Scan and are never included in bulk
offline cleanup.

If the first Inbox load on an online cold start succeeds with no documents,
Suchi Companion opens Documents instead. A failed load stays in Inbox for
**Retry**, and choosing a tab yourself prevents the automatic switch. Documents
sorting and detail's offline-copy options use the same rounded popup style as
Scan's long-press capture menu.

In **Documents**, the current scope is the heading. Open it to choose all
documents, a category, or **Saved offline**. The saved-copy count stays at the
right edge of the count row and opens this account's offline library without a
network request. When connected, the same right-aligned control shows a back
arrow and **All documents**; offline-only browsing keeps the count disabled.
Tap a row to open its protected full file.
Swipe left there to remove a saved copy even while offline; swipe right to
save/update is available only on online rows. Swipe actions fold away after
selection, while underlying work can still be retried or cancelled.

When a previously verified credential cannot reach its server, Suchi Companion
keeps local Documents, Scan and More available. Scans enter the same protected,
account-bound upload queue, remain on this device, and resume uploading only
after connectivity returns **and** the stored credential is verified again.
Inbox, Search, Trash and other server actions remain unavailable until then.
**More → Retry** performs a new anonymous handshake before reusing the token.
Signing out first moves the account’s offline copies into protected quarantine,
then deletes its credential. Credential-deletion failure restores the copies and
keeps the session active. Once credentials are gone, sign-out succeeds; if final
file removal fails, **More → Privacy & storage** exposes those protected files
for explicit retry. The signed-out/expired pairing screen also offers confirmed
removal before re-pairing. Expired or unreachable credentials do not silently
delete offline copies or failed queue files.

Document detail opens on a large preview: tap the page or the filled **Open**
button to hand off the full file. An outlined **Save offline** button sits
beside Open until a copy exists; narrow layouts stack the controls. File type,
size and saved-copy status stay inside the preview well, with update/remove
in its options menu. **Share**, **Edit** and **Trash** remain in the top bar.
Below it, **Read text** and **File under…** actions. The always-visible
**Details** card includes filing, sender, tags, sensitivity, languages, added
date and source. Tap its **Sensitivity** row
to change classification directly; choosing a sensitive level conceals the
preview immediately. Offline details remain read-only.

Saving a title, language, filing, sensitivity or tag change removes
`needs-review` only when the server's classifier added it. A tag added by you,
a rule or an import stays until explicitly removed.

Sensitive previews still require **Reveal preview**; **Hide** removes them
immediately. If a refresh fails, the last loaded information stays labelled
with an error and Retry rather than appearing current.

Email documents render the server-produced body inline without giving the
WebView a server URL or credentials. JavaScript, links, forms, frames and remote
resources are blocked. Email HTML stays in memory only and is cleared by Hide,
account changes, memory pressure or leaving the app.

Choose **Read text** in document detail to read or select recognized
text without exporting a file. Sensitive text requires confirmation. The reader
clears when you leave or background the app; copied text can remain in the system
clipboard. Empty text can mean processing is unfinished or no readable text was
found. Long text is paged, and API responses are limited to 8 MiB including JSON;
use the original document or web app if a response exceeds that limit.

Open **More → Trash** to restore recently deleted documents. The server checks
the 30-day recovery window; restoration refreshes the archive and Inbox.

Use **Edit** in document detail to update its title or language override,
and search existing server tags to add or remove them. The editor does not
create tags; server administrators manage tag creation separately. The
Documents sort control keeps the current filing category.
Viewing a document and returning keeps your Documents or Inbox scroll position
and loaded pages, including the Documents category and sort order. Successful
edits, filing changes, Trash and restoration refresh the archive and Inbox.

Choose **More → Appearance** for System, Light or Dark. This device preference
survives sign-out; both themes retain Suchi's paper, ink and manila palette.
More groups appearance and capture preferences separately from Trash, account
details and privacy information. Compact rows show preference values inline;
larger text stacks values and keeps the menu scrollable. Explanations stay in
the detail sheets rather than repeating beneath every menu item.
The **Suchi Companion** header keeps the brand mark, with
“Capture on your phone. Keep it in your archive.” in muted text beneath the title.

**More → Document view** selects Standard (the original cards), Compact, or
Detailed for Documents and Inbox. It changes presentation without refetching or
resetting your browsing position. Detailed uses existing summary metadata;
sensitive previews remain hidden.

Saved Views are synchronized with the paired Suchi server. Save the current
query, open a View as the active Documents scope, or delete it from either
platform. The app accepts the pinned server's flat and snapshot filter shapes;
unsupported future filters stay visible but never issue a partial document
request.

**More → Explore Suchi** opens the public `https://suchi.page` site in the
browser, separate from the paired server and without credentials.
**Privacy & storage** explains device-local behavior in the app. A public
privacy policy and an owner-designated monitored privacy contact remain
separate requirements before store submission; the in-app explanation does
not replace them.
**More → About** shows the installed version and build, the intended public
source repository, complete generated dependency and bundled-font license
notices, and fixed privacy, support and mobile-security links. Those public
targets must resolve before release; an in-app link is not deployment evidence.

On Android, the document and pairing QR scanners are Google Play services ML
Kit features. Suchi operates no ads, crash-reporting or document-relay service,
but Google documents collection of device and app information, identifiers,
performance and configuration metrics, and feature event and error data for
diagnostics and usage analytics. Pairing QR auto-zoom additionally collects a
generated scanning-session ID, zoom changes and predicted barcode bounding-box
coordinates. For pairing QR scans, Google says image processing occurs on-device
and it does not store the image or result. See Google's [ML Kit Android data
disclosure](https://developers.google.com/ml-kit/android-data-disclosure) and
[Google code scanner
guide](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner).

The compatible server tag, exact revision, API version, and contract are recorded
in [`tool/toolchain.json`](tool/toolchain.json). The mirrored response fixtures
in `test/fixtures/api/v1` keep the two implementations on the same wire contract.

The first release target and every mandatory release gate are maintained in
[RELEASE.md](RELEASE.md). That runbook covers signed physical-device checks,
public policies and contacts, the reviewer server, store declarations,
corresponding source, licensing approval, and coordinated publication. This
README describes shipped behavior; it is not a store-readiness checklist.

For server vulnerabilities, use the private GitHub Security Advisory form named
in the [server security policy](https://github.com/johnnybravo-xyz/suchi/blob/main/SECURITY.md);
public issues must not carry
tokens or document data. That server route is **not** a designated monitored
mobile-security contact. The owner must name one before releasing the
companion; do not send mobile reports to a guessed address.

See [DEVELOPMENT.md](DEVELOPMENT.md) for pinned tools and project checks.
