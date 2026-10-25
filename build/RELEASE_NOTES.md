# Sonorist v2.1.0 🎵

**Sonorist** is a native, high-fidelity YouTube Music client and offline audio player for macOS, built with pure Swift, SwiftUI, AVFoundation, and JavaScriptCore. Zero web wrappers, zero Electron overhead.

---

## What's New in v2.1.0

### 💾 Seamless Session State & Playback Memory
* **Timestamp & Queue Restoration:** When closed and reopened, Sonorist restores the exact song, current playback head position, and up-next queue where you left off.
* **Smart Tab Memory:** Reopens to your last viewed section (Search, Library, or Analytics). First-time launches land on Search.

### 🔊 Intelligent Volume Persistence
* Custom volume levels persist across app launches.
* Features smart pre-mute memory: unmuting restores your exact prior listening volume rather than an arbitrary default.

### 📐 Apple HIG Window & Pane Geometry
* **Rock-Solid Pane Stability:** Fixed sidebar icon shifting and player bar stretching during navigation between Search, Library, and Analytics.
* **Layout Containment:** Child views enforce flexible boundaries so internal content never pushes against the $210\text{ pt}$ sidebar or mutates window dimensions.

### 🎛️ Redesigned Compact Player HUD
* **Distinct Functional Grouping:** Enforces Apple HIG separation between primary Playback Transport (`Shuffle`, `Previous`, `Play`, `Next`, `Repeat`) and Auxiliary Utilities (`Lyrics`, `Queue`, `Fullscreen`, `Sleep Timer`, `Volume`).
* **Spacious Margin:** In the most minimized window size ($760\times 560\text{ pt}$), the Repeat button and Lyrics button maintain over $55\text{ pt}$ of clean breathing room, eliminating cramped controls.

### 🎨 Official macOS Application Icon
* Custom 1024×1024 multi-resolution Retina icon (`AppIcon.icns`) designed in accordance with Apple macOS icon guidelines.
* Features a vibrant Apple Music crimson gradient squircle, concentric acoustic soundwave resonance rings, and a glossy beamed double-note emblem.

### 🔒 100% Local Privacy & Zero Telemetry
* **No Telemetry / No Tracking:** Zero analytics SDKs, zero user identifiers, zero background telemetry.
* **Strict Storage Boundary:** Audio cache, likes, play history, and listening insights are saved 100% locally in `~/Library/Application Support/Sonorist/`.
* **Zero Secrets Sent:** Requests are strictly limited to official YouTube/InnerTube endpoints and open LRCLIB lyrics APIs.

### ⚡ Performance & Resource Consumption Optimization
* **View-Tree Invalidation Decoupling:** Isolated high-frequency playback position updates to `PlaybackProgressTracker`. Playback ticks no longer invalidate `MainContentView`, `SidebarView`, `SearchView`, `LibraryView`, `AnalyticsView`, or list rows, dropping idle playback CPU usage.
* **99% Disk I/O Reduction:** Replaced per-tick `UserDefaults` writes with an intelligent 15-second batch aggregator and state-flush triggers. Disk writes dropped from ~400 writes/minute to ~4 writes/minute, eliminating thermal and battery drain.
* **Optimized Audio Clock Wakeups:** Tuned AVPlayer periodic time observation from 150ms to 250ms, cutting timer wakeups by 40% while preserving sub-frame scrubbing smoothness and synchronized lyric alignment.
* **In-Memory Query & Metadata Caching:** 5-minute TTL LRU search caching in `InnerTubeClient` eliminates redundant network round-trips and JSON deserialization overhead during repeated searches.
* **Whole-Module Compiler Optimization (`-O -wmo -dead_strip`):** Stripped unused symbols and enabled cross-file inlining for lightning-fast launch and minimal memory footprint.

---

## 📦 Downloads & Checksums

| Asset | Format | Size | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| **`Sonorist-v2.1.0-macOS.dmg`** | Apple Disk Image (Drag & Drop) | ~2.6 MB | `c6a7fbeefad670e684cd90d5811369e3500f80b57103231a7a122fd492c94eb9` |
| **`Sonorist-v2.1.0-macOS.zip`** | Signed App Bundle Archive | ~2.2 MB | `c2bd96c1d7d5545d4e50f5dcfdde60eea9794ede44db2e895112648e68f044bf` |

### Installation Instructions
1. Download **`Sonorist-v2.1.0-macOS.dmg`**.
2. Double-click to mount the disk image.
3. Drag **Sonorist** into your **Applications** folder.
4. Launch Sonorist from Spotlight (`⌘ Space`) or Launchpad.

---

### System Requirements
* **macOS 14.0 (Sonoma)** or later (including macOS 15+ Sequoia).
* Compatible with Apple Silicon (M1/M2/M3/M4) and Intel Macs.
