# MuZic end-to-end test report

Generated: 2026-10-21 02:34 UTC  
Commit: `c822a8d` · Run: `21`

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
| 30 | `cold_start` | ✅ PASS | 3.45s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 3.46s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.02s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.52s |  |
| 30 | `search_flow` | ✅ PASS | 2.89s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 1.24s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 8.46s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.69s |  |
| 30 | `settings_sections` | ✅ PASS | 4.18s |  |
| 30 | `sleep_timer_toggle` | ✅ PASS | 1.43s |  |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.84s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.36s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.18s |  |
| 34 | `cold_start` | ✅ PASS | 3.52s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 3.52s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.03s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 1.06s |  |
| 34 | `search_flow` | ✅ PASS | 3.01s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 1.06s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 14.35s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 1.76s |  |
| 34 | `settings_sections` | ✅ PASS | 7.16s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 2.36s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 1.45s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.12s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.40s |  |

## 4. Device matrix

| API level | Android | ABI | Installed package |
| --- | --- | --- | --- |
| 30 | 11 | x86_64 | `not installed` |
| 34 | 14 | x86_64 | `not installed` |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 3.45s | 8.0s | ✅ within |
| `time_to_first_frame` | 3.46s | 8.0s | ✅ within |
| `search_flow` | 2.89s | 12.0s | ✅ within |
| `playback_start` | 1.24s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
