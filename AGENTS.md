# Mornye agent instructions

Mornye is a Flutter app with a Rust backend. Run commands from the repository root;
use the Flutter version in `.fvmrc` through FVM and the repository Rust toolchain.

## Working agreements

- Act on the next clear, necessary step within the agreed scope without asking
  again. Ask only for material missing information or required authorization.
- In this user's sessions, the root agent delegates and monitors; subagents do
  repository and tool work. Explicit session instructions can override this rule.
- Keep behavioral/workflow preferences in agent instructions or agent memory,
  not the user's personal notes unless explicitly requested.
- Treat a concrete defect reported during active work as a request to correct it
  within that task; investigate and verify rather than waiting for another go-ahead.
- Preserve existing user changes; make a private backup before reorganizing a
  large existing diff. Inspect scope before staging; never sweep
  unrelated changes, secrets, generated binaries, or logs into a commit.
- Do not push, publish, install on a device, or clear user data without authorization.

## Changes and APK versions

- Use meaningful regressions and focused formatting, analysis, and tests for the
  changed behavior. Broad changes may require the full suite; unrelated baseline
  failures must be evidenced and reported, not silently ignored or fixed out of scope.
- Review and commit the intended source, tests, and build changes before each
  delivered APK version, then build that exact committed state, clean by default.
  This is the user's standing commit workflow; explicit instructions take precedence.
- Preserve previous artifacts and report source commit, APK hash, build marker,
  variant and actual checks. Do not invent retrospective commits for old APKs;
  label inseparable existing work as a present-day checkpoint honestly.
- Distinguish unit/mocked tests, live API checks, build audits and device validation.
  Host success does not prove phone playback, availability or file sharing.
- Never run Flutter tests and Android builds concurrently. Tests alter generated
  configuration; the build skill handles config-only after tests and ZIP-gap checks.

## Task-specific skills

- [Android build and delivery](.agents/skills/mornye-android-build/SKILL.md):
  toolchain, focused checks, baseline evidence, clean-commit APK/manifest delivery.
- [Device verification](.agents/skills/mornye-device-check/SKILL.md):
  authorized installation, playback/backup scenarios and diagnostic handoff.

Keep these instructions and skills consistent when changing the workflow.
