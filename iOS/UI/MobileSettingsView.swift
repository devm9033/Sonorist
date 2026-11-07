import SwiftUI

import SwiftUI

@MainActor
public final class MobileSettingsModel: ObservableObject {
    public static let shared = MobileSettingsModel()
    @Published public var showClearCacheAlert: Bool = false
    @Published public var cacheSizeText: String = "Calculating..."
    @Published public var cacheSizeBytes: Int64 = 0
    @Published public var storageLimitGB: Double = 5.0
    @Published public var showEqualizerSheet: Bool = false
    
    public init() {
        self.storageLimitGB = MediaCacheManager.shared.maxStorageLimitGB
    }
}

/// Comprehensive iOS Settings View conforming to Apple Human Interface Guidelines
public struct MobileSettingsView: View {
    @ObservedObject private var themeManager = AppThemeManager.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var model = MobileSettingsModel.shared
    @Environment(\.dismiss) private var dismiss
    
    private let isPresentedAsSheet: Bool
    
    public init(isPresentedAsSheet: Bool = false) {
        self.isPresentedAsSheet = isPresentedAsSheet
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Appearance & Theme Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose how Sonorist looks on your device.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            ForEach(AppThemeMode.allCases) { mode in
                                let isSelected = themeManager.currentTheme == mode
                                Button {
                                    themeManager.setTheme(mode)
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 22, weight: .semibold))
                                        
                                        Text(mode.displayName)
                                            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                    }
                                    .foregroundColor(isSelected ? FluidTheme.musicRed : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(isSelected ? FluidTheme.musicRed.opacity(0.12) : Color.primary.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("APPEARANCE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                } footer: {
                    Text("When set to System, Sonorist automatically adapts to your iOS Light or Dark mode setting.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Streaming Audio Quality Section
                Section {
                    Picker("Streaming Quality", selection: $player.selectedAudioQuality) {
                        Text("Standard (AAC 128k)").tag(AudioQuality.standard)
                        Text("High-Res (Opus 160k)").tag(AudioQuality.high)
                        Text("Data Saver (AAC 48k)").tag(AudioQuality.dataSaver)
                    }
                    .pickerStyle(.menu)
                    .tint(FluidTheme.musicRed)
                    .onChange(of: player.selectedAudioQuality) { _, newQuality in
                        player.switchQuality(to: newQuality)
                    }
                } header: {
                    Text("AUDIO STREAMING")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Higher quality streams deliver richer acoustic fidelity but use more cellular data.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Playback & Automation Section
                Section {
                    // Apple Music Crossfade Toggle & Duration Slider
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Crossfade Songs", isOn: $player.isCrossfadeEnabled)
                            .tint(FluidTheme.musicRed)
                            .onChange(of: player.isCrossfadeEnabled) { _, _ in
                                MobileHaptics.trigger(.selection)
                            }
                        
                        if player.isCrossfadeEnabled {
                            HStack {
                                Text("Transition Duration")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(player.crossfadeDuration))s")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(FluidTheme.musicRed)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(FluidTheme.musicRed.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            
                            Slider(
                                value: $player.crossfadeDuration,
                                in: 1...12,
                                step: 1
                            )
                            .tint(FluidTheme.musicRed)
                            .onChange(of: player.crossfadeDuration) { oldVal, newVal in
                                if oldVal != newVal {
                                    MobileHaptics.trigger(.selection)
                                }
                            }
                            
                            HStack {
                                Text("1s")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("4s (Default)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("12s")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Autoplay Similar Music", isOn: $player.isAutoplayEnabled)
                        .tint(FluidTheme.musicRed)
                    
                    Toggle("Normalize Volume (Sound Check)", isOn: $player.isAudioNormalized)
                        .tint(FluidTheme.musicRed)
                } header: {
                    Text("PLAYBACK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Crossfade smoothly transitions between songs by fading out the current track while fading in the next.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Equalizer & Acoustic Profiles Section
                Section {
                    Toggle("Equalizer Active", isOn: $player.isEqualizerEnabled)
                        .tint(FluidTheme.musicRed)
                        .onChange(of: player.isEqualizerEnabled) { _, _ in
                            MobileHaptics.trigger(.selection)
                        }
                    
                    Picker("Acoustic Preset", selection: $player.equalizerPreset) {
                        ForEach(["Flat", "Acoustic", "Bass Booster", "Bass Reducer", "Classical", "Electronic", "Hip-Hop", "Jazz", "Pop", "Rock", "Vocal Booster"], id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FluidTheme.musicRed)
                    .onChange(of: player.equalizerPreset) { _, newPreset in
                        player.setEqualizerPreset(newPreset)
                    }
                    
                    Button {
                        MobileHaptics.trigger(.selection)
                        model.showEqualizerSheet = true
                    } label: {
                        HStack {
                            Label("10-Band Graphic Mixer", systemImage: "slider.vertical.3")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(player.equalizerPreset)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(FluidTheme.musicRed)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("AUDIO TUNING & EQUALIZER")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Fine-tune acoustics across 10 discrete frequency bands from 32 Hz sub-bass to 16 kHz air.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // MARK: - Storage & Cache Section
                Section {
                    // 1. Used vs Limit summary
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Offline Storage Limit")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(Int(model.storageLimitGB)) GB")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(FluidTheme.musicRed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(FluidTheme.musicRed.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        // Stepped drag slider (1GB to 10GB with haptics)
                        Slider(
                            value: $model.storageLimitGB,
                            in: 1...10,
                            step: 1
                        )
                        .tint(FluidTheme.musicRed)
                        .onChange(of: model.storageLimitGB) { oldVal, newVal in
                            if oldVal != newVal {
                                MobileHaptics.trigger(.selection)
                                MediaCacheManager.shared.maxStorageLimitGB = newVal
                            }
                        }
                        
                        // Slider Range Marks
                        HStack {
                            Text("1 GB")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("5 GB")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("10 GB")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // 2. Storage Usage Progress Bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Storage Used")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(model.cacheSizeText) of \(Int(model.storageLimitGB)) GB")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        GeometryReader { barGeo in
                            let limitBytes = max(1, Int64(model.storageLimitGB * 1024 * 1024 * 1024))
                            let ratio = min(1.0, max(0.0, Double(model.cacheSizeBytes) / Double(limitBytes)))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 7)
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [FluidTheme.musicRed, FluidTheme.musicRed.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(7, barGeo.size.width * CGFloat(ratio)), height: 7)
                            }
                        }
                        .frame(height: 7)
                    }
                    .padding(.vertical, 4)
                    
                    // 3. Clear Music Cache Button
                    Button(role: .destructive) {
                        MobileHaptics.trigger(.medium)
                        model.showClearCacheAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                            Text("Clear Music Cache")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                } header: {
                    Text("STORAGE & DOWNLOADS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Sonorist will automatically manage offline music bundles to stay within your \(Int(model.storageLimitGB)) GB storage budget.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // MARK: - About Section
                Section {
                    HStack {
                        Text("Sonorist for iOS")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("v1.0.0 (Build 24)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Audio Architecture")
                        Spacer()
                        Text("Pure AVFoundation Native")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("ABOUT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .toolbar {
                if isPresentedAsSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .alert("Clear Music Cache?", isPresented: $model.showClearCacheAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("This will remove all downloaded offline songs and temporary stream buffers.")
            }
            .onAppear {
                calculateCacheSize()
            }
            .sheet(isPresented: $model.showEqualizerSheet) {
                MobileEqualizerSheet()
                    .preferredColorScheme(themeManager.currentTheme.colorScheme)
                    .presentationDetents([.fraction(0.85), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
    }
    
    // MARK: - Cache Helpers
    
    private func calculateCacheSize() {
        let model = self.model
        Task.detached(priority: .utility) {
            let cache = MediaCacheManager.shared
            var bytes: Int64 = 0
            
            for dir in [cache.libraryDirectory, cache.playbackTempDirectory, cache.artworkDirectory] {
                if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
                    for fileURL in files {
                        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            bytes += Int64(size)
                        }
                    }
                }
            }
            
            let finalBytes = bytes
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            let formatted = formatter.string(fromByteCount: finalBytes)
            
            await MainActor.run {
                model.cacheSizeBytes = finalBytes
                model.cacheSizeText = formatted
            }
        }
    }
    
    private func clearCache() {
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                AudioPlayerEngine.shared.clearAllOfflineDownloads()
                MobileToastManager.shared.show(message: "Library & Cache Cleared", icon: "trash")
            }
            await self.calculateCacheSize()
        }
    }
}
