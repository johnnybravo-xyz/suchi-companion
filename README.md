# Suchi Companion

Suchi Companion is the pre-release Flutter client for a user-owned Suchi document archive. It includes
native document capture and sharing, an offline-safe upload queue, Inbox filing,
document browsing, search, and privacy-gated previews.

The Android/iOS app and share surfaces use **Suchi Companion** under the new
`page.suchi.companion` app ID; iOS Runner and Share Extension share only
`group.page.suchi.companion`. This unpublished development-only identity starts
with empty local data, not an update or migration from the old app. The repository
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
before starting another capture. An older pre-release queue database is detected
before recovery starts; the app leaves its database and queue files untouched and
asks for a reset or reinstall.

Scanner mode opens the platform document scanner. It detects
page edges, straightens perspective, corrects rotation, improves lighting and
lets you crop, filter, retake or remove pages before saving. Review the
result and retake a page when glare or deep curvature still hides content.

The **Scan** header also offers **Files** and **Photos** imports. Files accepts
PDF, JPEG, PNG and HEIC/HEIF through the system document picker; Photos uses the
system photo picker for images. Select up to 20 items at a time; each staged
file is limited to 64 MiB. Selections enter the same protected upload queue as
camera captures and OS shares. The app saves the originating account before
opening either picker: switching accounts while the picker is open never sends
its selected files to the new account. Unsupported items are reported, and
failed queue files remain available for retry or explicit discard. The app
does not request broad photo-library or storage access.

The activity strip distinguishes checking a share, secure staging, real file-byte
transfer and server processing. **View** opens the upload queue without starting
the camera. Failures and files needing an account remain visible until resolved;
an empty background share check does not dismiss them. Uploads resume while
Suchi Companion is open and the archive is reachable; closing the app does not
guarantee progress.

Tap an accepted upload in **Scan → Uploads** to open its document. Split uploads
show their remaining child documents by title, never the superseded parent.
Retry, account assignment and discard remain separate actions.

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
device copy. Saving checks current server metadata before retaining the
verified full file in protected,
backup-excluded app storage. A saved document shows its offline status beside
the file type and size inside the preview; **Offline copy options** offers
**Update offline copy** when stale and **Remove offline copy**. Each file
remains subject to the 64 MiB limit; sensitive
files ask before retention and again before handoff to
another app. Previews, email HTML and extracted text are never written into
the offline store.

In **Documents**, the visible **Saved offline** filter shows the current
account's saved-copy count. Select it to list copies without a network request;
tap a row to open its protected full file. The category drawer does not
duplicate this destination. Swipe left here to remove a saved copy even while
offline; swipe right to save/update is available only on online rows. Swipe
actions fold away after selection, while underlying work can still be retried
or cancelled.

When a previously verified credential cannot reach its server, Suchi Companion
keeps local Documents, Scan and More available. Scans enter the same protected,
account-bound upload queue, remain on this device, and resume uploading only
after connectivity returns **and** the stored credential is verified again.
Inbox, Search, Trash and other server actions remain unavailable until then.
**More → Retry** performs a new anonymous handshake before reusing the token.
Signing out removes the account's offline copies before deleting its
credential; if protected cleanup fails, sign-out fails and the session remains
active. Failed queue files remain available for explicit resolution.

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

**More → Privacy policy** opens the public `https://suchi.page/privacy/` route
in the browser, separate from the paired server. **Privacy & storage** explains
device-local behavior in the app. The public route currently needs deployment
and an owner-designated monitored privacy contact before it can serve as a
completed store policy. No support link is presented as monitored until the
owner supplies a real channel.

The exact compatible server revision and API version are recorded in
[`tool/toolchain.json`](tool/toolchain.json). The mirrored response fixtures in
`test/fixtures/api/v1` keep the two implementations on the same wire contract.

The first release candidate is `1.0.0+1`, not a published store version. Signed
physical-device capture/share checks, public privacy/support/security contacts,
a stable HTTPS reviewer server/account, store declarations and asset rights
remain release gates. The source is AGPL-3.0; public corresponding-source
delivery and Apple store EULA compatibility need owner/license-counsel approval
before any binary distribution. The owner has not yet selected a public mobile
source location; the current Forgejo remote remains private.

For server vulnerabilities, use the private GitHub Security Advisory form named
in the [server security policy](https://github.com/johnnybravo-xyz/suchi/blob/main/SECURITY.md);
public issues must not carry
tokens or document data. That server route is **not** a designated monitored
mobile-security contact. The owner must name one before releasing the
companion; do not send mobile reports to a guessed address.

See [DEVELOPMENT.md](DEVELOPMENT.md) for pinned tools and project checks.
