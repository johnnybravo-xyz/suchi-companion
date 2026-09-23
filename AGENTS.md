# Working on Suchi mobile

This Flutter app is an unreleased companion. Keep mobile changes in this
repository and verify them against the exact server revision recorded in
`tool/toolchain.json`. Do not
publish, sign, or change store metadata as part of ordinary implementation.

## Start here

- Check `git status --short` and `git worktree list`; preserve existing work.
- Read `README.md`, `DEVELOPMENT.md`, and `ARCHITECTURE.md` for the current
  implementation. Local design proposals may describe future work.
- `lib/` groups code by feature. Extend the owning screen or controller;
  shared widgets stay in `lib/widgets/`, wire contracts in `lib/api/`.
- Android adapters live in `android/app/src/main/kotlin/app/suchi/page/`;
  iOS adapters in `ios/Runner/`, with share staging in `ios/Shared/`.
- The server's `docs/api.mdx` and contract fixtures are authoritative. Update
  `tool/toolchain.json` only to an exact server commit that was verified.

## Invariants

- Verify the origin before credentials; reject redirects. Credentials belong
  in device secure storage and must never enter external URLs or logs.
- Bind asynchronous reads, native capture, shared batches and queued uploads
  to their original account. Ignore results after an identity transition.
- Preserve failed queue files until the user resolves them. Never upload a
  foreign account's files implicitly or hide failures as successful uploads.
- Sensitive documents require explicit reveal. Keep previews out of persistent
  caches; protect temporary export files and clean them at identity changes.
- Android scanning uses server OCR when device recognition cannot supply a
  trustworthy confidence. Never synthesize OCR confidence.
- Use existing Flutter composition and explicit state. Avoid repositories,
  service locators, generic caches or another navigation framework.

## Verification and handoff

- `make check` runs format checks, analysis and Flutter tests.
- `make api-check SERVER_ROOT=/path/to/suchi` compares mirrored fixtures.
- Run focused widget/API tests first. Cover user-visible success, refusal,
  error/retry, large text and stale-account behavior.
- Native changes require the relevant Android/iOS build and adapter tests.
  Mock and simulator tests do not establish physical camera/share behavior.
- Update feature docs and `CHANGELOG.md` with behavior; update architecture
  when ownership, storage, native channels or account boundaries change.
- Commit only when asked, in small reviewable chunks with a brief subject,
  few bullets and no contribution trailers. Report unavailable device/build
  checks without claiming release readiness.
