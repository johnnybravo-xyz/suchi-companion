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

The pinned Flutter 3.47.2 build uses compile/target API 36, AGP 9.1.0 and
Gradle 9.3.1 even when a newer Android platform is installed.
`flutter_secure_storage` stays on the compatible 10.3.1 security line because
11.x requires compile SDK 37. Native share adapters remain in-repository.

Dependency reviews follow Suchi's `../suchi/hack/pin-bumper.sh`: previous stable
release (N−1), no downgrades, and compatible parent constraints. Flutter and Dart
move together. The installed Flutter SDK's
`packages/flutter_tools/lib/src/android/gradle_utils.dart` records Gradle 9.3.1,
AGP 9.1.0 and Kotlin 2.4.0 as this Flutter release's template versions. Do not
advance that set independently of Flutter without validating its build integration.
SDK-selected test packages and dependency-constrained analyzer,
archive, and CLI utility versions stay with their owners; do not add overrides
just to raise transitive version numbers.

Install full Xcode 27.0 from the App Store, select it with `xcode-select`, run
first-launch setup, and install the recorded simulator runtimes. Command Line
Tools alone cannot build the iOS target. The deployment floor is explicitly
iOS 16.0 for the iPhone app, share extension and native tests; do not silently
inherit a higher Xcode-recommended target. Xcode 27.0 with the iOS 26.5 simulator
was exercised, but that does not establish iOS 16 or physical-device behavior.

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
rules. The v0.1.0 release candidate pins an exact compatible server revision.

```sh
flutter pub get
dart run tool/sync_api_fixtures.dart --check --server-root ../suchi
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

Large-text behavior is covered by each feature's widget tests.

## Release gates

Use [RELEASE.md](RELEASE.md) as the single maintained release runbook. It owns
the version/package contract, automated and physical-device gates, signed
artifact inspection, public services, reviewer environment, store preparation,
stop conditions, and publication order. Do not reproduce a second checklist in
development notes.
