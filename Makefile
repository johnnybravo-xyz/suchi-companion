.DEFAULT_GOAL := help
.PHONY: help deps format check api-check android android-release-unsigned ios ios-canary

SERVER_ROOT ?= ../suchi

help:
	@printf '%s\n' \
	  'deps       Install the locked Flutter dependencies.' \
	  'format     Format Dart source and tests.' \
	  'check      Check formatting, analyze, and run Flutter tests.' \
	  'api-check  Compare API fixtures with SERVER_ROOT.' \
	  'android    Build an Android debug APK.' \
	  'android-release-unsigned Build unsigned Android release assets on Linux.' \
	  'ios        Build an unsigned iOS Simulator app with an isolated environment.' \
	  'ios-canary Prove Xcode logs exclude inherited secret values.'

deps:
	flutter pub get --enforce-lockfile

format:
	dart format lib test tool

check:
	dart format --output=none --set-exit-if-changed lib test tool
	flutter analyze --fatal-infos
	flutter test

api-check:
	python3 tool/sync_api_fixtures.py --check --server-root "$(SERVER_ROOT)"

android:
	flutter build apk --debug

android-release-unsigned:
	@test "$$(uname -s)" = Linux || { echo 'Unsigned Android release assets must be built on the Linux release host.' >&2; exit 1; }
	@grep -qx 'version: 0.3.0+3' pubspec.yaml || { echo 'pubspec.yaml must declare version 0.3.0+3.' >&2; exit 1; }
	ORG_GRADLE_PROJECT_allowUnsignedRelease=true flutter build appbundle --release --no-pub
	ORG_GRADLE_PROJECT_allowUnsignedRelease=true flutter build apk --release --no-pub
	rm -rf dist/android-unsigned
	mkdir -p dist/android-unsigned
	cp build/app/outputs/bundle/release/app-release.aab dist/android-unsigned/suchi-companion-v0.3.0-build3-android-unsigned.aab
	cp build/app/outputs/flutter-apk/app-release.apk dist/android-unsigned/suchi-companion-v0.3.0-build3-android-unsigned.apk
	cd dist/android-unsigned && sha256sum suchi-companion-v0.3.0-build3-android-unsigned.aab suchi-companion-v0.3.0-build3-android-unsigned.apk > SHA256SUMS

ios:
	python3 tool/xcode_build.py

ios-canary:
	python3 tool/xcode_build.py --canary
