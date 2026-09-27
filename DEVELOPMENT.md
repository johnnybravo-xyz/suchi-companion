# Suchi Companion development

## Pinned tools

Versions are recorded in `tool/toolchain.json`. Dart ships with Flutter; do not install or upgrade it separately.

```sh
brew install --cask flutter android-commandlinetools
brew install openjdk@17
flutter --disable-analytics
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools
flutter config --jdk-dir /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

Use these environment variables for Android commands:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
export PATH="/opt/homebrew/opt/openjdk@17/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
```

Install the pinned Android packages:

```sh
sdkmanager --licenses
sdkmanager \
  'platform-tools' \
  'emulator' \
  'platforms;android-36' \
  'build-tools;36.0.0' \
  'cmake;3.22.1' \
  'ndk;28.2.13676358' \
  'system-images;android-26;google_apis;arm64-v8a' \
  'system-images;android-36;google_apis_playstore;arm64-v8a'
```

The tested Flutter 3.47.2 build stays on API 36/AGP 9.1.0 even when a newer platform is installed; AGP 9.1.0 is validated only through API 36.1. `flutter_secure_storage` stays on 10.3.1, the newest compatible security line, because 11.0.0 raises its compile SDK to 37. Native share adapters remain in-repository.

Dependency reviews follow Suchi's `../suchi/hack/pin-bumper.sh`: previous stable
release (N−1), no downgrades, and compatible parent constraints. Flutter and Dart
move together. The installed Flutter SDK's
`packages/flutter_tools/lib/src/android/gradle_utils.dart` still records Gradle
9.3.1 and AGP 9.1.0 as its tested/full-Kotlin-support boundary; do not independently
advance this pair to upstream AGP 9.3/Gradle 9.7 without validating Flutter's build
integration. SDK-selected test packages and dependency-constrained analyzer,
archive, and CLI utility versions stay with their owners; do not add overrides
just to raise transitive version numbers.

Install full Xcode 26.6 or later from the App Store, select it with
`xcode-select`, run first-launch setup, and install iOS runtimes. Command Line
Tools alone cannot build the iOS target. The iOS deployment floor is explicitly
16.0 for the iPhone app, share extension and native tests; do not silently
inherit a higher Xcode-recommended target. Xcode 27.0/iOS 26.5 simulator was
exercised, but does not establish iOS 16 or physical-device behavior.

## Verify the host

```sh
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter emulators
flutter devices
java -version
adb version
sdkmanager --list_installed
xcodebuild -version
xcode-select --print-path
xcrun simctl list runtimes
swift --version
```

A simulator build is a smoke test. Scanner, share-extension, signing, and release gates require the physical-device matrix described by the local implementation plan.

## Project checks

Run `make deps` for the locked dependencies, then `make check`. Use
`make api-check SERVER_ROOT=/path/to/suchi-checkout` against the exact server
revision recorded in `tool/toolchain.json`. The check compares the selected
checkout's wire fixtures with the companion's mirrored copies. `make icons`
regenerates the committed Android and iPhone icon sets from the canonical SVG
sources on macOS; `make check` rejects stale dimensions, alpha-bearing iOS
outputs, divergent monochrome geometry and iPad-only catalog slots.
`make android` and `make ios` build debug Android and unsigned iOS Simulator
artifacts; neither publishes the app. `make` lists these targets.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing feature boundaries and
[AGENTS.md](AGENTS.md) for the repository's implementation and verification
rules. The companion remains pre-release and pins an exact compatible server
revision.

