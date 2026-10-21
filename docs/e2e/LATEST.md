# MuZic end-to-end test report

Generated: 2026-10-21 04:03 UTC  
Commit: `1286fe9` · Run: `27`

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
| 30 | `cold_start` | ✅ PASS | 3.20s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 3.20s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.04s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.46s |  |
| 30 | `search_flow` | ✅ PASS | 2.60s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 30 | `playback_start` | ✅ PASS | 0.81s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 8.94s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.84s |  |
| 30 | `settings_sections` | ✅ PASS | 4.30s |  |
| 30 | `sleep_timer_toggle` | ✅ PASS | 1.58s |  |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.72s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.08s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.27s |  |
| 34 | `cold_start` | ✅ PASS | 3.90s |  |
| 34 | `time_to_first_frame` | ✅ PASS | 3.90s |  |
| 34 | `home_discover_feed` | ✅ PASS | 0.01s |  |
| 34 | `home_recommendation_shelves` | ✅ PASS | 0.91s |  |
| 34 | `search_flow` | ✅ PASS | 3.67s |  |
| 34 | `search_results_structure` | ✅ PASS | 0.00s |  |
| 34 | `playback_start` | ✅ PASS | 0.93s |  |
| 34 | `now_playing_and_lyrics` | ✅ PASS | 8.72s |  |
| 34 | `lyrics_language_picker` | ✅ PASS | 1.67s |  |
| 34 | `settings_sections` | ✅ PASS | 3.20s |  |
| 34 | `sleep_timer_toggle` | ✅ PASS | 1.36s |  |
| 34 | `audio_effects_toggle` | ✅ PASS | 0.81s |  |
| 34 | `diagnostics_capture` | ✅ PASS | 2.33s |  |
| 34 | `navigation_back_home` | ✅ PASS | 0.37s |  |

## 4. Device matrix

| Device | Android | ABI | MuZic build | APK | Journey |
| --- | --- | --- | --- | --- | --- |
| emulator-30 (API 30) | 11 | x86_64 | `1.4.2+7` | 153.8 MB | ✅ 14/14 |
| emulator-34 (API 34) | 14 | x86_64 | `1.4.2+7` | 153.8 MB | ✅ 14/14 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 3.20s | 8.0s | ✅ within |
| `time_to_first_frame` | 3.20s | 8.0s | ✅ within |
| `search_flow` | 2.60s | 12.0s | ✅ within |
| `playback_start` | 0.81s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
