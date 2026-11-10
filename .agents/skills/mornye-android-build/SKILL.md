---
name: mornye-android-build
description: Build and verify Mornye Android APKs on this MacBook using the pinned Flutter, Rust, Java, SDK, and NDK toolchain. Use when asked to build, rebuild, package, or verify an Android artifact for this repository.
---

# Build Mornye for Android

Work from the repository root and read `AGENTS.md` first. Preserve uncommitted changes and never run Flutter tests concurrently with the build.

## 1. Configure the toolchain

```bash
export JAVA_HOME="$HOME/.local/share/mise/installs/java/temurin-25.0.5+8.0.LTS/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/30.0.16248370"
export MORNYE_RUST_ANDROID_ABIS=arm64-v8a
```

Confirm FVM uses the version in `.fvmrc`. Do not replace it with an arbitrary system Flutter installation.

## 2. Check and commit the intended scope

Use `python3 scripts/check_local_changes.py --list AREA` to inspect focused checks
for `lastfm`, `playback`, `logging`, or `build`; run the relevant areas and review
the diff. Native changes additionally require the relevant Cargo tests and
`scripts/check_rust_backend.sh`. Historical baseline failures in `PROCESS.md` are
not automatic exemptions. Preserve unrelated work and never stage secrets or
artifacts. Commit the intended source, tests, and build changes before delivery.
Do not fabricate retrospective commits for previous APKs. Explicit user
instructions take precedence.

## 3. Deliver a local debug APK from that commit

For the personal side-by-side installation, use the guarded command below. Select
check areas relevant to the change (multiple `--check-area` flags are supported):

```bash
python3 scripts/deliver_android_debug.py --check-area build --check-area logging
```

It rejects dirty source, locks concurrent deliveries, checks pinned FVM, runs and
records selected checks, then performs config-only **after** those tests. It builds
current Rust inputs and ARM64 Lite debug APK, checks package `com.zarz.mornye.debug`,
established local debug certificate, source marker, native payload and compact ZIP
packaging. It preserves previous Downloads artifacts and writes a JSON manifest
with source commit/tree, actual command results, APK hash/size, certificate and
payload evidence. It does not claim real-device validation or a green full suite.
Do not run other tests/build commands concurrently outside this wrapper's lock.

## 4. Official/local release builds remain separate

The existing release script retains its original supported variants:

```bash
# After all tests, with the environment above:
fvm flutter build apk --config-only
bash scripts/build_android.sh --lite
shasum -a 256 build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
"$ANDROID_HOME/build-tools/37.0.0/apksigner" verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Do not use the debug delivery wrapper for an official release. Before delivering
any APK, build the exact committed source by default and report source commit,
build marker, APK path, SHA-256, size, variant and validated checks. The release
script's payload audit must pass; verify APK Signature Scheme v2. Debug signing
updates only a matching local certificate, never bypasses an official signature.

## Avoid incremental debug APK size inflation

Before distributing a debug APK, compare its total size with the sum of ZIP entry compressed sizes. Android incremental packaging can retain large unused gaps after changed native libraries or Dart kernels; this is not application payload growth. A measured case grew from 192 MB to 252 MB with unchanged entry contents.

For a fresh debug package, preserve the previous APK outside build outputs, remove only `build/app/intermediates/incremental/packageDebug`, `build/app/outputs/apk/debug`, and the generated `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`, then rerun the identical Flutter debug build command (including Dart defines). Do not clean unrelated release outputs or the Rust build cache. Verify the new signature, package/ABI and compare uncompressed ZIP entry hashes with the previous APK when no source changes were intended.
