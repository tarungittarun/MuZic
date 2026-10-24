# MuZic — end-to-end test findings

Date: 2026-10-23 · Branch: `arena/dd1906b8-muzic`
Latest run report: the E2E workflow summary and its 30-day `e2e-report` artifact.

The strict E2E workflow drives the real app on Android emulators. It now runs
automatically for app changes on pushes and pull requests, and remains manually
runnable. Any failed journey step blocks the check; no product assertion is a
warning-only pass.

---

## 1. What the workflow is

`.github/workflows/e2e.yml` — four jobs, independent of the release build:

| Job | Runner | What it does |
| --- | --- | --- |
| `static` | ubuntu-24.04 | `flutter analyze --fatal-warnings` + `flutter test --reporter json --coverage` |
| `e2e` | ubuntu-24.04, matrix API **30** and **34** | Builds a debug APK, boots a KVM-accelerated emulator, runs the strict integration journey, validates notification/session and single-task facts, and uploads logs |
| `strict-gate` | ubuntu-24.04 | Fails unless static analysis/tests and both Android matrix journeys succeed |
| `report` | ubuntu-24.04 | Adds a Markdown report to the workflow summary and a 30-day artifact; it does not push commits back into the branch |

The journey (`serverless_music_player/integration_test/app_flow_test.dart`)
runs 18 strict checks plus a cold-start timing metric and prints:

```
[E2E] step=<name> status=PASS|FAIL ms=<duration> detail=<text>
```

Provider-backed search and playback are hard gates too. If live service/network
availability breaks that journey, the E2E check fails visibly instead of
silently passing a warning.

### The strict journey

`cold_start` · `time_to_first_frame` · `home_discover_feed` ·
`one_hand_reach_transition` · `home_recommendation_shelves` · `search_flow` ·
`search_results_structure` · `playback_start` · `media_notification` ·
`now_playing_lock_screen_parity` · `live_waveform_controls` ·
`lyrics_language_picker` · `settings_sections` · `sound_studio_toggle` ·
`sleep_timer_toggle` · `diagnostics_capture` · `usage_insights` ·
`back_from_each_main_destination` · `single_recents_task`

### Why it is separate from the APK build

The release workflow only proves the app **compiles and signs**. It cannot see
whether the home screen renders, whether search returns rows, whether the
settings sections still exist after a refactor, or whether the notification
config is valid at runtime. The E2E workflow answers those questions on two
Android versions before a build is handed over.

---

## 2. Bugs the E2E suite found (and that are now fixed)

All three were **invisible to `flutter analyze` and to the 37 unit/widget
tests** — the first two also never showed up on a release device, because
release builds strip assertions and merely paint an overflow stripe.

### 2.1 Invalid `audio_service` notification config — crashed every debug cold start

`AudioServiceConfig` was created with `androidNotificationOngoing: true` while
`androidStopForegroundOnPause` was `false`, which `audio_service` rejects:

```
Failed assertion: '!androidNotificationOngoing || androidStopForegroundOnPause':
The androidNotificationOngoing will make no effect with
androidStopForegroundOnPause set to false
```

The two flags are coupled: a non-dismissible card is only allowed when the
service leaves the foreground on pause — but leaving the foreground removes the
card as soon as playback pauses, which contradicts the "keep the card visible
while paused" setting. Fixed in `lib/main.dart` by keeping the card dismissible
and preserving the user's keep-on-pause behaviour.

**Fixed in:** commit `79b32fd`.

### 2.2 Album shelf overflowed its fixed height — on every search with results

```
RenderFlex OVERFLOWING · constraints: BoxConstraints(w=128.0, h=162.0)
```

The Albums shelf gives each card 162 px of height. A 128 px cover plus a 7 px
gap plus two text lines needs ≈169 px, so the column overflowed by ~7 px on
**every** search results page in a debug build. The cover now takes whatever
height the labels leave (`Expanded` + `SizedBox.expand`), so the artwork shrinks
instead of overflowing — and the same treatment was applied to the song cards,
whose 5 px of slack would have overflowed with a larger system font.

