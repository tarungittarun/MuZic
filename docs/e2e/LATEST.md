# MuZic end-to-end test report

Generated: 2026-10-21 02:48 UTC  
Commit: `0982a98` · Run: `22`

What this suite covers, why it exists and what it has found: [FINDINGS.md](FINDINGS.md).

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
| 30 | `cold_start` | ✅ PASS | 1.90s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 1.90s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.04s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.41s |  |
| 30 | `search_flow` | ✅ PASS | 2.77s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 0.65s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 7.57s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.46s |  |
| 30 | `settings_sections` | ✅ PASS | 3.20s |  |
| 30 | `sleep_timer_toggle` | ✅ PASS | 1.07s |  |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.82s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.13s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.25s |  |
| 34 | `cold_start` | ✅ PASS | 5.35s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 5.36s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.08s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 0.49s |  |
| 34 | `search_flow` | ✅ PASS | 4.36s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.01s |  |
| 34 | `playback_start` | ✅ PASS | 0.94s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 12.96s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 2.54s |  |
| 34 | `settings_sections` | ✅ PASS | 7.96s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 1.41s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.70s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.31s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.31s |  |

## 4. Device matrix

| Device | Android | ABI | MuZic build | APK | Journey |
| --- | --- | --- | --- | --- | --- |
| emulator-30 (API 30) | 11 | x86_64 | `1.0.0+1` | 153.8 MB | ✅ 14/14 |
| emulator-34 (API 34) | 14 | x86_64 | `1.0.0+1` | 153.8 MB | ✅ 14/14 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 1.90s | 8.0s | ✅ within |
| `time_to_first_frame` | 1.90s | 8.0s | ✅ within |
| `search_flow` | 2.77s | 12.0s | ✅ within |
| `playback_start` | 0.65s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
