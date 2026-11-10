---
name: mornye-device-check
description: Safely install a Mornye Android build and validate streaming playback or backup restoration on a connected device. Use for adb installation, on-device verification, signature mismatches, or manual regression testing.
---

# Check Mornye on an Android device

Read `AGENTS.md` first. Build and verify the APK with the `mornye-android-build` skill before installation.

## Protect app data

- Use `adb install -r <apk>` to update an existing compatible installation.
- Never uninstall Mornye, use `pm clear`, or erase app data to bypass a signature mismatch without explicit user approval and a verified backup.
- An official Mornye installation cannot be updated with the local debug-signed APK. Stop and offer a side-by-side application ID or a properly signed build instead.
- A Mornye `.sflb` backup does not include downloaded audio files. Do not describe it as a complete data backup.

## Connect and install

```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
ADB="$ANDROID_HOME/platform-tools/adb"
"$ADB" devices
```

If no authorized device is listed, report that device verification is blocked. Do not claim playback or restore behavior was tested.

Install without removing existing data:

```bash
"$ADB" install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

If installation fails because signatures differ, stop. Do not uninstall automatically.

## Verify progressive playback

Use tracks and albums that are not already downloaded:

1. Start a track and confirm audible playback begins while download progress continues.
2. Let the download finish and confirm playback continues through the partial-file-to-final-file handoff.
3. Start an album from a middle track. Confirm that track is prioritized and remaining album downloads continue.
4. Test pause, resume, seeking within downloaded data, cancellation, and moving to the next track.
5. Check encrypted or unrecognized downloads use the finalized-file fallback rather than playing invalid bytes.
6. Watch Mornye logs for HTTP range, source-resolution, download, and player errors.

Record real-provider startup timing and any player-specific failures. Passing widget or service tests is not a substitute for these checks.

## Verify backup restoration

1. Keep a second copy of the original `.sflb` file.
2. Restore it through Settings > Backup & Restore.
3. Confirm the success message rather than only checking that the file was accepted.
4. Restart Mornye and verify settings, history, liked items, playlists, and extensions included in that backup.
5. If restoration fails, capture the exact log entry. Do not retry by deleting app data.

Report each verified scenario separately and list anything not tested.
