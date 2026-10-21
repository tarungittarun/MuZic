# MuZic end-to-end test report

Generated: 2026-10-21 02:07 UTC  
Commit: `79b32fd` · Run: `19`

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
| 30 | `cold_start` | ✅ PASS | 1.59s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 1.59s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.01s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.47s |  |
| 30 | `search_flow` | ✅ PASS | 1.77s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.01s |  |
| 30 | `playback_start` | ✅ PASS | 0.55s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 7.63s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.63s |  |
| 30 | `settings_sections` | ❌ FAIL | 11.18s | Bad state: No element |
| 34 | `cold_start` | ✅ PASS | 3.71s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 3.72s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.01s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 0.49s |  |
| 34 | `search_flow` | ✅ PASS | 3.90s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 3.10s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 13.60s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 0.00s |  |
| 34 | `settings_sections` | ❌ FAIL | 23.71s | Bad state: No element |

## 4. Device matrix

| Fact | Value |
| --- | --- |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 1.59s | 8.0s | ✅ within |
| `time_to_first_frame` | 1.59s | 8.0s | ✅ within |
| `search_flow` | 1.77s | 12.0s | ✅ within |
| `playback_start` | 0.55s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
