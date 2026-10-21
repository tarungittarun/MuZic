# MuZic end-to-end test report

Generated: 2026-10-21 02:20 UTC  
Commit: `9c5606d` · Run: `20`

## 1. Static analysis

| Metric | Value |
| --- | --- |
| Errors | 0 |
| Warnings | 0 |
| Lint infos | 9 |
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
| 30 | `cold_start` | ✅ PASS | 2.57s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 2.57s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.02s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.62s |  |
| 30 | `search_flow` | ✅ PASS | 4.43s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 0.80s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 9.27s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.73s |  |
| 30 | `settings_sections` | ✅ PASS | 3.96s |  |
| 30 | `sleep_timer_toggle` | ✅ PASS | 1.49s |  |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.78s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.21s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.12s |  |
| 34 | `cold_start` | ✅ PASS | 5.24s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 5.27s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.04s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 2.20s |  |
| 34 | `search_flow` | ✅ PASS | 4.01s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 1.11s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 9.68s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 1.57s |  |
| 34 | `settings_sections` | ✅ PASS | 4.17s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 2.35s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.85s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.42s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.11s |  |

## 4. Device matrix

| API level | Android | ABI | Installed package |
| --- | --- | --- | --- |
| 30 | ? | ? | `not installed` |
| 34 | ? | ? | `not installed` |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 2.57s | 8.0s | ✅ within |
| `time_to_first_frame` | 2.57s | 8.0s | ✅ within |
| `search_flow` | 4.43s | 12.0s | ✅ within |
| `playback_start` | 0.80s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
