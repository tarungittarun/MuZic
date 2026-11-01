# MuZic — serverless Flutter music player

MuZic is an Android-first Flutter source project. Playback, queues, downloads, favorites, playlists, and recents are handled on-device; the app has no backend service or paid API key.

## Build locally

Requirements: Flutter 3.27+ / Dart 3.6+, Android SDK 35, Android build tools, and JDK 17. This workspace did **not** contain Flutter, Dart, the Android SDK, or Gradle, so no APK has been produced or test-built here.

```bash
cd serverless_music_player
flutter pub get
flutter run
```

For smaller device-specific builds:

```bash
flutter build apk --release --split-per-abi \
  --obfuscate \
  --split-debug-info=build/muzic-symbols
```

Outputs are placed in `build/app/outputs/flutter-apk/`. `arm64-v8a` is the normal 64-bit Android target; `armeabi-v7a` is included for older 32-bit devices. ABI splitting reduces each individual APK, but **an under-20-MB size cannot be guaranteed**: Flutter engine/runtime, plugin native libraries, artwork, and build versions affect the final size. Check each artifact after building. `flutter build appbundle --release` is preferable for Play distribution.

Release builds require `android/key.properties` and a private keystore; Gradle refuses to produce a debug-signed release when signing configuration is missing. Keep both files local and out of Git. The APK workflow reads the keystore and credentials only from protected GitHub Actions secrets and skips publication when they are not configured. Never put keystore files or passwords in source control or workflow text. Keep the `build/muzic-symbols` mapping private and backed up if you need to decode obfuscated crash traces; do not attach it to public APK releases.

## Android permissions and background audio

`android/app/src/main/AndroidManifest.xml` declares Internet access, wake lock, foreground media playback, notification permission, and microphone access only for the optional live visualizer. It does not request contacts, location, camera, SMS, phone-state, or broad shared-storage permissions. Cleartext HTTP and Android backup are disabled. Audio is downloaded into app-private storage or a folder the user explicitly selects. The exported activity and media service exist for launching and Android media controls; the FileProvider is non-exported and scoped to a cache folder.


## Privacy and release identity

The app does not require an account and includes no ads or analytics SDK. Library data and usage summaries are stored locally in Android app-private storage. Hive data is not separately encrypted by MuZic; Android backup is disabled, but that does not protect data on a rooted, unlocked, or otherwise compromised device. Audio saved to a folder the user selects follows that folder's access controls. Search, playback, artwork, and lyric requests go directly to third-party services; those services may receive the device IP address and request details. Diagnostics capture is off by default. Diagnostic exports redact known provider labels, URLs, and credential-like values, but can still contain track titles and device details; the user must explicitly save or share a report. Source labels are generic in the app, but contacted services remain identifiable from network traffic and APK inspection; obfuscation is not secrecy.

The Android application ID is `com.github.tarungittarun.muzic`. Android treats it as a separate app package; earlier private app data is not migrated. Release builds use R8 shrinking and Flutter symbol obfuscation to raise reverse-engineering effort, not to make a client APK impossible to inspect. No service credentials should be embedded in the APK.

## Data-source and rights notes

JioSaavn search/stream fields are undocumented public endpoints and their response schema or access rules can change. YouTube stream resolution uses `youtube_explode_dart`, which is an unofficial client of YouTube's internal interfaces and may stop working when those interfaces change. Neither source has a service-level availability guarantee. Review each provider's current terms and obtain licenses/permission for any content you stream or save. Only download audio you own or are explicitly allowed to download; the app does not bypass account authentication or DRM. LRCLIB lyrics are best-effort and are not guaranteed for every track. See [`docs/SOURCE_OPTIONS.md`](../docs/SOURCE_OPTIONS.md) for the 2026 review of official alternatives and their playback/download/synchronization constraints.

## Deliverables by step

1. **Project and Android configuration:** `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle`, and the Android Gradle wrapper/configuration.
2. **Models and source resolver:** `lib/models/song_model.dart`, `lib/models/lyrics_model.dart`, and `lib/services/music_api_service.dart` (JioSaavn search/DES URL decoding, YouTube audio-only selection, automatic source fallback, autocomplete, and LRCLIB lyrics).
3. **Playback and offline library:** `lib/services/audio_player_service.dart`, `lib/services/download_service.dart`, `lib/services/library_service.dart`, and `lib/providers/player_controller.dart` (gapless queue, notification metadata, downloads/artwork, Hive favorites/playlists/recents/download index).
4. **Material 3 interface:** `lib/screens/` and `lib/widgets/` (Discover/Search, Library, downloads, mini-player, full player, queue, repeat/shuffle, and lyrics).

## Project map

```text
lib/
  app.dart
  main.dart
  models/       Song, source, playlist, lyric models
  providers/    PlayerController state + queue orchestration
  services/     JioSaavn/YouTube/LRCLIB client, audio, Hive, downloads
  screens/      Discover and local library
  widgets/      Song rows, artwork, mini player, full player/queue/lyrics
  theme/        Dark Material 3 palette
android/app/
  build.gradle  release shrinking and ABI split settings
  src/main/     Android manifest, launcher and splash resources
```
