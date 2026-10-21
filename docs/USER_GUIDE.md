# MuZic — User Guide

Everything MuZic can do, screen by screen. The pictures below are **schematic
illustrations** of each screen (drawn to match the app's dark theme), not device
screenshots.

---

## 1. Install & update

| What | How |
| --- | --- |
| **Install** | Open the latest release on GitHub → **Assets** → download `app-arm64-v8a-release.apk` (most phones) → tap it → *Install anyway* if Android warns about an unknown source. |
| **Older 32-bit phone** | Use `app-armeabi-v7a-release.apk` instead. |
| **Update** | Download the newest APK and install it over the old one. Every MuZic build is signed with the same key (`04d6c78f…`) and bumps the version code, so it updates in place — **no uninstall needed**. |
| **If you ever see "package conflicts"** | You are installing over an old build from before the signing fix. Uninstall MuZic once, then install the new APK. This will not happen again. |
| **Version** | Settings → About shows the version (e.g. `1.4.1+6`). |

---

## 2. Discover home

![Discover home](img/home.svg)

The home tab is a browsable feed, not just a search box.

1. **Greeting + search bar** at the top.
2. **Recently played** — the last tracks you started, newest first.
3. **Liked songs** — everything you hearted.
4. **Trending in \<language\>** — one shelf per language you picked
   (live JioSaavn charts).
5. **Lossless radio** — free FLAC streams (see §10).
6. **Your playlists** — tap a chip to play it.

**Pull down to refresh** trending shelves.

### Choosing your region and languages

*Settings → Discover*

| Setting | Effect |
| --- | --- |
| **Region** | India, US, UK, UAE, Singapore, Australia, Canada, Pakistan, Bangladesh, Nepal, Sri Lanka, South Africa. |
| **Languages** | Multi-select: Hindi, English, Punjabi, Tamil, Telugu, Marathi, Gujarati, Bengali, Kannada, Bhojpuri, Malayalam, Urdu, Haryanvi, Rajasthani, Odia, Assamese. |

Each selected language adds its own trending shelf on the home screen; the
shelves reload automatically when you change the selection.

---

## 3. Search

1. Type in the search field and press the arrow (or Enter).
2. Source chips let you switch between **Auto**, **JioSaavn** and **YouTube**;
   switching re-runs the search.
3. Results are grouped like other music apps:
   - **Top result** — big card, one tap to play.
   - **Albums** — horizontally scrollable; tap one to open a sheet listing every
     track in that album (tap any track to play the album from there).
   - **Songs** — up to 30 results with the usual actions (favourite, download,
     add to queue/playlist, details).
4. The **✕** button clears the search and returns you to the home feed.

---

## 4. Playing music

![Now playing](img/now-playing.svg)

- Tap any track, shelf card or album row to start playback.
- The **mini player** at the bottom opens the full now-playing sheet.
- **Queue** (☰ in now playing): reorder, jump to a track, remove items.
- **Shuffle / repeat** live in the mini player and the queue sheet.
- Playback continues in the background and survives screen-off.

### The quality badge

Tap the small badge under the artist (e.g. `AAC 320 kbps`) to open the
**Audio quality & signal path** sheet. It shows the real codec/bitrate, the
source, the stream host, and an honest note that Android may resample to 48 kHz
unless you use a USB DAC.

MuZic never claims "hi-res" for a lossy stream: JioSaavn tops out at AAC
320 kbps, YouTube at Opus/AAC.

---

## 5. Lyrics

![Synced lyrics](img/lyrics.svg)

Open the now-playing sheet and tap the **lyrics** icon.

- **Auto-scroll** follows the song smoothly and keeps the current line around a
  third of the way down the screen.
- **Take control**: drag the lyrics and auto-scroll stops immediately; a
  **Resume auto-scroll** pill appears. It also resumes by itself after 5 seconds
  of no interaction (or immediately if you tap the lyrics).
- **Language button** (top right, e.g. `हिन्दी`) opens the language sheet:

  *Available for this track* — versions actually provided for this song
  (synced/plain, with a check mark on the active one).

  *All languages* — English, Hindi, Telugu, Tamil, Kannada, Malayalam, Bengali,
  Punjabi, Gujarati, Marathi, Urdu, **Romanized (Latin letters)** and
  **Original language**. Each row says whether it is available for this song or
  will fall back to the original/romanized text.

- Your choice is remembered **per song**; *Follow default setting* uses the
  default from *Settings → Lyrics*.

---

## 6. The playback notification

![Playback notification settings](img/notifications.svg)

MuZic uses Android's **system media player** — the same controller the
phone itself renders on the lock screen and in Quick Settings
(full-width artwork, seek bar, shuffle / previous / play-pause / next /
repeat). It is provided by the standard `audio_service` +
`just_audio_background` stack: every song carries a media tag, and
Android turns the player's state into the controller automatically,
including Bluetooth and Android Auto. The controller appears while a
song plays and stays when you pause; swipe it away when paused to
dismiss it.

Some phones (including several Motorola builds) keep that system
player **out of the notification shade** even while it shows on the
lock screen. For those, MuZic also posts its own **shade player card**
into the notification panel, styled after the lock-screen player:
the track artwork fills the whole card, with the title, artist,
big play/pause button and waveform overlaid on it over a dark
gradient, and the full transport row (shuffle, previous, −10s,
+10s, next, repeat) below, kept in sync with playback. Tap the
waveform to jump to that part of the song (the notification system
offers no drag-scrubbing to apps, so the card seeks by tap). Tap
the card's expand arrow to open the full card; the collapsed strip
is kept slim by Android itself. The two surfaces never fight: the lock screen and Quick
Settings keep the exact system player, the shade shows the MuZic card.
The card posts on its own notification slot, verifies that Android
actually kept it, and steps down to a simpler big-artwork layout
automatically if a device refuses the rich one — so a working card
always lands.

*Settings → Playback*

| Row | What it does |
| --- | --- |
| **Notification access** | Shows Allowed/Blocked. **Allow** asks for the permission; if it is still blocked it opens the system settings page for MuZic. The media player cannot appear without it. |
| **Send a test notification** | Posts a plain notification. If this appears but the media player does not, the problem is playback, not the permission. |
| **Show active notifications** | Lists what Android is currently showing for MuZic (including whether the media player exists). |
| **Media notification health** | Step-by-step check of everything the media player needs (permission, channel, audio service, session). |
| **Allow background playback** | Battery-optimisation exemption. Required on MIUI, ColorOS, FuntouchOS, MagicOS — otherwise the player gets killed a few minutes after you leave the app. |

**If the card does not appear**

1. Settings → Playback → **Send a test notification**. No notification? Fix
   the permission / OEM "hide notifications" setting first.
2. Test notification appears but no card? Tap **Show active notifications**
   while a song plays. No entry = Android dropped it (send us a diagnostics
   report — the app version and icon are logged).
3. Allow **background playback** and re-test after locking the screen once.

---

## 7. Sleep timer

![Sleep timer](img/sleep-timer.svg)

*Settings → Sleep timer → Pause after inactivity* → choose 15, 30, 45, 60, 90,
120 or 180 minutes.

Timeline:

1. Music plays with **no activity** in the app for the chosen duration.
2. A warning notification (**"Still listening?"**) is posted and a banner
   appears above the mini player with an **I'm here** button.
3. If nothing happens for **5 more minutes**, playback **pauses** and a
   "Playback paused" notification is posted.

Anything resets the countdown: tapping/scrolling anywhere in the app, resuming
the app, tapping **I'm here**, or tapping the notification. The timer never
fires while playback is stopped.

---

## 8. Audio effects

*Settings → Audio effects* (applied to the real playback session — they work
with wired and Bluetooth headphones):

| Effect | Notes |
| --- | --- |
| **Virtualizer (surround)** | Stereo widening / virtual surround, strength slider. The closest thing to "spatial audio" this app can offer — Dolby Atmos itself needs an Atmos source and a licensed decoder. |
| **Bass boost** | Low-frequency enhancement, strength slider. |
| **Equalizer** | 10 presets (Normal, Classical, Dance, Flat, Folk, Heavy metal, Hip hop, Jazz, Pop, Rock). |

Changes apply instantly; they are remembered across restarts.

---

## 9. Live visualizer

In the now-playing sheet tap the **waveform icon** — an 18-band visualizer is
drawn from the *actual* audio session (not a fake animation).

Android only exposes the live waveform to apps with microphone access, so the
first tap asks for that permission. If you decline, MuZic tells you instead of
showing a fake visualizer; nothing is ever recorded from the microphone.

---

## 10. Lossless audio

MuZic is honest about lossless: JioSaavn/YouTube do not serve FLAC, so lossless
comes from two places.

**Free FLAC radio** — home → *Lossless radio*:

| Station | Stream |
| --- | --- |
| Radio Paradise — Main Mix | `stream.radioparadise.com/flac` |
| Radio Paradise — Mellow Mix | `…/mellow-flac` |
| Radio Paradise — Rock Mix | `…/rock-flac` |
| Radio Paradise — Global Mix | `…/eclectic-flac` |

These are true 16-bit/44.1 kHz Ogg-FLAC streams. Live streams cannot be
downloaded (the download button is disabled for them).

**Your own files** — *Library → Local →* the **add** button imports
**FLAC, WAV, AIFF or MP3** through the Android document picker. Files are
copied into app storage and play offline at full quality. The quality badge
shows `FLAC (local file)` etc.

---

## 11. Downloads & offline

- Tap the **download** icon on a track to save it for offline playback.
- Downloaded tracks play from local storage automatically (faster, works
  without a connection).
- Saved files live in app-private storage; remove the app and they go with it.
- Downloads are shown in *Library → Downloads*.

---

## 12. Diagnostics (opt-in)

![Diagnostics](img/diagnostics.svg)

**Nothing is recorded unless you turn it on.**

*Settings → Diagnostics →* **Capture diagnostics**, or the master switch at the
top of the Diagnostics screen. Turning it off also **deletes** whatever was
captured.

While capture is on, MuZic records: search and stream-resolution steps with
timings, playback and fallback errors, lyrics lookups, notification/session
events, sleep-timer events, video exports, queue and settings state, and
uncaught errors.

*Diagnostics screen*

| Button | Result |
| --- | --- |
| **Run simulated checks** | Exercises the real pipeline (search → stream URL → CDN reachability → lyrics → YouTube) and shows each step with timing. |
| **Copy report** | Full text report to the clipboard. |
| **Save to Downloads** | `Downloads/MuZic/muzic_diagnostics_<timestamp>.txt` — visible in Files, and attachable in WhatsApp/Gmail. |
| **App storage** | Same report in the app's private documents folder. |
| **Share report** | Android share sheet (WhatsApp, Gmail, Drive…). |

The log list is **live** (`live · N entries`). Tap the flag icon to drop a
marker into the log before you reproduce a problem — that makes the report much
easier to read.

---

## 13. Lyric video export

![Lyric video](img/video.svg)

In the now-playing sheet tap the **film icon**:

1. If the track is not downloaded yet, MuZic downloads it first (needed for the
   audio track).
2. The film icon becomes a **ring with the live percentage** while the video
   renders. No dialog blocks the app — you can keep browsing, search, or close
   the player and the render continues in the background.
3. The same percentage also appears above the mini player, so you never lose
   track of it. Tap either one to open the export sheet.
4. To stop early, tap the percentage and choose **Stop exporting**. The partial
   file is thrown away; nothing half-written reaches your gallery.
5. When it finishes the file is saved to **Movies/MuZic/** (visible in Gallery
   and Files) and a confirmation appears.

The video is 720×720, 24 fps, H.264 + AAC, and contains the cover art, a
waveform, the synced lyrics (current + next line) and a progress bar — ready to
post to WhatsApp Status, Reels or Shorts.

Rendering is far faster than it used to be: audio is copied through instead of
being decoded and re-encoded, and the background layer is painted once instead
of on every frame.

Everything is encoded **on the device**; nothing is uploaded.

Exported videos also appear in **Library → Downloads**, in their own
**Lyric videos** section (with a duration and date badge), separate from your
offline songs. Removing an entry there only clears it from MuZic — the file
stays in Movies/MuZic.

---

## 14. Where MuZic keeps files

| Path | Contents |
| --- | --- |
| `Downloads/MuZic/muzic_diagnostics_*.txt` | Reports you saved to Downloads |
| `Movies/MuZic/*.mp4` | Exported lyric videos |
| App-private storage | Downloaded music, imported local files, library/playlists, settings |

---

## 15. Troubleshooting

| Symptom | Fix |
| --- | --- |
| No media card in the notification shade | Settings → Playback → **Send a test notification**; allow notifications; enable **Allow background playback**; check **Show active notifications**. |
| Card disappears after a while | Battery optimisation (Settings → Playback → Allow background playback) — common on Xiaomi/OPPO/vivo. |
| Card disappears when paused | **Keep notification when paused** is on by default; re-enable it in Settings → Playback. |
| "Could not start playback" | Try the other source (JioSaavn/YouTube) — some regional tracks are missing from one of them. |
| A track will not play but others do | Long-press the row → details; if the stream host is `googlevideo.com` the cached URL expired — play the track again to refresh it. |
| Lyrics missing | Not every track has a licensed lyric source. The language sheet shows what is available; Romanized is generated when the original script exists. |
| Video export fails | Enable diagnostics, retry, then **Share report** — the `video` log lines name the failing stage/codec. |
| App feels slow after months of use | Clear the diagnostics log and remove downloads you no longer need (Library → Downloads). |
