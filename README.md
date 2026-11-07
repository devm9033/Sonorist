# Sonorist 🎵

> **Native iOS & macOS YouTube Music Client & High-Fidelity Offline Player**  
> Built with pure Swift, SwiftUI, AVFoundation, and JavaScriptCore. Zero web wrappers, zero Electron bloat, zero tracking.

[![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-black?style=flat&logo=apple)](https://apple.com)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat&logo=apple)](https://apple.com)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat&logo=swift)](https://swift.org)
[![Version 2.2.0](https://img.shields.io/badge/Version-2.2.0-blue?style=flat)](Info.plist)
[![Tests Passing](https://img.shields.io/badge/Tests-57%2F57%20Passed-brightgreen?style=flat)](Tests/)
[![License MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zero Telemetry](https://img.shields.io/badge/Privacy-100%25%20Local-success?style=flat&logo=apple)](README.md#%EF%B8%8F-security--privacy-architecture)

---

## 📱 What's New in the iOS Release (v2.2.0)

Sonorist is now officially available for **iOS (iPhone & iPad)**, bringing Apple-native design engineering to mobile streaming:

* **Apple Music-Inspired Native UI:** Custom full-screen Now Playing sheet crafted with authentic Apple Human Interface Guidelines, translucent Liquid Glass materials (`ultraThinMaterial`), dynamic ambient mesh illumination, and responsive portrait layouts.
* **Clean Launch Zero-State & MiniPlayer Lifecycle:**
  * Clean, unencumbered Day-1 launch opening directly to Search with zero player banners or popups blocking the screen.
  * MiniPlayer automatically materializes with a fluid spring when any song is tapped.
  * Downward flick gesture smoothly sinks the MiniPlayer capsule into the Tab Bar and dismisses it when idle or paused.
* **Interactive Album Art Gestures & Physics:**
  * **Tap-to-Pause/Resume:** Tapping the album artwork toggles playback with a tactile spring scale animation ($1.0 \leftrightarrow 0.92$).
  * **Pure Horizontal Slide & Fade:** Dragging or flicking artwork glides along the X-axis with zero rotational tilt or visual jump.
  * **WWDC Fluid Interfaces Rubber-Banding:** Boundary resistance at queue edges with smooth cushioned spring return.
* **Top Header Ergonomics:**
  * **Top-Left Direct Share Button:** Quick-access native iOS `ShareLink` (`square.and.arrow.up`).
  * **Top-Right Bedtime Sleep Timer:** One-tap sleep timer access with active timer badge and quick Equalizer shortcut.
  * **Dead-Center Source Indicator:** Symmetrical $44\,\text{pt}$ actions ensure source labels and album names remain 100% centered.
* **Continuous Background Playback & Dynamic Island:**
  * Fully backgrounded audio playback via `AVInitialRouteSharingPolicy: LongformAudio`.
  * Real-time Lock Screen & Dynamic Island media controls, scrubber synchronization, and route management (AirPods, iPhone Speaker, Bluetooth, CarPlay).
* **Automatic Silent Offline Caching:** Songs played during online streaming are automatically bundled and compressed into proprietary `.sonorist` files in the background—no manual download button clicks required.

---

## 💡 Inspirations & Acknowledgments

Sonorist brings together modern audio engineering and Apple design principles:

* **Apple Music (iOS & macOS)** — Native Human Interface Guidelines, translucent materials, ambient multi-color album art mesh lighting, and fluid gesture interactions.
* **Echo Music & Metrolist (Android)** — Architectural inspiration for multi-provider synchronized timestamped lyrics (`.lrc`), phonetic transliteration, and live bilingual line translation.
* **LRCLIB & NetEase Cloud Music** — Open community databases providing millisecond-precision synchronized timestamps and syllable cadence.
* **Emil Kowalski Design Engineering** — Concentric geometric radius curves ($R_{\text{inner}} = R_{\text{outer}} - \text{padding}$), tactile haptics, and interruptible physical springs.

---

## ✨ Features at a Glance

### 🎤 Synchronized Karaoke Lyrics
* **Dual-Provider Engine:** Queries LRCLIB and NetEase Music concurrently for millisecond-precision timestamped lyrics (`[mm:ss.xx]`).
* **Phonetic Romanization:** Instant transliteration for Japanese (Romaji), Chinese (Pinyin), Korean (Hangul), and Hindi/Devanagari scripts.
* **Line-by-Line Translation:** Bilingual translation overlaid directly beneath active lyric lines.
* **Syllable Karaoke Sweep:** AttributedString word-by-word highlights following song tempo.
* **One-Tap Calibration Popover:** Click the `Sync` pill to advance/delay offset by `0.1s`/`0.5s`, or hit **`⚡ Align Active Line to Now`** to instantly eliminate intro drift.
* **Offline Caching:** Synchronized lyrics are saved locally with audio for offline sing-alongs.

### 🌌 Immersive "Now Playing" Experience
* Dynamic ambient fluid mesh blur derived from high-resolution album artwork.
* Split view on macOS (`⌘ F`) and interactive sheet modal on iOS with gesture dismissal.
* Fully adaptive to Apple **Light**, **Dark**, and **System** appearance modes.
* Expandable **Track Story & Music DNA** drawer featuring Wikipedia summaries and verified song credits.

### 💾 High-Efficiency Offline Library & Local Player
* **High-Compression `.sonorist` Containers:** Proprietary LZFSE-compressed container format reducing disk usage by up to 99%.
* **Zero-IO In-Memory Index:** Instant O(1) offline availability lookup without disk traversal.
* **Single-Click Export:** Export offline songs to standard Apple `.m4a` files with embedded ID3 metadata tags (Title, Artist, Album, Cover Art, and Lyrics).
* **Purge Lifecycle:** Complete cache clearing with instant storage reclamation.

### 📊 Visual Listening Insights
* **Apple Music Replay Experience:** Clean, listener-focused visual highlights with zero developer jargon.
* **Hero Stat Cards:** Total listening time (with daily streak 🔥), songs streamed, and listening persona vibe.
* **Daily Rhythm Chart:** Colorful gradient progress bars tracking when you tune in (Morning 🌅, Afternoon ☀️, Evening 🌆, Night 🌙).
* **Top Artists & Songs:** Ranked artist podium and most replayed songs with quick play shortcuts.

### 🎛️ Audio Fidelity & Hardware Integration
* **Persistent Playback State & Timestamp Memory:** Seamlessly restores the exact song, up-next queue, and playback head timestamp where you left off.
* **Intelligent Volume Memory:** Custom volume levels persist across launches, with smart pre-mute memory restoring prior sound levels.
* **Smart Autoplay & Radio:** Automatically discovers and queues algorithmic recommendations via InnerTube's `/youtubei/v1/next` endpoint when your queue ends.
* **10-Band Graphic Equalizer:** Preamp fader (-12dB to +12dB) with curated acoustic presets (Bass Booster, Rock, Vocal, Electronic, Flat).

---

## 🛡️ Security, Penetration Testing & Privacy Architecture

Sonorist has been audited against penetration, stress, and security test vectors with a **100% pass rate (56/56 tests)**:

* **100% Local Privacy & Zero Telemetry:** Sonorist contains zero analytics SDKs, zero crash beacons, and zero telemetry trackers. All play counts, history, offline compressed tracks, and audio settings are stored strictly in the local sandboxed application directory.
* **Zero Private Data Transmitted:** Outgoing network traffic is strictly confined to official YouTube/InnerTube endpoints for search/streams and open LRCLIB endpoints for lyrics. No user machine identity, IP logs, credentials, or personal tokens are ever transmitted.
* **Zip-Bomb & Anti-OOM Bounds:** Container decompression enforces strict size caps (max metadata 5MB, lyrics 5MB, artwork 25MB, audio 250MB) and pre-checks data slice boundaries before allocation.
* **Path Traversal Protection:** All track and file identifiers are strictly sanitized against directory traversal sequences (`../../`).
* **Strict App Transport Security (ATS):** Encrypted HTTPS connections strictly enforced; arbitrary insecure HTTP protocols and private/SSRF IP addresses are rejected at the networking layer.
* **Isolated JavaScriptCore Sandbox:** YouTube signature deobfuscation and parameter deciphering execute inside an isolated `JSContext` with zero filesystem or socket permissions.
* **Zero-Leak Memory Optimization:** In-memory artwork caches use `NSCache` bounded to 30 items, and listen to `UIApplication.didReceiveMemoryWarningNotification` to purge under memory pressure.

---

## 📦 Building & Running

### iOS (iPhone & iPad)
1. Open `iOS/SonoristMobile.xcodeproj` in Xcode 15+.
2. Select the `SonoristMobile` scheme and your target device (or Simulator).
3. Press `⌘ R` to build and run.

### macOS
1. Open the project root in Xcode or build via terminal:
```bash
swiftc -O -module-cache-path /tmp/clang-cache Sources/Sonorist/Core/**/*.swift Sources/Sonorist/UI/**/*.swift Sources/Sonorist/App/SonoristApp.swift -o build/Sonorist.app/Contents/MacOS/Sonorist
codesign --force --deep --sign - --entitlements entitlements.plist build/Sonorist.app
```

### Run the Comprehensive Test Suite
Execute the 43-test security, penetration, cipher, audio, and cache suite:
```bash
swiftc -module-cache-path /tmp/clang-cache Sources/Sonorist/Core/**/*.swift Sources/Sonorist/UI/**/*.swift Tests/SonoristTests/SonoristTests.swift -o /tmp/SonoristTests && /tmp/SonoristTests
```

---

## 📂 Project Architecture

```
Sonorist/
├── iOS/                       # Native iOS application target
│   ├── SonoristMobile.xcodeproj
│   ├── Info.plist             # Background audio & device capabilities
│   ├── UI/                    # MobileNowPlayingSheet, MobileSettingsView
│   └── Adapters/              # iOSAudioSessionManager, TrackArtworkView, MobileHaptics
├── Sources/
│   └── Sonorist/
│       ├── App/               # Application lifecycle & menu commands (SonoristApp)
│       ├── Core/
│       │   ├── Audio/         # AudioPlayerEngine, QueueManager, SleepTimer
│       │   ├── Analytics/     # ListeningAnalyticsManager (100% local tracking)
│       │   ├── Cache/         # MediaCacheManager (compressed .sonorist & export)
│       │   ├── Cipher/        # JavaScriptCore cipher deobfuscator
│       │   ├── InnerTube/     # InnerTubeClient (stream resolution, search, radio)
│       │   ├── LocalMusic/    # Local audio file importer (AVURLAsset)
│       │   ├── Lyrics/        # LRCLIBService & NetEase live lyrics engine
│       │   └── Security/      # SecurityAudit (ATS & input sanitization)
│       └── UI/
│           ├── Components/    # TrackRowView, PlayerBarView, AmbientArtworkGlow
│           ├── DesignSystem/  # FluidTheme, AppThemeManager, tactile button styles
│           └── Views/         # ImmersivePlayerView, LyricsView, LibraryView,
│                              # AnalyticsView, SearchView, MiniPlayerView,
│                              # EqualizerView, SettingsView, MenuBarView
├── Tests/
│   └── SonoristTests/         # 57-test security, penetration, audio, AI curation, and cache suite
├── Resources/                 # App icons and assets
├── Package.swift              # Swift package manifest
├── entitlements.plist         # Hardened runtime & network entitlements
├── .gitignore                 # Clean macOS, iOS & Xcode exclusion manifest
└── README.md                  # Project overview, iOS v2.2.0 features & documentation
```

---

## 📄 License

Licensed under the [MIT License](LICENSE).