**Fixed in:** commit `c822a8d`.

### 2.3 Every APK shipped as version `1.0.0` (code `1`)

The device matrix prints the version the phone actually sees. It reported
`1.0.0+1` while `pubspec.yaml` said `1.4.1+6`:

```groovy
// android/app/build.gradle
versionCode = 1          // beat the pubspec on every build
versionName = "1.0.0"
```

The Flutter Gradle plugin's pubspec version is only a *default*, so the
hard-coded values won. Every APK ever handed over installed as `1.0.0` with
version code 1 — the "versionCode must increase every build" rule was never
actually being met, even though the pubspec was being bumped every round.

Both values now come from the Flutter extension
(`flutter.versionCode` / `flutter.versionName`, which read
`version: 1.4.2+7`), and the release workflow reads
`aapt2 dump badging` and fails if the manifest disagrees with the pubspec.
`--split-per-abi` offsets the code per ABI (arm64-v8a is `2000 + base`), so the
guard compares the base code and the version name rather than the raw value.

**Fixed in:** commits `0384728`, `2347486`, `a05bea8`; first correct build is
`apk-build-45` (`1.4.2`, code 2007 on arm64 / 1007 on armv7).

### 2.4 Settings screen was unreachable by the test (test defect, worth knowing)

The first version of the journey tapped the *tune* icon to open Settings. That
icon is also the audio-effects entry inside the now-playing sheet, so the test
could end up on a sheet with no `Scrollable` and fail with the unhelpful
`Bad state: No element`. It also walked the settings sections out of document
order (it looked for `DISCOVER` after scrolling past it to `AUDIO EFFECTS`).
The journey now uses the stable `Settings` tooltip and walks the sections
top-to-bottom. Failures now also quote the text that was on screen, so the
report says *what the user would have seen*.

**Fixed in:** commit `9c5606d`.

### 2.5 The media notification: what the probe actually proved

Three earlier "fixes" guessed at the cause. This round added a native probe
(`mediaNotificationDiagnostics`) that reports the whole chain, and an E2E step
that asserts on it after playback starts. Result on both emulators:

| Probe | API 30 | API 34 |
| --- | --- | --- |
| `notificationsEnabled` | true | true |
| `postPermission` | false (not a runtime permission before 33) | true |
| `playbackChannelExists` | true | true |
| `playbackChannelImportance` | 3 (DEFAULT) | 3 (DEFAULT) |
| `audioServiceDeclared` | true | true |
| `smallIconResolves` | true | true |
| `postedCount` | 1 | 1 |

So `audio_service` **does** post a media card, on a channel with visible
importance, with a resolvable icon. The failure was therefore never "the app
doesn't post it" — it was either a channel that had been created wrong in an
earlier build (Android channels are immutable, so it stays wrong forever), or
the device hiding/blocking it.

Fix: MuZic now owns the channel id, versions it
(`com.music.player.playback.v2`) and creates it itself in
`MainActivity.onCreate` with `IMPORTANCE_DEFAULT`, public lock-screen
visibility and no sound, before `audio_service` posts. A new channel id also
sidesteps whatever state the old `com.music.player.audio` channel is in on any
existing install.

Verification path that does not need a developer: **Settings → Playback →
Media notification health** prints the same chain on the phone and offers to
open Android's notification settings.

---

## 3. CI infrastructure findings (why the device jobs failed for six attempts)

These are environment facts, not app defects, but they are the reason the
emulator matrix produced no results at first.

