# Sonorist 🎵

> **Native macOS YouTube Music Client & High-Fidelity Offline Player**  
> Built with pure Swift, SwiftUI, AVFoundation, and JavaScriptCore. Zero web wrappers, zero Electron bloat.

[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat&logo=apple)](https://apple.com)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat&logo=swift)](https://swift.org)
[![Version 2.1.0](https://img.shields.io/badge/Version-2.1.0-blue?style=flat)](Info.plist)
[![Tests Passing](https://img.shields.io/badge/Tests-38%2F38%20Passed-brightgreen?style=flat)](Tests/)
[![License MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zero Telemetry](https://img.shields.io/badge/Privacy-100%25%20Local-success?style=flat&logo=apple)](README.md#%EF%B8%8F-security--privacy-architecture)

---

## 💡 Inspirations & Acknowledgments

Sonorist brings together the best concepts from modern music engineering and Apple design principles:

* **Apple Music (macOS)** — Native macOS Human Interface Guidelines, translucent Liquid Glass materials (`ultraThinMaterial`, `bar`), ambient multi-color album art mesh lighting, and the full-window Now Playing stage (`⌘ F`).
* **Echo Music & Metrolist (Android)** — Architectural inspiration for multi-provider synchronized timestamped lyrics (`.lrc`), phonetic transliteration, and live bilingual line translation.
* **LRCLIB & NetEase Cloud Music** — Open community databases providing millisecond-precision synchronized timestamps and syllable cadence.
* **Emil Kowalski Design Engineering** — Concentric geometric radius curves ($R_{\text{inner}} = R_{\text{outer}} - \text{padding}$), tactile Force Touch Taptic feedback, and fluid physical springs.

---

## ✨ Features at a Glance

### 🎤 Synchronized Karaoke Lyrics
* **Dual-Provider Engine:** Queries LRCLIB and NetEase Music concurrently for millisecond-precision timestamped lyrics (`[mm:ss.xx]`).
* **Phonetic Romanization:** Instant transliteration for Japanese (Romaji), Chinese (Pinyin), Korean (Hangul), and Hindi/Devanagari scripts.
* **Line-by-Line Translation:** Bilingual translation overlaid directly beneath active lyric lines.
* **Syllable Karaoke Sweep:** AttributedString word-by-word highlights following song tempo.
* **One-Tap Calibration Popover:** Click the `Sync` pill to advance/delay offset by `0.1s`/`0.5s`, or hit **`⚡ Align Active Line to Now`** to instantly eliminate intro drift.
* **Offline Caching:** Synchronized lyrics are saved locally with audio for offline sing-alongs.

### 🌌 Immersive Full-Window "Now Playing" (`⌘ F`)
* Dynamic ambient fluid mesh blur derived from high-resolution album artwork.
* Side-by-side split stage: Album Art & Controls on the left, Rolling Karaoke Lyrics on the right.
* Fully adaptive to macOS **Light (White)**, **Dark**, and **System** appearance modes.
* Expandable **Track Story & Music DNA** drawer featuring Wikipedia summaries and verified YouTube song credits.

### 💾 High-Efficiency Offline Library & Local Player
* **High-Compression `.sonorist` Containers:** Proprietary LZFSE-compressed container format reducing disk usage by up to 99%.
* **Local Audio Player:** Open or drag-and-drop local `.mp3`, `.m4a`, `.flac`, `.wav`, and `.aac` files (`⌘ O`).
* **Single-Click Finder Export:** Export offline songs to standard Apple `.m4a` files with embedded ID3 metadata tags (Title, Artist, Album, Cover Art, and Lyrics).
* **Purge Lifecycle:** Complete cache clearing with instant 0 KB reclamation.

### 📊 Visual Listening Insights
* **Apple Music Replay Experience:** Clean, listener-focused visual highlights with zero developer jargon.
* **3 Hero Stat Cards:** Total listening time (with daily streak 🔥), songs streamed, and listening persona vibe.
* **Daily Rhythm Chart:** Colorful gradient progress bars tracking when you tune in (Morning 🌅, Afternoon ☀️, Evening 🌆, Night 🌙).
* **Top Artists & Songs:** Ranked artist podium and most replayed songs with quick play shortcuts.

### 🎛️ Audio Fidelity & macOS Hardware Integration
* **Persistent Playback State & Timestamp Memory (v2.1):** When closed and reopened, Sonorist seamlessly restores the exact song, up-next queue, and playback head timestamp where you left off.
* **Intelligent Volume Memory (v2.1):** Custom volume levels persist across launches, with smart pre-mute memory restoring prior sound levels rather than a generic default.
* **10-Band Graphic Equalizer (`⌥ ⌘ E`):** Preamp fader (-12dB to +12dB) with curated acoustic presets (Bass Booster, Rock, Vocal, Electronic, Flat).
* **Smart Autoplay & Radio:** Automatically discovers and queues algorithmic recommendations via InnerTube's `/youtubei/v1/next` endpoint when your playlist ends.
* **Sleep Timer:** 15m, 30m, 45m, 1h, or "End of Current Song" presets with a smooth 5-second volume fade-out.
* **MiniPlayer (`⌘ M`):** Compact floating glass card for unobtrusive desktop listening.
* **Menu Bar Companion:** Global menu bar extra for quick control without switching spaces.

---

## 🛡️ Security & Privacy Architecture

* **100% Local Privacy & Zero Telemetry:** Sonorist contains zero analytics SDKs, zero crash beacons, and zero telemetry trackers. All likes, play counts, history, offline compressed tracks, and audio settings are stored strictly on your local Mac in `~/Library/Application Support/Sonorist/`.
* **Zero Private Data Transmitted:** Outgoing network traffic is strictly confined to official YouTube/InnerTube endpoints for search/streams and open LRCLIB endpoints for lyrics. No user machine identity, IP logs, credentials, or personal tokens are ever transmitted.
* **Strict App Transport Security (ATS):** Encrypted HTTPS connections strictly enforced; arbitrary insecure HTTP protocols are rejected at the networking layer.
* **Isolated JavaScriptCore Sandbox:** YouTube signature deobfuscation and parameter deciphering execute inside an isolated `JSContext` with zero filesystem or socket permissions.

---

## 📦 GitHub Release & Installation

Pre-built binaries are available in [`build/`](build/) or on the GitHub Releases page:

| Format | File | Recommended For |
| :--- | :--- | :--- |
| **Disk Image (.dmg)** | `build/Sonorist-v2.1.0-macOS.dmg` | Standard drag-and-drop macOS install |
| **Zip Bundle (.zip)** | `build/Sonorist-v2.1.0-macOS.zip` | Direct extraction to `/Applications` |

### Run the Verification Suite
Execute the 38-test comprehensive verification suite:
```bash
swiftc -module-cache-path /tmp/clang-cache Sources/Sonorist/Core/**/*.swift Sources/Sonorist/UI/**/*.swift Tests/SonoristTests/SonoristTests.swift -o /tmp/SonoristTests && /tmp/SonoristTests
```

### Recompile Release Binary
```bash
swiftc -O -module-cache-path /tmp/clang-cache Sources/Sonorist/Core/**/*.swift Sources/Sonorist/UI/**/*.swift Sources/Sonorist/App/SonoristApp.swift -o build/Sonorist.app/Contents/MacOS/Sonorist
codesign --force --deep --sign - --entitlements entitlements.plist build/Sonorist.app
```

---

## 📂 Project Architecture

```
Sonorist/
├── build/                     # Release packages & application bundle
│   ├── Sonorist.app/          # Code-signed macOS application bundle with AppIcon.icns
│   ├── Sonorist-v2.1.0-macOS.dmg
│   ├── Sonorist-v2.1.0-macOS.zip
│   ├── SHA256SUMS.txt
│   └── RELEASE_NOTES.md
├── Resources/                 # App icons (AppIcon.icns, AppIcon.png)
├── Package.swift              # Swift package manifest
├── entitlements.plist         # Hardened runtime & network entitlements
├── .gitignore                 # Clean macOS & Xcode exclusion manifest
├── README.md                  # Project overview, features & documentation
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
└── Tests/
    └── SonoristTests/         # 38-test security, cipher, audio, and cache suite
```

---

## 📄 License

Licensed under the [MIT License](LICENSE).
