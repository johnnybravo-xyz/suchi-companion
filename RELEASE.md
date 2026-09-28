# Suchi Companion release runbook

This is the single maintained checklist for building, validating, and publishing
Suchi Companion. Development setup belongs in [DEVELOPMENT.md](DEVELOPMENT.md).
The server release process belongs in the
[server release guide](https://github.com/johnnybravo-xyz/suchi/blob/main/docs/release-process.mdx).
Older local release notes are historical and are not release authority.

A release is ready only when every applicable gate below has recorded evidence.
A simulator, unsigned build, unit test, or source-file inspection does not replace
an explicitly required signed-artifact, console, reviewer-server, or physical-device
check.

## v0.1.0 contract

| Surface | Required value |
| --- | --- |
| Marketing version and source tag | `0.1.0` and signed annotated tag `v0.1.0` |
| First submitted build | `1`; increment after any submitted-code change |
| iOS app | iPhone only, iOS 26.0 minimum, bundle ID `page.suchi.companion` |
| iOS extension | `page.suchi.companion.ShareExtension` |
| Shared App Group | `group.page.suchi.companion` on both iOS targets |
| Android app | API 31 minimum, target API 36, application ID `page.suchi.companion` |
| Mobile API | `suchi-companion-v1`, API version `1` |
| Distribution | Free public app through Apple App Store and Google Play |
| Rollout | Manual, coordinated 100% release after all mandatory gates pass |

`tool/toolchain.json` is the machine-readable authority for the compatible server
tag, exact revision, API version, and pinned build tools. The exact tagged mobile
source must be public at <https://github.com/johnnybravo-xyz/suchi-companion> before
distributing its binaries.

## Release order and evidence

1. Freeze clean server and mobile `main` commits. Record the commit hashes,
   version/build, dependency locks, and toolchain metadata.
2. Complete and publish the server release first. Verify its signed tag,
   checksums, SBOM, signatures, source archive, and immutable container digest.
3. Deploy the reviewer server from that immutable server digest with synthetic
   data, a valid public certificate, and a console-only disposable account.
4. Update `tool/toolchain.json` to the released server commit and API contract;
   run the fixture compatibility check against that exact checkout.
5. Build and verify the signed mobile artifacts from the reviewed mobile commit.
6. Complete store testing and approvals. Release Apple and Google together only
   after both production releases are ready.

Keep the release evidence outside the public repository when it contains account,
device, reviewer, or console details. The evidence record must still identify the
source commits, signed tags, commands, artifact digests, devices/OS versions,
console decisions, failures, and reruns. Never commit signing material, reviewer
credentials, tokens, document data, device identifiers, or private console exports.

## Source and automated gates

Run from the mobile repository unless stated otherwise:

```sh
make deps
make api-check SERVER_ROOT=../suchi
make check
make android
make ios
make ios-canary
```

Before tagging, also require all of the following in CI or the named native tool:

- formatting, analyzer, Flutter tests, Drift validation, icon validation,
  dependency/license inventory, API fixture compatibility, and secret scans;
- Android lint/build plus native tests, with emulator or device coverage at APIs
  31 and 36;
- iOS native tests on the oldest supported iOS version and the current version;
- release archive and bundle checks described below;
- a clean source archive containing the required generated/native files and no
  secrets, debug credentials, personal data, stale identifiers, local absolute
  paths, or unrelated APKs;
- no unresolved data-loss or security defect and no failed mandatory gate.

GitHub Actions repeats the source, pinned API-fixture, Android debug
lint/build, iOS simulator build, and inherited-secret canary gates on pushes to
`main`, pull requests, and manual dispatch. Signed artifacts, emulators,
physical devices, store consoles, and external services remain separate gates
because a hosted source workflow cannot establish them.

The archived Trust Gate Go and Dart engines are not companion dependencies and
must not be copied into source or bundled into an app artifact. The companion
uses the server's existing authorization and review contracts; it does not carry
a second trust or approval engine.

Keep the scanner evidence record with the private release evidence. It must name
the mobile commit, signed-artifact SHA-256 and certificate fingerprint, server
commit and immutable image digest, device model and OS/API version, test time,
tester, each scenario and its observed result, failures, fixes and reruns. Mark
the scanner gate passed only after the signed artifact completes the physical
matrix below; source inspection, emulator results and adapter tests are supporting
evidence, not substitutes.

## Functional and physical-device gates

Exercise the release candidate against the immutable reviewer server on at least
one physical iPhone and one physical Android phone. Record device and OS versions.
Cover:

- QR and pasted-link pairing, device naming, token revocation, account switching,
  offline re-verification, and sign-out recovery;
- document scanner, Photo mode, Files/iCloud, Photos, cold and warm OS shares,
  content-provider imports, large and multi-page inputs, cancellation,
  locked-device/background recovery, retry, discard, queue recovery and account
  transitions;
- image and PDF uploads through server processing, filing, search, previews,
  full-file handoff, edits, Trash, and restoration;
- interrupted, cancelled, corrupted, oversized, type-mismatched, bounded, and
  low-storage downloads while preserving the last verified offline copy;
- the 512 MiB free-space reserve and recoverable queue behavior for every mobile
  write path;
- Dynamic Type/text scaling, screen readers, focus/keyboard behavior, contrast,
  touch targets, destructive confirmations, and the lifecycle privacy shield;
- app-switcher behavior on Android API 31 and on a newer Android release; and
- scanner latency, perspective, rotation, lighting, glare/curvature guidance,
  page review, OCR quality, repeated capture cycles, and interruption recovery.

A mock, simulator, or adapter test can supplement this matrix but cannot satisfy a
physical camera, share recipient, secure storage, signing, performance, or image
quality gate.

## Signed artifact gates

### Android App Bundle

Build a newly signed AAB with the backed-up upload key. Inspect the AAB and Play's
generated APKs, not an older local artifact. Verify:

- package `page.suchi.companion`, version `0.1.0`, current build number, minimum
  API 31, target API 36, and only intended permissions/components;
- Play App Signing and the registered upload certificate;
- arm64 libraries and 16 KiB ELF/ZIP alignment on a 16 KiB device or emulator;
- production HTTPS enforcement, release network policy, launcher icons, notices,
  ML Kit dependencies, and absence of debug/test configuration; and
- installation and the functional matrix through Play internal testing, followed
  by the required closed track and pre-launch report.

### iOS archive

Archive with the pinned Xcode version and paid distribution team. Inspect the
archive, exported IPA, entitlements, embedded privacy manifests, generated privacy
report, and signing identities. Verify:

- iPhone-only distribution; iOS 26.0 minimum; app, extension, and App Group IDs
  exactly match the contract above;
- both targets are provisioned with only required capabilities and the App Group;
- version/build, icons, permission strings, HTTPS policy, dependency notices,
  export-compliance answers, and absence of debug/test configuration;
- inherited secret canaries are absent from Xcode activity logs and build
  receipts; and
- the signed app passes the physical matrix before TestFlight external review and
  App Store submission.

## Public service and reviewer gates

Before submission, verify with unauthenticated HTTPS requests that these are the
real deployed pages, not redirects to a generic landing page or placeholder:

- <https://suchi.page/privacy/>
- <https://suchi.page/support/>
- <https://suchi.page/security/>
- <https://suchi.page/> and its `#mobile-showcase` section

Verify monitored `privacy@suchi.page`, `support@suchi.page`, and
`security@suchi.page` mailboxes end to end. The privacy policy and store answers
must match the final artifact, including device-local storage, the user's
self-hosted server and operator, deletion/retention, explicit exports, and Android
ML Kit diagnostics, usage analytics, and QR auto-zoom data documented in the
README.

The reviewer server must stay available for the full review window. Verify its
certificate, released immutable server digest, synthetic sample documents,
non-expiring disposable reviewer account, required token scopes, and private
pairing/Files/Photos/search/sign-out instructions. Never put its credentials in
source, screenshots, public issue trackers, or this runbook.

## Store preparation and publication

For both stores:

- accept current account agreements; create records without changing the fixed
  package/bundle identifiers; publish the exact corresponding source and notices;
- prepare truthful English, phone-focused metadata and screenshots captured from
  the signed release build; complete content, privacy/data, rights, encryption,
  target-audience, advertising, and reviewer-access declarations from the final
  dependency and permission inventories;
- record worldwide availability, free pricing with no ads or purchases, and the
  confirmed EU Digital Services Act non-trader status in both consoles;
- use only approved public privacy, support, security, source, and mobile URLs;
- reassess mutable store rules, account verification, and DSA trader status on
  submission day rather than relying on an old checklist; and
- retain console decisions, tester feedback, pre-launch reports, and resulting
  change records in the private release evidence.

For Apple, register the app, Share Extension, and App Group; upload to TestFlight
internal testing; obtain external TestFlight review; then submit the accepted
physical-device build for manual App Store release. Hold release until Google
production readiness.

For Google, complete developer and physical-device verification, register the
package and signing certificate, enable Play App Signing, upload the inspected
AAB, complete internal testing and the pre-launch report, then satisfy the current
production-access closed-test requirement. For the current personal-account rule,
plan for at least 12 opted-in testers continuously for 14 days, but recheck the
console policy before starting and before applying for production access. Keep the
closed track available for fixes.

## Stop and rollback rules

Stop submission or release when any mandatory gate fails, an artifact is unsigned
or does not match its source/tag, public policy or package identity is stale, the
reviewer server is inaccessible, or a data-loss/security defect remains unresolved.
After any submitted-code change, increment the build number and rerun affected
automation, signed-artifact inspection, privacy, and physical-device gates.

Release both stores manually at 100% only after both approvals are ready. Preserve
signed artifacts, source archives, checksums, SBOMs, store metadata, reviewer-server
digest, and prior releasable builds for emergency response. Stop distribution on
a critical regression; revoke reviewer credentials when review ends; keep the
closed track and rollback evidence available for a corrected build.
