<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Suchi Companion store declarations (English, United States)

Use this source-backed worksheet for the `0.1.0+1` artifacts. Recheck the stores' current wording and the final generated binaries on submission day; console completion is separate evidence.

## Artifact identity and business model

- iOS bundle: `page.suchi.companion`; Share Extension: `page.suchi.companion.ShareExtension`; App Group: `group.page.suchi.companion`; minimum iOS 26.0.
- Android package: `page.suchi.companion`; minimum API 35; target API 36.
- Free app. No advertising, in-app purchases, subscriptions, paid account creation or digital-goods sales.
- Phone-focused. iOS is iPhone-only; Android is resizable without a tablet-specific claim.
- Requires a user-selected, self-hosted Suchi server. The publisher does not provide or relay document hosting.

## Apple declarations

### App Privacy

- Tracking: **No**. The privacy manifests declare no tracking or tracking domains. The app does not request App Tracking Transparency permission.
- Data collected by the publisher: **None**. Documents, account metadata, scoped pairing credentials and edits travel only between the device and the server selected by the user; they are not sent to a Suchi-operated service.
- Device storage: scoped credentials use platform secure storage. Queue payloads, receipts, database state and optional offline copies stay in protected, backup-excluded app storage.
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

Suchi operates no advertising, crash-reporting, hosted analytics or document-relay service. App documents, edits, scoped credentials and optional offline files move only between the device, protected device storage and the server selected by the user.

Android document and pairing QR scanning use Google Play services ML Kit. Disclose the data Google documents for those SDK features:

- device and app information and identifiers;
- performance and configuration metrics;
- feature event and error data used for diagnostics and usage analytics; and
- for pairing QR auto-zoom, a generated scanning-session ID, zoom changes and predicted barcode bounding-box coordinates.

Google states that pairing QR image processing occurs on-device and that it does not store the image or scan result. Keep the store form aligned with Google's current ML Kit Android data-disclosure and Google code-scanner guidance; do not represent the SDK traffic as Suchi-operated analytics.

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
