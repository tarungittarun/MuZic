# MuZic end-to-end test report

Generated: 2026-10-21 05:32 UTC  
Commit: `eb34dfb` · Run: `29`

What this suite covers, why it exists and what it has found: [FINDINGS.md](FINDINGS.md).

## 1. Static analysis

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 0 |
| Lint infos | 10 |
| Verdict | ✅ clean |

## 2. Unit & widget tests

| Metric | Value |
| --- | --- |
| Passed | 0 |
| Failed | 0 |
| Pass rate | 0.0% |

## 3. End-to-end journeys (real Android emulator)

| API level | Step | Status | Time | Detail |
| --- | --- | --- | --- | --- |
| 30 | `cold_start` | ✅ PASS | 3.39s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 3.40s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.04s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.50s |  |
| 30 | `search_flow` | ✅ PASS | 2.10s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 0.87s |  |
| 30 | `media_notification` | ✅ PASS | 4.81s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 4.61s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.48s |  |
| 30 | `settings_sections` | ✅ PASS | 4.06s |  |
| 30 | `sleep_timer_toggle` | ⚠️ WARN | 1.50s | Expected: exactly one matching candidate [screen: Pause after inactivity / A warning appears 5 minutes before MuZic pauses playback when nothing has happened in the app. / DISCOVER / Region / India / Languages / Hindi, English / AUDIO EFFECTS / Virtualizer (surround) / Widens the sound stage — close |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.78s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.42s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.25s |  |
| 34 | `cold_start` | ✅ PASS | 3.49s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 3.50s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.08s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 0.95s |  |
| 34 | `search_flow` | ✅ PASS | 6.11s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 1.41s |  |
| 34 | `media_notification` | ✅ PASS | 7.40s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 10.74s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 1.56s |  |
| 34 | `settings_sections` | ✅ PASS | 4.38s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 1.54s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.81s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.20s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.31s |  |

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
| `cold_start` | 3.39s | 8.0s | ✅ within |
| `time_to_first_frame` | 3.40s | 8.0s | ✅ within |
| `search_flow` | 2.10s | 12.0s | ✅ within |
| `playback_start` | 0.87s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
