# Local development and APK handoff

This describes the fork's local workflow. It does not replace the official release
scripts or authorize publishing, installing on a phone, clearing data, or pushing.

## A delivery corresponds to a source commit

1. Inspect the branch and dirty files before editing. Preserve unrelated user work;
   make a private backup before reorganizing a large existing diff. Never stage
   credentials, generated binaries, logs, or an entire unknown working tree blindly.
2. Fix a demonstrated behavior and add a regression that fails for that behavior.
   Keep source identity and failure cases in tests; an available next song must not
   silently replace a requested unavailable song.
3. Run checks relevant to the touched areas. Record commands, results, and any
   device-only gaps. A prior successful check is not evidence for later edits.
4. Review the intended diff and commit the source, tests, and necessary build
   changes. Build that exact committed state, clean by default. Do not invent
   retrospective per-APK commits when old source snapshots were never captured.
   If existing work is inseparable, label a checkpoint honestly instead of claiming
   fabricated authorship or historical boundaries.
5. After Flutter tests, regenerate normal configuration with
   `fvm flutter build apk --config-only` before the Android build. Never run Flutter
   tests and APK builds concurrently. Follow
   [the build skill](.agents/skills/mornye-android-build/SKILL.md).
6. Verify package ID, ABI, certificate, native payload, build marker, and ZIP
   overhead. Preserve previous artifacts. Hand off the APK with its source commit,
   SHA-256, size, build variant, validated checks, and untested behavior. A successful
   host build is not proof of playback or sharing on the user's phone.

Explicit user instructions override the default workflow. A clean commit is a
traceability boundary, not a claim that every environment has been tested.

## Reproducible debug delivery

After committing the intended changes, run:

```bash
python3 scripts/deliver_android_debug.py \
  --check-area lastfm --check-area playback --check-area logging --check-area build
```

The wrapper runs selected checks and records their actual commands, exit codes,
and timestamps in the artifact manifest; it does not accept an invented pass list.
Select areas based on the actual diff rather than rerunning every area for every
small change. The manifest associates the APK hash, variant, size, build marker,
and source commit with the recorded evidence. It is not evidence of device testing
or checks that were not run. Keep the APK and manifest together at handoff.

## Focused checks

`python3 scripts/check_local_changes.py --list AREA` prints reviewable commands.
`--run AREA` executes them sequentially from the repository root and stops at the
first failure. The default is listing only; it never builds or commits.

| Area | Scope |
| --- | --- |
| `lastfm` | Service response/cache behavior, settings, matching, selected-row identity, Home integration |
| `playback` | Current/next scheduling, completion/path handoff, player runtime, metadata identity, playlist controls |
| `logging` | Bounded diagnostics, redaction, UTF-8 file attachments |
| `build` | Python build-selection, payload-audit, and local-process tests (no real APK build) |

These are starting points, not an automatic completeness guarantee. Add checks for
other edited screens/providers. Native changes also require the relevant Cargo
unit tests and `bash scripts/check_rust_backend.sh`; the delivered APK must contain
that rebuilt native payload. Large cross-cutting changes warrant the full Flutter
suite. A small log-share or matching change does not require repeated unrelated
5,000-test runs once its meaningful checks pass.

## Baseline failures: evidence, not exemptions

During the November 2026 work, the broad checks reported:

- Full analysis: three missing `referenceColumns` arguments in
  `integration_test/native_cache_maintenance_test.dart` (then lines 155, 216, 302).
- A SQLite migration test failed against a fixture lacking
  `audio_metadata_scan_version` / `format` columns.
- An early Link test failure was transient on isolated rerun; it was not established
  as a permanent baseline failure.

These are historical observations, not current assertions or skip rules. When a
failure recurs, capture the exact command, current commit, test name, and error;
compare with an isolated baseline if necessary. Distinguish newly introduced
regressions from existing failures. Never turn these notes into permanent blanket
ignores, and never report the entire suite green when it was not.

## Device handoff

Use a small repeatable scenario and ask for the resulting attached log file if it
fails. For music changes, compare the same track from wave, search, and album;
check a missing-track case; verify that a new album initially schedules only the
current and next tracks. Previously queued/manual downloads can remain running.
For log sharing, verify that the receiver gets a readable `.txt` attachment.
Include the build marker so a report cannot be confused with a previous APK.

Diagnostics should retain useful stage/provider/status/correlation data while
redacting keys, cookies, signed URLs, and private paths. Never attach `.env`, API
sessions, or raw request dumps. Test fixtures may contain public song metadata,
with their retrieval provenance and limitations documented.

## Lessons retained

- APK growth can be unused incremental ZIP gaps, not larger application contents;
  compare compressed entry totals and audit payloads before changing product code.
- “No exact match” does not prove a song is absent from a provider catalog. Separate
  retrieval, identity rejection, download availability, and playback failures.
- A completed download can disappear from queue state immediately; retain the
  completion handoff and test final local/SAF paths independently of queue rows.
- Repeated emergency APKs without commits made attribution difficult. Future
  versions should be traceable from source commit through artifact to device log.
