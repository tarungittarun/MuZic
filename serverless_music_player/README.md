# Auralis — serverless Flutter music player

Auralis is an Android-first Flutter source project. Playback, queues, downloads, favorites, playlists, and recents are handled on-device; the app has no backend service or paid API key.

## Build locally

Requirements: Flutter 3.27+ / Dart 3.6+, Android SDK 35, Android build tools, and JDK 17. This workspace did **not** contain Flutter, Dart, the Android SDK, or Gradle, so no APK has been produced or test-built here.

```bash
cd serverless_music_player
flutter pub get
flutter run
```

For smaller device-specific builds:

```bash
flutter build apk --release --split-per-abi
```

Outputs are placed in `build/app/outputs/flutter-apk/`. `arm64-v8a` is the normal 64-bit Android target; `armeabi-v7a` is included for older 32-bit devices. ABI splitting reduces each individual APK, but **an under-20-MB size cannot be guaranteed**: Flutter engine/runtime, plugin native libraries, artwork, and build versions affect the final size. Check each artifact after building. `flutter build appbundle --release` is preferable for Play distribution.

The Gradle configuration creates a debug-signed release APK for quick device testing when `android/key.properties` is absent. For distribution, create and protect a release keystore, add `android/key.properties` locally (it is gitignored), and use your own signing credentials. Never ship a debug-signed build.

## Android permissions and background audio

`android/app/src/main/AndroidManifest.xml` declares only Internet access, wake lock, foreground playback service, and Android 13+ notification permission. Audio is downloaded into the app-private `Documents/music` directory, so the app does not request broad/shared-storage access on Android 10–15. Notification permission is requested when playback first starts. The activity/service/receiver entries follow `just_audio_background`'s Android setup.

## Data-source and rights notes

JioSaavn search/stream fields are undocumented public endpoints and their response schema or access rules can change. YouTube stream resolution uses `youtube_explode_dart`, which is an unofficial client of YouTube's internal interfaces and may stop working when those interfaces change. Neither source has a service-level availability guarantee. Review each provider's current terms and obtain licenses/permission for any content you stream or save. Only download audio you own or are explicitly allowed to download; the app does not bypass account authentication or DRM. LRCLIB lyrics are best-effort and are not guaranteed for every track.

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
