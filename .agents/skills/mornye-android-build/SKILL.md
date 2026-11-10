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

## 2. Stabilize generated Android files

If Flutter tests have run since the previous build, regenerate normal app configuration before building:

```bash
fvm flutter build apk --config-only
```

Do not substitute `fvm flutter pub get`; it does not reliably remove test-only plugin registrations.

## 3. Run relevant checks

Run focused tests for changed behavior and the appropriate final checks:

```bash
fvm dart format --output=none --set-exit-if-changed lib test integration_test
fvm flutter analyze
fvm flutter test test/backup_restore_picker_test.dart
bash scripts/check_rust_backend.sh
```

Replace the example focused test with those covering the actual change. Use the full `fvm flutter test` for broad final verification. Do not treat unrelated baseline failures as caused by the current change, and do not hide them.

## 4. Commit the delivery scope, build and verify

For every APK version delivered to the user, verify the intended scope and relevant checks, commit its source, tests, and build changes, and build that exact committed state. Do not deliver from a dirty build state by default. Never sweep unrelated user changes, secrets, or generated artifacts into the commit; isolate the intended scope first. Explicit user instructions take precedence. Do not fabricate retrospective commits for earlier APKs. Report the source commit, APK SHA-256, and build marker with each delivery.

```bash
bash scripts/build_android.sh --lite
shasum -a 256 build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
"$ANDROID_HOME/build-tools/37.0.0/apksigner" verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The build script must complete its Rust APK payload audit. Signature verification must report APK Signature Scheme v2 as true.

Report the absolute APK path, size, SHA-256, and whether real-device behavior was tested. Local debug signing is suitable for updating earlier local fork builds with the same key, not for replacing an official installation.

## Avoid incremental debug APK size inflation

Before distributing a debug APK, compare its total size with the sum of ZIP entry compressed sizes. Android incremental packaging can retain large unused gaps after changed native libraries or Dart kernels; this is not application payload growth. A measured case grew from 192 MB to 252 MB with unchanged entry contents.

For a fresh debug package, preserve the previous APK outside build outputs, remove only `build/app/intermediates/incremental/packageDebug`, `build/app/outputs/apk/debug`, and the generated `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`, then rerun the identical Flutter debug build command (including Dart defines). Do not clean unrelated release outputs or the Rust build cache. Verify the new signature, package/ABI and compare uncompressed ZIP entry hashes with the previous APK when no source changes were intended.
