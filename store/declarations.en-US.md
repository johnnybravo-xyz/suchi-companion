<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Suchi Companion store declarations (English, United States)

Use this source-backed worksheet for the `0.1.0+1` artifacts. Recheck the stores' current wording and the final generated binaries on submission day; console completion is separate evidence.

## Artifact identity and business model

- iOS bundle: `page.suchi.companion`; Share Extension: `page.suchi.companion.ShareExtension`; App Group: `group.page.suchi.companion`; minimum iOS 26.0.
- Android package: `page.suchi.companion`; minimum API 31; target API 36.
- Free app. No advertising, in-app purchases, subscriptions, paid account creation or digital-goods sales.
- Worldwide distribution in every App Store and Google Play territory available
  to the publisher; no country-specific product or payment behavior.
- EU Digital Services Act status: **non-trader**, as confirmed for this release.
- Phone-focused. iOS is iPhone-only; Android is resizable without a tablet-specific claim.
- Requires a user-selected, self-hosted Suchi server. The publisher does not provide or relay document hosting.

## Local storage, backup, uninstall and capacity

- Scoped credentials use platform secure storage. Queue payloads, receipts,
  database state and optional offline copies use protected app-private storage.
- Android excludes the complete app data tree from cloud backup and device
  transfer. iOS applies the excluded-from-backup resource flag to queue and
  offline storage.
- Uninstall removes the app-private file container but does not contact the
  selected server or remove server-side users, tokens or documents. Android also
  removes the package's secure-storage material. An iOS Keychain credential can
  survive uninstall, so users requiring credential removal must sign out first
  or revoke the token at their server.
- Each staged, exported or offline document is limited to 64 MiB. Every bounded
  write must retain a 512 MiB free-space reserve. There is no additional
  aggregate app-defined quota; available device capacity and the reserve are the
  collection bound, and failed queue items remain until the user resolves them.

## Apple declarations

### App Privacy

- Tracking: **No**. The privacy manifests declare no tracking or tracking domains. The app does not request App Tracking Transparency permission.
- Data collected by the publisher: **None**. Keep Apple's **Data Not Collected**
  answer. Documents, account metadata, scoped pairing credentials, searches and
  edits travel only between the device and the server selected by the user; they
  are not sent to the publisher or a Suchi-operated service.
- Reviewer note: **Data Not Collected** describes the publisher boundary, not an
  offline-only app. The app connects directly to the user's chosen self-hosted
  server, whose operator controls its accounts, logs, retention and deletion.
  The publisher has no access to those servers and ships no publisher-accessible
  analytics, advertising or crash-reporting service.
- Third-party advertising or analytics SDKs: **None on iOS**.
- Required-reason APIs: file timestamps (`C617.1`) and disk space (`E174.1`) in Runner; disk space (`E174.1`) in the Share Extension.

### Export compliance

- `ITSAppUsesNonExemptEncryption` is `false` in the packaged Runner property list.
- The app uses standard platform HTTPS/TLS and platform secure storage. It does not implement or ship proprietary or non-exempt cryptography.

### Capabilities and access

- Camera: document/photo capture and pairing QR codes.
- Local network: direct connection to the server selected by the user.
- Files, Photos and Share Extension: user-initiated import into the protected queue.
- App Group: transfer of user-selected payloads and bounded manifests between Runner and Share Extension.
- No location, contacts, microphone, Bluetooth, Health, Home, advertising attribution or push-notification capability.

## Google Play declarations

### Data safety

Suchi operates no advertising, crash-reporting, hosted analytics or document-relay service. Google Play's definition of collection includes data transmitted off the device, so disclose the direct traffic to the user-selected server even though the publisher cannot access it. Use the following source-backed worksheet in the Play Console:

| Play data type | Collected | Shared | Required and purpose |
| --- | --- | --- | --- |
| Personal info: email address, user ID and other account identity; user-provided device name | Yes | No | Required for pairing, authentication and account management; app functionality |
| Photos | Yes | No | Optional, user-initiated capture/import to create a document; app functionality |
| Files and docs | Yes | No | Optional, user-initiated import/upload, viewing, export and offline retrieval; app functionality |
| App activity: in-app search history | Yes | No | Optional queries sent to the selected server; app functionality |
| App activity: other user-generated content and other actions | Yes | No | Optional titles, tags, language, filing, sensitivity, Trash/restore and Saved View actions; app functionality |
| Device or other identifiers | Yes | No | ML Kit diagnostics and usage analytics |
| App info and performance: diagnostics and other performance data | Yes | No | ML Kit device/app/configuration details, event/error data and latency metrics; diagnostics and usage analytics |

All app-to-server traffic is encrypted in transit because release builds require
HTTPS. The server-bound rows are marked not shared because they are direct,
user-initiated transfers to the server the user chose, not disclosure to the
publisher or an unrelated recipient. Recheck the Console's current definitions
and the final SDK inventory before submission.

Android document and pairing QR scanning use Google Play services ML Kit. Disclose the data Google documents for those SDK features:

- device and app information and identifiers;
- performance and configuration metrics;
- feature event and error data used for diagnostics and usage analytics; and
- for pairing QR auto-zoom, a generated scanning-session ID, zoom changes and predicted barcode bounding-box coordinates.

Google states that pairing QR image processing occurs on-device and that it does not store the image or scan result. Google also states that ML Kit encrypts its collected data in transit and does not transfer it to third parties. Keep the store form aligned with [Google Play Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en), [ML Kit's Android disclosure](https://developers.google.com/ml-kit/android-data-disclosure), and Google code-scanner guidance; do not represent the SDK traffic as Suchi-operated analytics.

### Permissions and networking

- Direct permission: `android.permission.INTERNET`.
- Dependency-added network-state permission may appear in generated APKs.
- No storage, camera, location, contacts, microphone, phone, SMS, advertising-ID or notification permission is requested by the release manifest. Scanner and picker access is mediated by platform or Play-services UI.
- Release traffic rejects cleartext HTTP. Debug-only local development is outside the store artifact.

### Content and audience

- Productivity/document-management utility; no user-generated public feed, messaging, gambling, dating, medical treatment, financial transaction, violence or mature content feature.
- General adult productivity audience; not designed for children.
- No ads and no paid content.
- Users revoke the paired token at their server or sign out in the app. Signing out removes the credential and paired account's local offline copies; More → Privacy & storage exposes retry cleanup for protected leftovers.

## Reviewer summary

Pair with a dedicated synthetic-data server account. Explain that the app has no publisher-hosted sign-up: the supplied pairing link is the scoped credential. Review capture/import, recoverable uploads, Inbox filing, Documents/search, verified offline copies, edits, Trash/restore and sign-out. Keep reviewer credentials and server coordinates out of this repository.
