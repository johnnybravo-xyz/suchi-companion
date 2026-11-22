# Suchi Companion development

## Pinned tools

Versions are recorded in `tool/toolchain.json`. Dart ships with Flutter; do not install or upgrade it separately. Use the pinned Flutter archive rather than the moving Homebrew cask for release work.

```sh
brew install --cask android-commandlinetools
brew install openjdk@17
curl -fLO https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.9-stable.zip
echo '6545b85938745dc5070e9faf2adf70233c1811009d87fe6d27bfcda5a04b7698  flutter_macos_arm64_3.47.9-stable.zip' | shasum -a 256 -c -
unzip flutter_macos_arm64_3.47.9-stable.zip
export FLUTTER_ROOT="$PWD/flutter"
export PATH="$FLUTTER_ROOT/bin:$PATH"
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
  'platforms;android-35' \
  'platforms;android-36' \
  'build-tools;36.0.0' \
  'cmake;3.22.1' \
  'ndk;28.2.13676358' \
  'system-images;android-35;google_apis;arm64-v8a' \
  'system-images;android-36;google_apis_playstore;arm64-v8a'
```

Suchi builds with API 31 as its minimum and compile/target API 36 with AGP
9.1.0 and Gradle 9.3.1 even when a newer Android platform is installed.
`flutter_secure_storage` stays on 10.3.1 for this release; move to 11.x only
after physical v0.2.0-to-current credential upgrade tests. Native share adapters
remain in-repository.

Dependency reviews follow Suchi's `../suchi/hack/pin-bumper.sh`: previous stable
release (N−1), no downgrades, and compatible parent constraints. Flutter and Dart
move together. The installed Flutter SDK's
`packages/flutter_tools/lib/src/android/gradle_utils.dart` records Gradle 9.3.1,
AGP 9.1.0 and Kotlin 2.4.0 as this Flutter release's template versions. Do not
advance that set independently of Flutter without validating its build integration.
SDK-selected test packages and dependency-constrained analyzer,
archive, and CLI utility versions stay with their owners; do not add overrides
just to raise transitive version numbers.

Install full Xcode 27.2 from the App Store, select it with `xcode-select`, run
first-launch setup, and install the recorded simulator runtimes. Command Line
Tools alone cannot build the iOS target. The deployment floor is explicitly
iOS 26.0 for the universal iPhone/iPad app, share extension and native tests.
Xcode 27.2 with the installed iOS 26.5 and iOS 27.0 simulator runtimes is the
supported local test range. CI rejects Xcode older than 27.1. The display-region
bridge compiles with Xcode 27.1+ and reports reserved layout regions and the
system vertical-bar edge on iOS 27.1+; older runtimes deliberately return an
empty environment. Verify those signals on an iOS 27.1+ Duo runtime or device
before release.

## Debian Android release host

`devlab` is Debian 13 x86-64 and builds only unsigned Android release assets.
Install the pinned SDKs there; do not copy signing material to it:

```sh
sudo apt-get update
sudo apt-get install -y curl git openjdk-17-jdk unzip xz-utils

mkdir -p "$HOME/.local"
cd "$HOME/.local"
curl -fLO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz
echo '25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a  flutter_linux_3.47.9-stable.tar.xz' | sha256sum -c -
tar -xf flutter_linux_3.47.9-stable.tar.xz

export ANDROID_SDK_ROOT="$HOME/.local/android-sdk"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
echo '4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583  commandlinetools-linux-15859902_latest.zip' | sha256sum -c -
unzip commandlinetools-linux-15859902_latest.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$HOME/.local/flutter/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
flutter --disable-analytics
flutter config --android-sdk "$ANDROID_SDK_ROOT"
yes | sdkmanager --licenses
sdkmanager \
  'platform-tools' \
  'platforms;android-36' \
  'build-tools;36.0.0' \
  'cmake;3.22.1' \
  'ndk;28.2.13676358'
flutter precache --android
```

Before a release build, verify `flutter --version`, `java -version`, and
`sdkmanager --list_installed` against `tool/toolchain.json`. The exact build
commands live in `RELEASE.md`; run them from a clean detached release tag only
after its compatible Suchi server release is published.

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
checkout's wire fixtures with the companion's mirrored copies. `make check`
checks formatting, analyzer diagnostics and Flutter tests. `make android` and
`make ios` build debug Android and unsigned iOS Simulator artifacts; neither
publishes the app. `make` lists these targets.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing feature boundaries and
[AGENTS.md](AGENTS.md) for the repository's implementation and verification
rules. Each release candidate pins an exact compatible server revision.

```sh
flutter pub get
python3 tool/sync_api_fixtures.py --check --server-root ../suchi
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

Large-text behavior and compact-to-wide resizing are covered by feature widget
tests. iPad simulator checks cover the universal target and adaptive shell;
simulators do not replace the Duo and physical-device gates in `RELEASE.md`.

## Release gates

Use [RELEASE.md](RELEASE.md) as the single maintained release runbook. It owns
the version/package contract, automated and physical-device gates, signed
artifact inspection, public services, reviewer environment, store preparation,
stop conditions, and publication order. Do not reproduce a second checklist in
development notes.
