# MuZic end-to-end test report

Generated: 2026-10-21 07:02 UTC  
Commit: `6d122a4` · Run: `41`

What this suite covers, why it exists and what it has found: [FINDINGS.md](FINDINGS.md).

## 1. Static analysis

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 0 |
| Lint infos | 3 |
| Verdict | ✅ clean |

## 2. Unit & widget tests

| Metric | Value |
| --- | --- |
| Passed | 44 |
| Failed | 0 |
| Pass rate | 100.0% |

Line coverage: **57.1%** (757/1325 lines)

## 3. End-to-end journeys (real Android emulator)

| API level | Step | Status | Time | Detail |
| --- | --- | --- | --- | --- |
| 30 | `cold_start` | ✅ PASS | 1.71s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 1.72s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.02s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.47s |  |
| 30 | `search_flow` | ✅ PASS | 2.39s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 0.77s |  |
| 30 | `media_notification` | ✅ PASS | 0.20s |  |
| 34 | `cold_start` | ✅ PASS | 4.98s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 4.98s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.02s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 1.09s |  |
| 34 | `search_flow` | ✅ PASS | 6.10s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 1.44s |  |
| 34 | `media_notification` | ✅ PASS | 2.04s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 8.53s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 2.05s |  |
| 34 | `settings_sections` | ✅ PASS | 4.53s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 2.37s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.66s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.59s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.40s |  |

### Media notification, as Android sees it

| Probe | API 30 | API 34 |
| --- | --- | --- |
| `notificationsEnabled` | true | true |
| `postPermission` | false | true |
| `playbackChannelExists` | true | true |
| `playbackChannelImportance` | 3 | 3 |
| `audioServiceDeclared` | true | true |
| `mediaSessionActive` | true | true |
| `playbackServiceRunning` | true | true |
| `smallIconResolves` | true | true |
| `postedCount` | 1 | 1 |
| `posted` | [com.music.player.playback.v2#1201] | [com.music.player.playback.v2#1201] |

## 4. Device matrix

| Device | Android | ABI | MuZic build | APK | Journey |
| --- | --- | --- | --- | --- | --- |
| emulator-30 (API 30) | 11 | x86_64 | `1.5.2+10` | 153.6 MB | ✅ 14/14 |
| emulator-34 (API 34) | 14 | x86_64 | `1.5.2+10` | 153.6 MB | ✅ 14/14 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 1.71s | 8.0s | ✅ within |
| `time_to_first_frame` | 1.72s | 8.0s | ✅ within |
| `search_flow` | 2.39s | 12.0s | ✅ within |
| `playback_start` | 0.77s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
