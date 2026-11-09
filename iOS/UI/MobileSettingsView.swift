import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class MobileSettingsModel: ObservableObject {
    public static let shared = MobileSettingsModel()
    @Published public var showClearCacheAlert: Bool = false
    @Published public var showClearArtworkAlert: Bool = false
    @Published public var showResetListeningAlert: Bool = false
    @Published public var cacheSizeText: String = "Calculating..."
    @Published public var artworkCacheSizeText: String = "Calculating..."
    @Published public var cacheSizeBytes: Int64 = 0
    @Published public var storageLimitGB: Double = 5.0
    @Published public var showEqualizerSheet: Bool = false
    
    // Backup & Restore
    @Published public var showBackupDialog: Bool = false
    @Published public var showFileImporter: Bool = false
    @Published public var isExportingBackup: Bool = false
    @Published public var isImportingBackup: Bool = false
    @Published public var exportedBackupURL: URL? = nil
    @Published public var showShareSheet: Bool = false
    @Published public var settingsBackupSizeText: String = "~64 KB"
    @Published public var songsBackupSizeText: String = "0 MB"
    
    // Backup & Restore Progress & Completion HUD
    @Published public var showBackupStatusSheet: Bool = false
    @Published public var backupOperationType: String = ""
    @Published public var backupIsCompleted: Bool = false
    @Published public var hasSavedToFile: Bool = false
    @Published public var backupProgress: Double = 0.0
    @Published public var backupCurrentCount: Int = 0
    @Published public var backupTotalCount: Int = 0
    @Published public var backupStatusMessage: String = ""
    @Published public var backupResultTitle: String = ""
    @Published public var backupResultMessage: String = ""
    @Published public var backupFailedError: String? = nil
    
    public init() {
        self.storageLimitGB = MediaCacheManager.shared.maxStorageLimitGB
        updateBackupEstimates()
    }
    
    public func updateBackupEstimates() {
        self.settingsBackupSizeText = SonoristBackupManager.calculateSettingsBackupSize().formatted
        self.songsBackupSizeText = SonoristBackupManager.calculateSongsBackupSize().formatted
    }
    
    public func exportSettingsBackup() {
        showBackupStatusSheet = true
        backupOperationType = "Exporting Playlists & Settings"
        backupIsCompleted = false
        hasSavedToFile = false
        backupFailedError = nil
        backupProgress = 0.1
        backupCurrentCount = 1
        backupTotalCount = 4
        backupStatusMessage = "Starting backup..."
        
        Task {
            do {
                let url = try await SonoristBackupManager.exportSettingsBackup { progress, message, current, total in
                    Task { @MainActor in
                        self.backupProgress = progress
                        self.backupStatusMessage = message
                        self.backupCurrentCount = current
                        self.backupTotalCount = total
                    }
                }
                await MainActor.run {
                    self.backupProgress = 1.0
                    self.backupCurrentCount = 4
                    self.backupTotalCount = 4
                    self.backupStatusMessage = "Packaging completed"
                    self.backupIsCompleted = true
                    self.backupResultTitle = "Settings Backup Ready"
                    self.backupResultMessage = "Playlists, custom subfolders, favorites, and settings exported successfully."
                    self.exportedBackupURL = url
                    MobileHaptics.trigger(.heavy)
                }
            } catch {
                await MainActor.run {
                    self.backupIsCompleted = false
                    self.backupFailedError = error.localizedDescription
                    MobileHaptics.trigger(.error)
                }
            }
        }
    }
    
    public func exportSongsBackup() {
        showBackupStatusSheet = true
        backupOperationType = "Backing Up Songs"
        backupIsCompleted = false
        hasSavedToFile = false
        backupFailedError = nil
        backupProgress = 0.05
        backupCurrentCount = 0
        backupTotalCount = 0
        backupStatusMessage = "Scanning offline library..."
        
        Task {
            do {
                let url = try await SonoristBackupManager.exportSongsBackup { progress, message, current, total in
                    Task { @MainActor in
                        self.backupProgress = progress
                        self.backupStatusMessage = message
                        self.backupCurrentCount = current
                        self.backupTotalCount = total
                    }
                }
                let count = MediaCacheManager.shared.getAllCachedTracks().count
                let size = SonoristBackupManager.calculateSongsBackupSize().formatted
                await MainActor.run {
                    self.backupProgress = 1.0
                    self.backupCurrentCount = count
                    self.backupTotalCount = count
                    self.backupStatusMessage = "Packaging completed"
                    self.backupIsCompleted = true
                    self.backupResultTitle = "Songs Backup Ready"
                    self.backupResultMessage = "\(count) \(count == 1 ? "song" : "songs") packaged into a single \(size) offline file."
                    self.exportedBackupURL = url
                    MobileHaptics.trigger(.heavy)
                }
            } catch {
                await MainActor.run {
                    self.backupIsCompleted = false
                    self.backupFailedError = error.localizedDescription
                    MobileHaptics.trigger(.error)
                }
            }
        }
    }
    
    public func exportBackup(includeAudio: Bool) {
        if includeAudio {
            exportSongsBackup()
        } else {
            exportSettingsBackup()
        }
    }
    
    public func importBackup(from url: URL) {
        showBackupStatusSheet = true
        backupOperationType = "Restoring Backup"
        backupIsCompleted = false
        hasSavedToFile = false
        backupFailedError = nil
        backupProgress = 0.05
        backupCurrentCount = 0
        backupTotalCount = 0
        backupStatusMessage = "Opening backup package..."
        exportedBackupURL = nil
        
        Task {
            do {
                let summary = try await SonoristBackupManager.importBackup(from: url) { progress, message, current, total in
                    Task { @MainActor in
                        self.backupProgress = progress
                        self.backupStatusMessage = message
                        self.backupCurrentCount = current
                        self.backupTotalCount = total
                    }
                }
                await MainActor.run {
                    self.backupProgress = 1.0
                    self.backupStatusMessage = "Completed"
                    self.backupIsCompleted = true
                    self.backupResultTitle = "Restore Completed!"
                    let totalSongs = summary.audioRestoredCount + summary.audioAlreadyPresentCount
                    if totalSongs > 0 && summary.playlistCount == 0 {
                        if summary.audioRestoredCount > 0 && summary.audioAlreadyPresentCount > 0 {
                            self.backupResultMessage = "Out of \(totalSongs) songs, \(summary.audioRestoredCount) restored and \(summary.audioAlreadyPresentCount) already present in your library."
                        } else if summary.audioRestoredCount == 0 && summary.audioAlreadyPresentCount > 0 {
                            self.backupResultMessage = "All \(summary.audioAlreadyPresentCount) \(summary.audioAlreadyPresentCount == 1 ? "song was" : "songs were") already present in your library. Nothing was overwritten."
                        } else {
                            self.backupResultMessage = "Successfully restored \(summary.audioRestoredCount) \(summary.audioRestoredCount == 1 ? "song" : "songs") to your offline library."
                        }
                    } else if totalSongs > 0 {
                        if summary.audioAlreadyPresentCount > 0 && summary.audioRestoredCount > 0 {
                            self.backupResultMessage = "Restored \(summary.playlistCount) playlists. Out of \(totalSongs) songs, \(summary.audioRestoredCount) restored and \(summary.audioAlreadyPresentCount) already present."
                        } else if summary.audioRestoredCount == 0 && summary.audioAlreadyPresentCount > 0 {
                            self.backupResultMessage = "Restored \(summary.playlistCount) playlists. All \(summary.audioAlreadyPresentCount) songs were already present."
                        } else {
                            self.backupResultMessage = "Successfully restored \(summary.audioRestoredCount) offline songs and \(summary.playlistCount) playlists."
                        }
                    } else {
                        self.backupResultMessage = "Successfully restored \(summary.playlistCount) playlists, favorites, and preferences."
                    }
                    MobileLibraryModel.shared.loadOfflineTracks()
                    AIPlaylistEngine.shared.reconcileWithCachedTracks()
                    self.updateBackupEstimates()
                    MobileHaptics.trigger(.heavy)
                }
            } catch {
                await MainActor.run {
                    self.backupIsCompleted = false
                    self.backupFailedError = error.localizedDescription
                    MobileHaptics.trigger(.error)
                }
            }
        }
    }
    
    public func handleShareCompleted(activityType: String?) {
        self.hasSavedToFile = true
        self.backupResultTitle = "Saved to Files!"
        self.backupResultMessage = "Your backup has been safely saved to your iPhone storage."
        MobileHaptics.trigger(.heavy)
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
        VStack(spacing: 0) {
            // Compact Native Sheet Header (Aligns Settings and Done on the same horizontal row with zero dead gap)
            HStack(alignment: .center) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isPresentedAsSheet {
                    Button {
                        MobileHaptics.trigger(.light)
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
            
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
                            let gigabyteInBytes: Double = 1073741824.0
                            let limitBytes: Double = max(1.0, model.storageLimitGB * gigabyteInBytes)
                            let ratio: Double = min(1.0, max(0.0, Double(model.cacheSizeBytes) / limitBytes))
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
                    
                    // 3. Clear Downloaded Music Button
                    Button(role: .destructive) {
                        MobileHaptics.trigger(.medium)
                        model.showClearCacheAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                            Text("Clear Downloaded Music")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    
                    // 4. Reset Listening History Button
                    Button(role: .destructive) {
                        MobileHaptics.trigger(.medium)
                        model.showResetListeningAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .medium))
                            Text("Reset Listening History")
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
                
                // MARK: - Backup & Data Portability Section
                Section {
                    // 1. Export Backup Button
                    Button {
                        MobileHaptics.trigger(.medium)
                        model.showBackupDialog = true
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Export Backup")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Playlists, settings or offline songs")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "square.and.arrow.up.fill")
                                    .foregroundColor(FluidTheme.musicRed)
                            }
                            Spacer()
                            if model.isExportingBackup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                        }
                    }
                    .disabled(model.isExportingBackup)
                    
                    // 2. Restore from Backup Button
                    Button {
                        MobileHaptics.trigger(.medium)
                        model.showFileImporter = true
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Restore from Backup")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Import from iCloud Drive or Files (.sonorist-backup, .sonorist-songs)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .foregroundColor(.indigo)
                            }
                            Spacer()
                            if model.isImportingBackup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                        }
                    }
                    .disabled(model.isImportingBackup)
                } header: {
                    Text("BACKUP & RESTORE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Playlists and settings backups are lightweight files. Songs backups package your downloaded music files directly without extra storage overhead.")
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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
        }
        .alert("Clear Downloaded Music?", isPresented: $model.showClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearCache()
            }
        } message: {
            Text("This will remove all downloaded offline songs and temporary stream buffers.")
        }
        .alert("Reset Listening History?", isPresented: $model.showResetListeningAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset All", role: .destructive) {
                ListeningAnalyticsManager.shared.resetAll()
                AIInsightsEngine.shared.currentStory = nil
                MobileToastManager.shared.show(message: "Listening history reset to 0 mins", icon: "arrow.counterclockwise")
            }
        } message: {
            Text("Permanently resets all listening streaks, play counts, and insights logs.")
        }
        .onAppear {
            calculateCacheSize()
            model.updateBackupEstimates()
        }
        .sheet(isPresented: $model.showEqualizerSheet) {
            MobileEqualizerSheet()
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .confirmationDialog(
            "Backup Library",
            isPresented: $model.showBackupDialog,
            titleVisibility: .visible
        ) {
            Button("Playlists & Settings (\(model.settingsBackupSizeText))") {
                model.exportSettingsBackup()
            }
            Button("Songs Only (\(model.songsBackupSizeText))") {
                model.exportSongsBackup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select what you would like to export:")
        }
        .fileImporter(
            isPresented: $model.showFileImporter,
            allowedContentTypes: [.data, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.importBackup(from: url)
            case .failure(let error):
                MobileToastManager.shared.show(message: "Failed to open file: \(error.localizedDescription)", icon: "exclamationmark.triangle")
            }
        }
        .sheet(isPresented: $model.showShareSheet) {
            if let url = model.exportedBackupURL {
                #if canImport(UIKit)
                ActivityViewControllerRepresentable(activityItems: [url]) { completed, activityType in
                    if completed {
                        model.handleShareCompleted(activityType: activityType)
                    }
                }
                .presentationDetents([.medium, .large])
                #else
                Text("Exported: \(url.lastPathComponent)")
                    .padding()
                #endif
            }
        }
        .sheet(isPresented: $model.showBackupStatusSheet) {
            BackupProgressSheetView(model: model)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDetents([.fraction(0.48), .medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
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
            
            let artBytes = cache.getArtworkCacheSizeBytes()
            let formattedArt: String
            if artBytes <= 0 {
                formattedArt = "0 KB"
            } else if artBytes < 1024 * 1024 {
                let kb = max(1, artBytes / 1024)
                formattedArt = "\(kb) KB"
            } else {
                let mb = Double(artBytes) / 1048576.0
                formattedArt = String(format: "%.1f MB", mb)
            }
            
            await MainActor.run {
                model.cacheSizeBytes = finalBytes
                model.cacheSizeText = formatted
                model.artworkCacheSizeText = formattedArt
            }
        }
    }
    
    private func clearCache() {
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                AudioPlayerEngine.shared.clearAllOfflineDownloads()
                MobileHaptics.trigger(.heavy)
            }
            await self.calculateCacheSize()
        }
    }
}

