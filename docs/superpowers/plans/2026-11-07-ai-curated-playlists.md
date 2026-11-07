# AI Curated Playlists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an intelligent, Apple-native AI Playlist curation system for Sonorist that automatically clusters offline downloaded tracks into clean Language and Genre folders (max 5 genres per language), with automatic background curation upon download and daily auto-sync.

**Architecture:** 
- A dedicated `AIPlaylistEngine` manages communication with LLM APIs (Google Gemini, Groq Llama 3, OpenAI, or Local Ollama) using structured JSON output.
- Taxonomies are capped at 5 primary genres per language (e.g. Pop & Dance, Melodic & Romance, Acoustic & Chill, Classical & Heritage, Rock & Energetic) to keep navigation clean and Apple HIG compliant.
- `MediaCacheManager` triggers silent background classification on download completion.
- Playlists are persisted locally in `AICuratedPlaylists.json` for 100% offline playback.
- UI features folder-drilldown in Library, zero-state onboarding, and Keychain-backed API configuration in Settings.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation (URLSession, Codable), Security (Keychain / sandboxed storage), AVFoundation.

---

## Tasks

- [ ] Task 1: Create Data Models and Persistence (`AIPlaylistModel.swift`)
- [ ] Task 2: Build Secure Configuration & Provider Client (`AIProviderConfig.swift`, `AIPlaylistEngine.swift`)
- [ ] Task 3: Implement Background Download Hook and Daily Auto-Sync (`MediaCacheManager.swift` integration)
- [ ] Task 4: Build Native SwiftUI UI Views (`AICuratedPlaylistsView.swift` with Folder Hierarchy & Zero-State)
- [ ] Task 5: Integrate into Mobile Library and Settings Views (`MobileLibraryView.swift`, `SettingsView.swift`)
- [ ] Task 6: Add Comprehensive Automated Unit Tests & Verification (Tests 54, 55, 56)
- [ ] Task 7: Build, Run on Simulator, Capture Visual Verification Screenshots, and Clean Up