| Symptom | Root cause | Fix |
| --- | --- | --- |
| Job hung for the full 60-minute timeout | `adb wait-for-device` has **no timeout**; when the emulator dies, it blocks forever | bounded `getprop sys.boot_completed` poll that also detects the emulator process dying |
| `android-emulator-runner` exited silently | action swallowed the failure | replaced with explicit `sdkmanager` / `avdmanager` / `emulator` steps |
| `exit 127: sdkmanager: command not found` | `sdkmanager` is not on `PATH` on the runner image | discover `$ANDROID_SDK_ROOT/cmdline-tools/*/bin` and export it |
| `qemu-system-x86_64: error while loading shared libraries: libpulse.so.0` | emulator 37.x links libpulse **even in `-no-window` mode** | `apt-get install libpulse0 libxcomposite1 libxcursor1 libxi6 libxtst6 libnss3 libgbm1 libxdamage1 libxrandr2` |
| `Unknown AVD name [muzic-34]` right after a successful create | `avdmanager` wrote the AVD outside `$HOME/.android/avd` | create **and** launch with an explicit `ANDROID_AVD_HOME` |
| Device facts all blank / `package=not installed` | every CI step is a fresh shell — `PATH` exports do not persist | export the SDK paths inside each step that needs ADB; capture package facts *before* `flutter test` (it uninstalls the app afterwards) |
| One matrix leg failed to compile while the other passed on the same commit | transient Gradle failure, and the step only printed its last 20 lines | retry once, annotate the compiler errors, keep `build-debug.log` as an artefact |
| Emulator boots in 40–100 s but occasionally needs longer | cold boot with `-wipe-data` | 15-minute bounded poll with a 20 s per-`adb` timeout |

KVM was never the problem: `/dev/kvm` is present and `kvm-ok` reports
"KVM acceleration can be used" on the runner.

---

## 4. Current results

From [`LATEST.md`](LATEST.md) (run 35, commit `8048d95`):

| Area | Result |
| --- | --- |
| Static analysis | 0 errors, 0 warnings, 9 lint infos |
| Unit & widget tests | 43 passed, 0 failed (100 %) |
| Line coverage | 57.1 % (757/1325 lines) |
| E2E steps, API 30 (Android 11) | 15/15 PASS |
| E2E steps, API 34 (Android 14) | 15/15 PASS |
| Version seen on device | `1.5.1+9` on both emulators (was `1.0.0+1`) |
| Cold start (software-rendered emulator) | 5.27 s worst case — budget 8 s |
| Search round trip | 2.74 s — budget 12 s |
| Playback start | 0.90 s — budget 15 s |

Timings are worst-case: the emulator renders with `swiftshader` software GL and
shares 4 vCPUs. Real hardware is materially faster.

---

## 5. Known gaps

- **The emulator cannot photograph the notification shade.** The E2E run
  strictly verifies notification permission/channel, the active MediaSession,
  posted notification, and foreground playback service. The lock-screen card's
  visual appearance is separately evidenced by the supplied Motorola/Samsung
  device screenshots; a headless emulator cannot assert pixel-level shade UI.
- **Coverage is 55 % in the historical run cited above** — concentrated in
  services and widgets; screens are also covered by the strict E2E journey.
- Only two API levels are covered; adding API 24 (minSdk floor) and API 35 would
  widen the matrix at roughly one extra emulator boot each.

---

## 6. Running it yourself

```bash
# everything except the emulator
cd serverless_music_player
flutter analyze --fatal-warnings
flutter test --coverage

# the full journey on a connected device or a running emulator
flutter test integration_test/app_flow_test.dart -d <device-id> --reporter expanded
```

On CI the workflow triggers on app changes for every push and pull request,
and by hand (`workflow_dispatch`). Reports stay in the Actions summary and
artifact so CI cannot self-trigger by committing generated report changes.


---

## 7. Strict pipeline update (2026-10-23)

The E2E suite now runs on app pushes and pull requests, uses a dedicated strict
gate, and treats every integration assertion as a hard failure. We added checks
for the one-hand transition (including the removal of the Last played overlay),
the full-face in-app controller and wavy seek control, live waveform UI, the
new Sound Studio controls, Usage insights, Android Back from Library/Settings/
Usage, and Android task count. The report is an artifact/summary rather than a
branch commit, preventing a report loop.