```sh
flutter pub get
dart run tool/sync_api_fixtures.dart --check --server-root ../suchi
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

Large-text behavior is covered by each feature's widget tests.

## First release candidate: `1.0.0+1`

The iOS distribution is iPhone-only. Android remains resizable and installable
on supported large-screen devices, but the first release is phone-focused and
does not claim a tablet-specific interface.

This is an **unpublished**, free build. Do not sign, upload, or change store
metadata as part of ordinary development. The Flutter debug APK and unsigned
iOS Simulator build are diagnostic artifacts, not store packages. An unsigned
iOS Simulator app lacks the Keychain application identity: Security framework
returns `-34018` and the app correctly refuses to read credentials. Do not
disable secure storage to make that artifact appear paired; provision the app
and extension properly for an actual signed-device check.

Run `make api-check SERVER_ROOT=../suchi` against the pinned server commit,
exercise handshake, pairing, upload and search with disposable accounts, then
`make check`. Focused Dart checks include `test/auth`, `test/share`, `test/scan`,
`test/shell` and `test/search`; native adapters need `RunnerTests` on iOS and
connected Android instrumentation tests. Capture a fresh debug and a signed
release-like build separately. A locally installed iOS Release-configuration app
can still use an Apple Development profile; it is not an App Store distribution
signature. A disposable Android release-mode emulator key is not a backed-up
Play upload key or evidence of store readiness. Only debug permits
private-LAN/localhost HTTP; release must refuse it before any saved token is
used. Check merged packaged manifests rather than inferring permissions or ATS
from source files.

Verify the app-switcher snapshot on a physical iPhone and on Android both below
and above API 31. Android 8–11 keeps `FLAG_SECURE` while the activity is open:
Recents gets a blank system card, and screenshots/screen recording are unavailable
there. Android 12+ and iOS use blurred live content, not a persisted last-screen
image. A signed build alone does not prove the switcher transition.

The owner must supply and verify these gates **before** claiming store readiness:

- Verify the paid Apple team can register the new
  `page.suchi.companion` Runner and `page.suchi.companion.ShareExtension`
  bundle IDs and attach `group.page.suchi.companion` to both. Provision both
  targets and exercise a physically signed iOS 16+ build. A Personal Team
  cannot provision Suchi Personal's unchanged CloudKit capability; resolve
  paid-team access rather than changing Personal's identity or entitlements.
  Test document scanner, Files/iCloud, Photos, cold/warm share extension,
  large batches, account switching and locked-device/background recovery.
  An unsigned simulator cannot prove them.
- Build a newly signed Android App Bundle with the intended upload key, inspect
  target API 36, merged permissions, 64-bit libraries, 16 KiB ELF/ZIP alignment
  and bundle-delivered APKs on a 16 KiB emulator. Existing generated release
  packages predating the HTTPS manifest change are stale; never submit them.
  Test native camera, file/photo picker fallback and OS shares across API 26–36.
- Provide a stable HTTPS reviewer server and a non-expiring disposable reviewer
  account with sample documents and the needed scopes. Give reviewer pairing,
  Files/Photos, search and sign-out instructions privately in the App Store and
  Play Console; never commit credentials or use a private real archive.
- Designate monitored privacy, support and **mobile-specific security** routes,
  approve the website's `/privacy/` disclosure and deploy it so the public
  HTTPS URL serves that page rather than the old landing fallback. The paired
  self-hosted server's operator controls its own logs, integrations, deletion,
  Trash and backups. The mobile client keeps device-bound tokens, per-account
  saved searches and protected queue payloads; temporary export copies may
  leave the app at a user's explicit share action. Verify platform SDK and
  processor disclosures rather than selecting “no data collected” by default.
- In the store consoles, approve App Store privacy labels and EULA, Play Data
  safety, advertising/target-audience/content-rating answers and reviewer
  access. Do not link download badges until actual approved URLs exist. If a
  new personal Play developer account needs production access, complete its
  closed-test requirement with the owner.
- Audit artwork/trademark rights and dependency notices; obtain
  owner/license-counsel approval for AGPL-3.0 corresponding-source delivery and
  Apple's standard-versus-custom EULA before any distribution. Select a public
  mobile source location and keep its corresponding source available with
  released binaries. The current private Forgejo remote is not that location.

Document the signed physical-device matrix, reviewer credentials exchange and
store decisions outside this repository's public source; no simulator or local
mock makes those gates pass.
