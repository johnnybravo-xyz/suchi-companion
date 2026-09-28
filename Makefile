.DEFAULT_GOAL := help
.PHONY: help deps icons icons-check format check api-check android ios ios-canary

SERVER_ROOT ?= ../suchi

help:
	@printf '%s\n' \
	  'deps       Install the locked Flutter dependencies.' \
	  'icons      Regenerate launcher icons from the canonical vectors.' \
	  'icons-check Validate launcher icon sources and outputs.' \
	  'format     Format Dart source and tests.' \
	  'check      Check formatting, analyze, and run Flutter tests.' \
	  'api-check  Compare API fixtures with SERVER_ROOT.' \
	  'android    Build an Android debug APK.' \
	  'ios        Build an unsigned iOS Simulator app with an isolated environment.' \
	  'ios-canary Prove Xcode logs exclude inherited secret values.'

deps:
	flutter pub get --enforce-lockfile

icons:
	python3 tool/icons.py generate

icons-check:
	python3 tool/icons.py check

format:
	dart format lib test tool

check: icons-check
	dart format --output=none --set-exit-if-changed lib test tool
	flutter analyze --fatal-infos
	flutter test

api-check:
	python3 tool/sync_api_fixtures.py --check --server-root "$(SERVER_ROOT)"

android:
	flutter build apk --debug

ios:
	python3 tool/xcode_build.py

ios-canary:
	python3 tool/xcode_build.py --canary
