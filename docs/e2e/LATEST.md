# MuZic end-to-end test report

Generated: 2026-10-21 06:01 UTC  
Commit: `6e80471` · Run: `34`

What this suite covers, why it exists and what it has found: [FINDINGS.md](FINDINGS.md).

## 1. Static analysis

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 0 |
| Lint infos | 7 |
| Verdict | ✅ clean |

## 2. Unit & widget tests

| Metric | Value |
| --- | --- |
| Passed | 37 |
| Failed | 0 |
| Pass rate | 100.0% |

Line coverage: **55.0%** (686/1247 lines)

## 3. End-to-end journeys (real Android emulator)

| API level | Step | Status | Time | Detail |
| --- | --- | --- | --- | --- |
| 30 | `cold_start` | ✅ PASS | 4.08s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 4.09s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.03s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.54s |  |
| 30 | `search_flow` | ✅ PASS | 2.71s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.01s |  |
| 30 | `playback_start` | ✅ PASS | 0.99s |  |
| 30 | `media_notification` | ✅ PASS | 5.53s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 4.29s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.70s |  |
| 30 | `settings_sections` | ✅ PASS | 3.38s |  |
| 30 | `sleep_timer_toggle` | ⚠️ WARN | 1.19s | Expected: exactly one matching candidate [screen: Pause after inactivity / A warning appears 5 minutes before MuZic pauses playback when nothing has happened in the app. / DISCOVER / Region / India / Languages / Hindi, English / AUDIO EFFECTS / Virtualizer (surround) / Widens the sound stage — close |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.75s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.05s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.30s |  |
| 34 | `cold_start` | ✅ PASS | 2.89s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 2.90s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.02s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 0.53s |  |
| 34 | `search_flow` | ✅ PASS | 2.45s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 0.67s |  |
| 34 | `media_notification` | ✅ PASS | 5.51s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 5.02s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 2.39s |  |
| 34 | `settings_sections` | ✅ PASS | 4.63s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 1.13s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.78s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.17s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.14s |  |

### Media notification, as Android sees it

| Probe | API 30 | API 34 |
| --- | --- | --- |
| `notificationsEnabled` | true | true |
| `postPermission` | false | true |
| `playbackChannelExists` | true | true |
| `playbackChannelImportance` | 3 | 3 |
| `audioServiceDeclared` | true | true |
| `smallIconResolves` | true | true |
| `postedCount` | 1 | 1 |
| `posted` | [com.music.player.playback.v2#1124 | [com.music.player.playback.v2#1124] |

## 4. Device matrix

| Device | Android | ABI | MuZic build | APK | Journey |
| --- | --- | --- | --- | --- | --- |
| emulator-30 (API 30) | 11 | x86_64 | `1.5.0+8` | 153.8 MB | ✅ 14/14 |
| emulator-34 (API 34) | 14 | x86_64 | `1.5.0+8` | 153.8 MB | ✅ 14/14 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 4.08s | 8.0s | ✅ within |
| `time_to_first_frame` | 4.09s | 8.0s | ✅ within |
| `search_flow` | 2.71s | 12.0s | ✅ within |
| `playback_start` | 0.99s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