#if canImport(UIKit)
struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: ((Bool, String?) -> Void)? = nil
    
    init(activityItems: [Any], onComplete: ((Bool, String?) -> Void)? = nil) {
        self.activityItems = activityItems
        self.onComplete = onComplete
    }
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            onComplete?(completed, activityType?.rawValue)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Backup Progress & Peace-of-Mind Completion Sheet
public struct BackupProgressSheetView: View {
    @ObservedObject var model: MobileSettingsModel
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        VStack(spacing: 18) {
            if let error = model.backupFailedError {
                // Failure State
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.red)
                }
                .padding(.top, 8)
                
                VStack(spacing: 6) {
                    Text("Operation Failed")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                Button("Dismiss") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(FluidTheme.musicRed)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            } else if model.backupIsCompleted {
                // Success State (Peace of mind)
                ZStack {
                    Circle()
                        .fill(FluidTheme.downloadGreen.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(FluidTheme.downloadGreen)
                }
                .padding(.top, 8)
                
                VStack(spacing: 6) {
                    Text(model.backupResultTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    
                    Text(model.backupResultMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                VStack(spacing: 10) {
                    if model.hasSavedToFile {
                        // User saved to iPhone Files! Show clean Apple-style Done confirmation
                        Button {
                            MobileHaptics.trigger(.heavy)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Done")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FluidTheme.downloadGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        
                        Button {
                            MobileHaptics.trigger(.selection)
                            model.showShareSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Share or Save Again")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                        }
                    } else if model.exportedBackupURL != nil {
                        // Exported, ready for user to choose where to save / share
                        Button {
                            MobileHaptics.trigger(.medium)
                            model.showShareSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Save to Files / Share")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FluidTheme.musicRed)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        
                        Button("Done") {
                            MobileHaptics.trigger(.light)
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    } else {
                        // Restore completed
                        Button {
                            MobileHaptics.trigger(.heavy)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Done")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(FluidTheme.downloadGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            } else {
                // Live Progress State with Song Counter & Fluid Loading Bar
                ZStack {
                    Circle()
                        .fill(FluidTheme.musicRed.opacity(0.12))
                        .frame(width: 62, height: 62)
                    Image(systemName: model.backupOperationType.contains("Restor") ? "arrow.down.doc.fill" : "arrow.up.doc.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                }
                .padding(.top, 6)
                
                VStack(spacing: 6) {
                    Text(model.backupOperationType)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    
                    if model.backupTotalCount > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(FluidTheme.musicRed)
                                .frame(width: 6, height: 6)
                            Text("Song \(model.backupCurrentCount) of \(model.backupTotalCount)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(FluidTheme.musicRed)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(FluidTheme.musicRed.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                
                // Fluid Apple-style Progress Bar
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [FluidTheme.musicRed, Color(red: 1.0, green: 0.38, blue: 0.34)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(min(1.0, max(0.02, model.backupProgress)))))
                                .animation(.easeInOut(duration: 0.15), value: model.backupProgress)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(Int(model.backupProgress * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(FluidTheme.musicRed)
                        
                        Spacer()
                        
                        if model.backupTotalCount > 0 {
                            Text("\(model.backupCurrentCount) / \(model.backupTotalCount)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Please keep Sonorist open")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    
                    Text(model.backupStatusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 28)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 20)
        .interactiveDismissDisabled(!model.backupIsCompleted && model.backupFailedError == nil)
    }
}
