# MuZic end-to-end test report

Generated: 2026-10-21 01:57 UTC  
Commit: `2dfcdcb` · Run: `18`

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
| 30 | `cold_start` | ❌ FAIL | 0.21s | 'package:audio_service/audio_service.dart': Failed assertion: line 3525 pos 11: '!androidNotificationOngoing / |
| 34 | `cold_start` | ❌ FAIL | 1.21s | 'package:audio_service/audio_service.dart': Failed assertion: line 3525 pos 11: '!androidNotificationOngoing / |

## 4. Device matrix

| Fact | Value |
| --- | --- |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |
| `cold_start` | 0.21s | 8.0s | ✅ within |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
