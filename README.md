<p align="center">
  <img src="assets/brand/suchi-mark.svg" alt="Suchi Companion" width="112">
</p>

<h1 align="center">Suchi Companion</h1>

<p align="center">
  <b>Capture on your phone. Keep it in your archive.</b>
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/suchi-companion/id6817310696">App Store (iPhone)</a> ·
  <a href="https://suchi.page/#mobile-showcase">Android beta</a> ·
  <a href="https://github.com/johnnybravo-xyz/suchi">Suchi server</a> ·
  <a href="https://suchi.page/?#privacy">Privacy</a>
</p>

<p align="center">
  <img src=".github/readme/companion-screens.png" alt="Four Companion screens: Scan, the upload Queue, the Inbox of documents waiting to be filed, and Search results for warranty." width="860">
</p>

Suchi Companion is the iPhone and Android app for
[Suchi](https://github.com/johnnybravo-xyz/suchi), a self-hosted document
archive. Scan a sheet of paper or share a PDF from another app, and it goes
straight to your own Suchi server. Uploads wait in a queue until there is a
connection, and documents you choose stay readable offline.

There is no Suchi account and nothing in between: the app talks only to the
server you pair it with. You need a Suchi server reachable over HTTPS. The app
is free, with no ads and no in-app purchases.

- **iPhone:** available on the
  [App Store](https://apps.apple.com/us/app/suchi-companion/id6817310696).
- **Android:** in early-access beta before its Play Store release.
  [Sign up on suchi.page](https://suchi.page/#mobile-showcase) with the email
  address linked to your Google Play account.

## Capabilities

- Scan cleaned-up documents or retain the full camera frame as a photo PDF.
- Import PDF, JPEG, PNG and HEIC/HEIF files from system pickers and share sheets.
- Keep account-bound uploads in a protected, retryable queue.
- Browse Inbox, Documents, Saved Views, Search and Trash; edit filing metadata.
- Review pending title, filing-category, tag, and date suggestions from Inbox
  or Documents, with explicit Accept and Dismiss actions.
- Save verified files for offline use, with progress, cancellation and stale-copy
  updates.
- Preview documents, protected email HTML and extracted text with sensitivity
  gates.
- Create public Suchi links with optional expiry and password protection, or
  share the original document file.
- Use System, Light or Dark appearance and Standard, Compact or Detailed lists.

Camera, picker, share, queue, temporary export and offline writes preserve a
512 MiB free-space reserve. Individual staged or downloaded files are limited
to 64 MiB. There is no separate aggregate app quota: retained files are bounded
by available device capacity and the reserve. Queue and offline files are stored
in device-protected, backup-excluded app storage.

## Pairing

Run a compatible Suchi server over HTTPS. In the web app, open **Settings →
Mobile app**, create a one-use pairing code, then choose **Scan QR code** or
**Paste pairing link** in Companion. Review the server address and device name
before confirming.

Release builds accept HTTPS origins only. Debug builds may use localhost or
private-LAN HTTP for development. Redirects never receive mobile credentials.
The exact compatible server revision and API contract are pinned in
[`tool/toolchain.json`](tool/toolchain.json).

## Privacy and Android ML Kit disclosure

Documents, account metadata, scoped pairing credentials and edits travel only
between the device and the server selected by the user. Suchi operates no ads,
crash-reporting or document-relay service. The app does not request broad photo
library or storage access. Sensitive previews require confirmation, and
sign-out does not silently discard failed uploads or protected offline files.
See the deployed [privacy policy](https://suchi.page/privacy/) and the in-app
**More → Privacy & storage** and **More → About** surfaces.

On Android, the document and pairing QR scanners are Google Play services ML
Kit features. Google documents collection of device and app information,
identifiers, performance and configuration metrics, and feature event and
error data for diagnostics and usage analytics. Pairing QR auto-zoom
additionally collects a generated scanning-session ID, zoom changes and
predicted barcode bounding-box coordinates. For pairing QR scans, Google says
image processing occurs on-device and it does not store the image or result.
See Google's [ML Kit Android data
disclosure](https://developers.google.com/ml-kit/android-data-disclosure) and
[Google code scanner
guide](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner).

## Development

Current source line: **v0.1.0**. The app uses package ID
`page.suchi.companion`; iOS also ships
`page.suchi.companion.ShareExtension` with App Group
`group.page.suchi.companion`.

Use the pinned Flutter, Dart, Android and Xcode versions in
[`tool/toolchain.json`](tool/toolchain.json):

```sh
flutter pub get
make check
make android
make ios
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup,
[ARCHITECTURE.md](ARCHITECTURE.md) for app and native boundaries, and
[RELEASE.md](RELEASE.md) for mandatory release gates. Third-party components,
bundled fonts and their terms are recorded in [NOTICE](NOTICE) and exposed
under **More → About → Open-source licenses**. Report vulnerabilities through
the [Suchi security guidance](https://suchi.page/security/); never put tokens
or document data in public issues.

## License

Copyright (c) 2026 Ritesh Shrivastav. Suchi Companion is available under two
licenses:

- **[GNU Affero General Public License v3.0](LICENSE)** — free for everyone.
- **Commercial license** — for distributors who cannot accept the AGPL terms.
  Write to <contact@suchi.page>.
