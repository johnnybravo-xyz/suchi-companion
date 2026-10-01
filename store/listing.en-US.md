<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Suchi Companion store listing (English, United States)

## Shared product facts

- **Name:** Suchi Companion
- **Price:** Free
- **Primary category:** Productivity
- **Secondary category:** Utilities
- **Supported form factor:** Phones. The iOS app is iPhone-only. The Android app remains resizable but does not claim a tablet-specific interface.
- **Requirement:** A reachable, self-hosted Suchi server and a scoped pairing link are required. Suchi Companion is not a hosted document service and does not provide a server account.
- **Source:** <https://github.com/johnnybravo-xyz/suchi-companion>
- **Marketing:** <https://suchi.page/>
- **Privacy:** <https://suchi.page/privacy/>
- **Support:** <https://suchi.page/support/>
- **Security:** <https://suchi.page/security/>

## Apple subtitle

Capture to your Suchi archive

## Apple keywords

scanner,documents,archive,offline,PDF,OCR,filing,search,privacy

## Google Play short description

Capture, file, search and read documents in your Suchi archive.

## Google Play promotional assets

- **Feature graphic:** `store/google-play/en-US/feature-graphic.png` (1024 × 500, 24-bit PNG without transparency; SHA-256 `1e3d05dde63a3f92f7d789541b936cf923ab90e919119f063acd21af1c9c6ddf`)
- **Preview video master:** `store/google-play/en-US/preview-video.mp4` (1920 × 1080, 31 seconds, H.264 video with AAC audio; SHA-256 `3a974fca2c2718d86f1030525c47d91b1b3935a3e5c9c6afc57a0fa8b38007ae`)
- **Preview video URL:** <https://www.youtube.com/watch?v=Vm7Tim1-Ksc> (unlisted on `@johnnybravo-xyz`, with embedding enabled)

The feature graphic is uploaded directly to Google Play. Google Play accepts the preview video only through a direct public or unlisted YouTube URL, so the MP4 remains the source master and must not be bundled into the Android app.

## Full description

Suchi Companion connects your phone to a Suchi document archive.

Capture images with the native document scanner, keep an uncropped photo when that is the better record, or import PDFs and images from your phone. Uploads enter a protected, account-bound queue and remain recoverable when a transfer is interrupted.

Work with your archive from the phone:

- review the Inbox and file documents;
- browse categories, search and open full documents;
- edit titles, tags, language, filing and sensitivity;
- move documents to Trash or restore them;
- save selected files for verified offline access; and
- share PDFs and images into the protected upload queue.

Offline copies are optional and stored in protected, backup-excluded app storage. Each retained or staged document is limited to 64 MiB, and every write must leave 512 MiB free. There is no separate aggregate app quota; available device capacity and that reserve bound the collection. The app verifies retained bytes before use, warns before retaining or handing off sensitive files, and preserves the last verified copy if an update fails.

Pairing uses a scoped token from your own Suchi server. The app requires HTTPS outside debug-only local development. It has no advertising, in-app purchases, crash-reporting service or Suchi-operated document relay.

On Android, document and pairing QR scanning use Google Play services ML Kit. Google documents diagnostic and usage data for those features, including device and app information, identifiers, performance and configuration metrics, and feature event and error data. Pairing QR auto-zoom additionally uses a generated scanning-session ID, zoom changes and predicted barcode bounding-box coordinates. Pairing image processing occurs on the device; Google states that it does not store the image or scan result.

Suchi Companion is free software available under the repository's licensing terms. Third-party and bundled-font notices are available in the app under More → About.

## Accessibility notes

Suchi Companion supports light and dark appearance, Dynamic Type or Android font scaling, screen readers, reduced motion, keyboard focus, 48-by-48 logical-pixel touch targets, and WCAG AA text and control contrast. Sensitive content is removed from accessibility and pointer interaction while the lifecycle privacy shield is active.

## Account and data removal guidance

Suchi Companion does not create or sell an online account. Pairing adds a scoped token issued by the user's Suchi server. Signing out removes that credential and the paired account's offline copies from the device; protected leftovers remain visible for explicit cleanup if final file removal fails. Users can also remove current-account or orphaned offline copies under More → Privacy & storage.

Uninstalling removes the app's private file container but does not delete anything from the selected server. Android excludes all app data from backup and device transfer. iOS marks queued and offline files as excluded from backup, but an iOS Keychain credential may survive uninstall; sign out or revoke the token at the server before uninstalling when credential removal is required. Server operators control server-side users, tokens, retained documents, backups and deletion according to the public privacy policy and their own deployment policy.
