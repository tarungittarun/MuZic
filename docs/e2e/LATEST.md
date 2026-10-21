# MuZic end-to-end test report

Generated: 2026-10-21 06:11 UTC  
Commit: `8048d95` · Run: `35`

What this suite covers, why it exists and what it has found: [FINDINGS.md](FINDINGS.md).

## 1. Static analysis

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 0 |
| Lint infos | 8 |
| Verdict | ✅ clean |

## 2. Unit & widget tests

| Metric | Value |
| --- | --- |
| Passed | 43 |
| Failed | 0 |
| Pass rate | 100.0% |

Line coverage: **57.1%** (757/1325 lines)

## 3. End-to-end journeys (real Android emulator)

| API level | Step | Status | Time | Detail |
| --- | --- | --- | --- | --- |
| 30 | `cold_start` | ✅ PASS | 2.15s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 2.15s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.04s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.63s |  |
| 30 | `search_flow` | ✅ PASS | 2.21s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 0.97s |  |
| 30 | `media_notification` | ✅ PASS | 3.69s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 4.16s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.59s |  |
| 30 | `settings_sections` | ✅ PASS | 3.05s |  |
| 30 | `sleep_timer_toggle` | ✅ PASS | 1.33s |  |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.77s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.08s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.15s |  |
| 34 | `cold_start` | ✅ PASS | 4.73s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 4.74s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.03s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 0.82s |  |
| 34 | `search_flow` | ✅ PASS | 4.37s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.01s |  |
| 34 | `playback_start` | ✅ PASS | 0.86s |  |
| 34 | `media_notification` | ✅ PASS | 4.79s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 4.36s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 1.63s |  |
| 34 | `settings_sections` | ✅ PASS | 4.43s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 2.33s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.85s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 3.13s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.26s |  |

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
| emulator-30 (API 30) | 11 | x86_64 | `1.5.1+9` | 153.8 MB | ✅ 14/14 |
| emulator-34 (API 34) | 14 | x86_64 | `1.5.1+9` | 153.8 MB | ✅ 14/14 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 2.15s | 8.0s | ✅ within |
| `time_to_first_frame` | 2.15s | 8.0s | ✅ within |
| `search_flow` | 2.21s | 12.0s | ✅ within |
| `playback_start` | 0.97s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
