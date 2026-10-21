# MuZic end-to-end test report

Generated: 2026-10-21 03:28 UTC  
Commit: `a05bea8` · Run: `25`

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
| 30 | `cold_start` | ✅ PASS | 4.21s |  |
| 30 | `time_to_first_frame` | ✅ PASS | 4.22s |  |
| 30 | `home_discover_feed` | ✅ PASS | 0.02s |  |
| 30 | `home_recommendation_shelves` | ✅ PASS | 0.43s |  |
| 30 | `search_flow` | ✅ PASS | 3.28s |  |
| 30 | `search_results_structure` | ✅ PASS | 0.01s |  |
| 30 | `playback_start` | ✅ PASS | 0.92s |  |
| 30 | `now_playing_and_lyrics` | ✅ PASS | 8.78s |  |
| 30 | `lyrics_language_picker` | ✅ PASS | 1.58s |  |
| 30 | `settings_sections` | ✅ PASS | 3.69s |  |
| 30 | `sleep_timer_toggle` | ✅ PASS | 1.23s |  |
| 30 | `audio_effects_toggle` | ✅ PASS | 0.69s |  |
| 30 | `diagnostics_capture` | ✅ PASS | 2.10s |  |
| 30 | `navigation_back_home` | ✅ PASS | 0.28s |  |

## 4. Device matrix

| Device | Android | ABI | MuZic build | APK | Journey |
| --- | --- | --- | --- | --- | --- |
| emulator-30 (API 30) | 11 | x86_64 | `1.4.2+7` | 153.8 MB | ✅ 14/14 |
| emulator-34 (API 34) | ? | ? | `—+—` | — | ❌ see §3 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 4.21s | 8.0s | ✅ within |
| `time_to_first_frame` | 4.22s | 8.0s | ✅ within |
| `search_flow` | 3.28s | 12.0s | ✅ within |
| `playback_start` | 0.92s | 15.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
