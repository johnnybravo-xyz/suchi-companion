.DEFAULT_GOAL := help
.PHONY: help deps format check api-check android ios

SERVER_ROOT ?= ../suchi

help:
	@printf '%s\n' \
	  'deps       Install the locked Flutter dependencies.' \
	  'format     Format Dart source and tests.' \
	  'check      Check formatting, analyze, and run Flutter tests.' \
	  'api-check  Compare API fixtures with SERVER_ROOT.' \
	  'android    Build an Android debug APK.' \
	  'ios        Build an unsigned iOS Simulator app.'

deps:
	flutter pub get --enforce-lockfile

format:
	dart format lib test tool

check:
	dart format --output=none --set-exit-if-changed lib test tool
	flutter analyze --fatal-infos
	flutter test

api-check:
	dart run tool/sync_api_fixtures.dart --check --server-root "$(SERVER_ROOT)"

android:
	flutter build apk --debug

ios:
	flutter build ios --simulator --no-codesign
