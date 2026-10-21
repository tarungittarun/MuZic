# MuZic end-to-end test report

Generated: 2026-10-21 06:43 UTC  
Commit: `c48f870` · Run: `38`

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
| – | no journey output | ❌ | – | emulator job failed before emitting steps |

### Media notification, as Android sees it

No notification report was produced.

## 4. Device matrix

| Device | Android | ABI | MuZic build | APK | Journey |
| --- | --- | --- | --- | --- | --- |
| emulator-30 (API 30) | ? | ? | `—+—` | — | ❌ see §3 |
| emulator-34 (API 34) | ? | ? | `—+—` | — | ❌ see §3 |

## 5. Timings & budgets

| Step | Measured | Budget | Verdict |
| --- | --- | --- | --- |

## 6. Notes

- Steps marked ⚠️ depend on the live JioSaavn/YouTube network and do not fail the build.
- `cold_start` measures process start → first rendered home frame on a software-rendered emulator, so real hardware is faster.
- The device matrix runs the same journey on API 30 (Android 11) and API 34 (Android 14).
