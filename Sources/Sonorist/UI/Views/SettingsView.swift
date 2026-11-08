import SwiftUI
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case playback = "Playback"
    case appearance = "Appearance"
    case storage = "Storage"
    case security = "Privacy"
    case general = "Shortcuts"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .playback: return "play.circle.fill"
        case .appearance: return "paintbrush.fill"
        case .storage: return "internaldrive.fill"
        case .security: return "lock.shield.fill"
        case .general: return "command"
        }
    }
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    public static let shared = SettingsViewModel()
    @Published public var selectedTab: SettingsTab = .playback
    @Published public var showPurgeSuccess: Bool = false
    @Published public var showPurgeCacheAlert: Bool = false
    @Published public var showClearHistoryAlert: Bool = false
    public init() {}
}

public struct SettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    @ObservedObject var libraryVM = LibraryViewModel.shared
    @ObservedObject var themeManager = AppThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple Mac Preferences Toolbar Header
            preferencesHeader
            
            Divider()
                .opacity(0.25)
            
            // Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch viewModel.selectedTab {
                    case .playback:
                        playbackContent
                    case .appearance:
                        appearanceContent
                    case .storage:
                        storageContent
                    case .security:
                        securityContent
                    case .general:
                        generalContent
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
        }
        .frame(width: 580, height: 530)
        .background(FluidTheme.barMaterial)
        .onExitCommand { dismiss() }
        .sheet(isPresented: $player.showEqualizerSheet) {
            EqualizerView()
        }
        .alert("Purge Offline Audio Cache?", isPresented: $viewModel.showPurgeCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Purge Cache", role: .destructive) {
                FluidHaptics.toggle()
                withAnimation(FluidTheme.tapSpring) {
                    libraryVM.clearCache()
                    viewModel.showPurgeSuccess = true
                }
            }
        } message: {
            Text("This will permanently remove all downloaded offline tracks (\(libraryVM.formattedCacheSize)) from your Mac. You can redownload your tracks at any time.")
        }
        .alert("Clear Listening History & Stats?", isPresented: $viewModel.showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                FluidHaptics.toggle()
                withAnimation(FluidTheme.tapSpring) {
                    player.playHistory.removeAll()
                    ListeningAnalyticsManager.shared.resetAll()
                }
            }
        } message: {
            Text("This will permanently delete your recently played track history and all local listening analytics. This action cannot be undone.")
        }
    }
    
    // MARK: - Preferences Toolbar Header (Native Apple macOS Style)
    
    @ViewBuilder
    private var preferencesHeader: some View {
        HStack(alignment: .center) {
            // Left Spacer matching Trailing Done button width (64pt) for true optical centering
            Spacer()
                .frame(width: 64)
            
            Spacer()
            
            // Center Apple macOS Icon Tabs (Equal widths, icon on top, text underneath)
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    let isSelected = viewModel.selectedTab == tab
                    Button(action: {
                        FluidHaptics.tap()
                        withAnimation(FluidTheme.tapSpring) {
                            viewModel.selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(isSelected ? FluidTheme.musicRed : .secondary)
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 72, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
            
            // Right Apple Standard Done Button
            Button(action: {
                FluidHaptics.tap()
                dismiss()
            }) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .foregroundColor(.white)
                    .background(FluidTheme.musicRed)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 64, alignment: .trailing)
            .keyboardShortcut(.defaultAction)
            .help("Close Settings (Return or Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - 1. Playback Tab Content
    
    @ViewBuilder
    private var playbackContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Streaming Quality
            settingsGroup(title: "STREAMING QUALITY") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Audio Stream Quality")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { player.selectedAudioQuality },
                            set: { player.switchQuality(to: $0); FluidHaptics.tap() }
                        )) {
                            ForEach(AudioQuality.allCases) { q in
                                Text(q.rawValue).tag(q)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 215)
                    }
                    
                    Text("Standard (AAC 128k) uses Apple CoreAudio hardware decoding with near-zero battery. High (Opus 160k) delivers studio acoustic fidelity.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            
            // Radio & Autoplay
            settingsGroup(title: "RADIO & AUTOPLAY") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Autoplay Recommended Radio Tracks")
                            .font(.system(size: 13, weight: .medium))
                        Text("Continuously discovers and plays similar YouTube Music tracks when queue ends.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { player.isAutoplayEnabled },
                        set: { player.isAutoplayEnabled = $0; FluidHaptics.toggle() }
                    ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: FluidTheme.musicRed))
                }
                .padding(14)
            }
            
            // Smart Playlists
            settingsGroup(title: "SMART PLAYLISTS") {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Automatic Curation on Download")
                                .font(.system(size: 13, weight: .medium))
                            Text("Automatically categorizes downloaded songs into languages and genres.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { AIProviderConfig.shared.isAutoCurateOnDownloadEnabled },
                            set: { AIProviderConfig.shared.isAutoCurateOnDownloadEnabled = $0; FluidHaptics.toggle() }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: FluidTheme.musicRed))
                    }
                    .padding(14)
                    
                    Divider().opacity(0.2)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto-Sync Pending Tracks")
                                .font(.system(size: 13, weight: .medium))
                            Text("Automatically processes tracks from the outbox queue when connected.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { AIProviderConfig.shared.isAutoRetryPendingEnabled },
                            set: { AIProviderConfig.shared.isAutoRetryPendingEnabled = $0; FluidHaptics.toggle() }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: FluidTheme.musicRed))
                    }
                    .padding(14)

                    Divider().opacity(0.2)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Provider")
                                .font(.system(size: 13, weight: .medium))
                            Text("Service used for song classification.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { AIProviderConfig.shared.selectedProvider },
                            set: { (val: AIProvider) in
                                AIProviderConfig.shared.selectedProvider = val
                                FluidHaptics.tap()
                            }
                        )) {
                            ForEach(AIProvider.allCases) { prov in
                                Text(prov.displayName).tag(prov)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    .padding(14)

                    if AIProviderConfig.shared.selectedProvider.requiresApiKey {
                        Divider().opacity(0.2)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("API Key")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Stored securely. Only song title and artist are transmitted.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            SecureField("Enter API Key", text: Binding(
                                get: { AIProviderConfig.shared.apiKey },
                                set: { AIProviderConfig.shared.apiKey = $0 }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                        }
                        .padding(14)

                        if !AIProviderConfig.shared.selectedProvider.instructionsURL.isEmpty,
                           let url = URL(string: AIProviderConfig.shared.selectedProvider.instructionsURL) {
                            HStack {
                                Link("Get Free \(AIProviderConfig.shared.selectedProvider.shortName) Key ↗", destination: url)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(FluidTheme.musicRed)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 6)
                        }

                        Divider().opacity(0.2)

                        HStack {
                            Button {
                                FluidHaptics.tap()
                                Task {
                                    _ = await AIPlaylistEngine.shared.testAPIConnection()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if AIPlaylistEngine.shared.testingConnection {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "checkmark.shield.fill")
                                    }
                                    Text(AIPlaylistEngine.shared.testingConnection ? "Verifying..." : "Test API Key & Verify")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(FluidTheme.musicRed.opacity(0.12))
                                .foregroundColor(FluidTheme.musicRed)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(AIPlaylistEngine.shared.testingConnection || AIProviderConfig.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if let msg = AIPlaylistEngine.shared.connectionMessage {
                                Text(msg)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                                    .padding(.leading, 6)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(14)
                    } else if AIProviderConfig.shared.selectedProvider == .ollama {
                        Divider().opacity(0.2)

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ollama Endpoint")
                                    .font(.system(size: 13, weight: .medium))
                                Text("URL of your local Ollama instance.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            TextField("http://localhost:11434/v1/chat/completions", text: Binding(
                                get: { AIProviderConfig.shared.customEndpoint },
                                set: { AIProviderConfig.shared.customEndpoint = $0 }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 250)
                        }
                        .padding(14)

                        Divider().opacity(0.2)

                        HStack {
                            Button {
                                FluidHaptics.tap()
                                Task {
                                    _ = await AIPlaylistEngine.shared.testAPIConnection()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if AIPlaylistEngine.shared.testingConnection {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text(AIPlaylistEngine.shared.testingConnection ? "Verifying..." : "Test Local Ollama Connection")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(FluidTheme.musicRed.opacity(0.12))
                                .foregroundColor(FluidTheme.musicRed)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(AIPlaylistEngine.shared.testingConnection)

                            if let msg = AIPlaylistEngine.shared.connectionMessage {
                                Text(msg)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                                    .padding(.leading, 6)
                            }
                            Spacer()
                        }
                        .padding(14)
                    } else {
                        Divider().opacity(0.2)

                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 13))
                                Text("No sign-up or API key required. Works automatically.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                FluidHaptics.tap()
                                Task {
                                    _ = await AIPlaylistEngine.shared.testAPIConnection()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if AIPlaylistEngine.shared.testingConnection {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "checkmark.shield.fill")
                                    }
                                    Text(AIPlaylistEngine.shared.testingConnection ? "Verifying..." : "Test Connection")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(FluidTheme.musicRed.opacity(0.12))
                                .foregroundColor(FluidTheme.musicRed)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(AIPlaylistEngine.shared.testingConnection)
                        }
                        .padding(14)

                        if let msg = AIPlaylistEngine.shared.connectionMessage {
                            HStack {
                                Text(msg)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
            
            // Audio Transitions & Volume
            settingsGroup(title: "AUDIO TRANSITIONS & VOLUME") {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sound Check (Audio Normalization)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Balances volume levels across songs with different recording master volumes.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { player.isAudioNormalized },
                            set: { player.isAudioNormalized = $0; FluidHaptics.toggle() }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: FluidTheme.musicRed))
                    }
                    .padding(14)
                    
                    Divider().opacity(0.2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Crossfade Duration")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(player.crossfadeDuration == 0 ? "Off (0s)" : String(format: "%.1f seconds", player.crossfadeDuration))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(player.crossfadeDuration == 0 ? .secondary : FluidTheme.musicRed)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { player.crossfadeDuration },
                                set: { player.crossfadeDuration = (round($0 * 2) / 2) }
                            ),
                            in: 0...12
                        )
                        .accentColor(FluidTheme.musicRed)
                    }
                    .padding(14)
                }
            }
            
            // Lyrics Synchronization
            settingsGroup(title: "LYRICS SYNCHRONIZATION") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Natural Vocal Lead Time")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { player.lyricLeadTime },
                            set: { player.lyricLeadTime = $0; FluidHaptics.tap() }
                        )) {
                            Text("Off (0.0s)").tag(0.0)
                            Text("Snappy (0.2s)").tag(0.20)
                            Text("Apple Music (0.35s)").tag(0.35)
                            Text("Generous (0.5s)").tag(0.50)
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 215)
                    }
                    
                    Text("Anticipates vocal onset by smoothly animating lines into view as the phrase begins, matching Apple Music and karaoke displays.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            
            // Equalizer & Audio Profiles
            settingsGroup(title: "EQUALIZER & AUDIO PROFILES") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("10-Band Graphic Equalizer")
                            .font(.system(size: 13, weight: .medium))
                        Text("Active Preset: \(player.equalizerPreset) (32 Hz to 16 kHz acoustic curve)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        FluidHaptics.tap()
                        player.showEqualizerSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.vertical.3")
                            Text("Open Equalizer...")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(14)
            }
        }
    }
    
    // MARK: - 2. Appearance Tab Content
    
    @ViewBuilder
    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup(title: "THEME PREFERENCE") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ForEach(AppThemeMode.allCases) { mode in
                            themePreviewCard(mode: mode)
                        }
                    }
                    
                    Divider().opacity(0.2)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(FluidTheme.musicRed)
                        Text(themeManager.currentTheme.description)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
            }
            
            settingsGroup(title: "NOW PLAYING IMMERSIVE EXPERIENCE") {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Adaptive Dynamic Backdrop")
                                .font(.system(size: 13, weight: .medium))
                            Text("Harmonizes Now Playing with your chosen theme. Light mode renders an airy frosted ambient glow with high-contrast text; Dark mode renders a deep cinematic atmosphere.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                    .padding(14)
                    
                    Divider().opacity(0.2)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Active Appearance State")
                                .font(.system(size: 13, weight: .medium))
                            Text("Controls window frames, titlebars, menu bar popovers, and sheets.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(themeManager.currentTheme.displayName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(FluidTheme.musicRed)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(FluidTheme.musicRed.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(14)
                }
            }
        }
    }
    
    @ViewBuilder
    private func themePreviewCard(mode: AppThemeMode) -> some View {
        let isSelected = themeManager.currentTheme == mode
        
        Button(action: {
            themeManager.setTheme(mode)
        }) {
            VStack(spacing: 8) {
                // Mini window mockup preview
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    
                    switch mode {
                    case .light:
                        VStack(spacing: 0) {
                            // Mini title bar
                            HStack(spacing: 3) {
                                Circle().fill(Color.red.opacity(0.8)).frame(width: 4, height: 4)
                                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 4, height: 4)
                                Circle().fill(Color.green.opacity(0.8)).frame(width: 4, height: 4)
                                Spacer()
                            }
                            .padding(4)
                            .background(Color(white: 0.94))
                            
                            HStack(spacing: 0) {
                                // Mini sidebar
                                Rectangle()
                                    .fill(Color(white: 0.90))
                                    .frame(width: 26)
                                // Mini content
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2).fill(FluidTheme.musicRed).frame(width: 28, height: 4)
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.black.opacity(0.3)).frame(width: 45, height: 3)
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.black.opacity(0.15)).frame(width: 35, height: 3)
                                    Spacer()
                                }
                                .padding(4)
                                .background(Color.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        
                    case .dark:
                        VStack(spacing: 0) {
                            // Mini title bar
                            HStack(spacing: 3) {
                                Circle().fill(Color.red.opacity(0.8)).frame(width: 4, height: 4)
                                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 4, height: 4)
                                Circle().fill(Color.green.opacity(0.8)).frame(width: 4, height: 4)
                                Spacer()
                            }
                            .padding(4)
                            .background(Color(white: 0.16))
                            
                            HStack(spacing: 0) {
                                // Mini sidebar
                                Rectangle()
                                    .fill(Color(white: 0.20))
                                    .frame(width: 26)
                                // Mini content
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2).fill(FluidTheme.musicRed).frame(width: 28, height: 4)
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.6)).frame(width: 45, height: 3)
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.3)).frame(width: 35, height: 3)
                                    Spacer()
                                }
                                .padding(4)
                                .background(Color(white: 0.12))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        
                    case .system:
                        HStack(spacing: 0) {
                            // Light half
                            VStack(spacing: 0) {
                                HStack(spacing: 2) {
                                    Circle().fill(Color.red.opacity(0.8)).frame(width: 4, height: 4)
                                    Circle().fill(Color.yellow.opacity(0.8)).frame(width: 4, height: 4)
                                    Spacer()
                                }
                                .padding(3)
                                .background(Color(white: 0.94))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2).fill(FluidTheme.musicRed).frame(width: 20, height: 4)
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.black.opacity(0.3)).frame(width: 30, height: 3)
                                    Spacer()
                                }
                                .padding(3)
                                .background(Color.white)
                            }
                            
                            // Dark half
                            VStack(spacing: 0) {
                                HStack(spacing: 2) {
                                    Spacer()
                                    Circle().fill(Color.green.opacity(0.8)).frame(width: 4, height: 4)
                                }
                                .padding(3)
                                .background(Color(white: 0.16))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2).fill(FluidTheme.musicRed).frame(width: 20, height: 4)
                                    RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.4)).frame(width: 30, height: 3)
                                    Spacer()
                                }
                                .padding(3)
                                .background(Color(white: 0.12))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .frame(height: 64)
                
                // Mode Label & Radio Indicator
                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? FluidTheme.musicRed : .secondary)
                    
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? .primary : .secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? FluidTheme.musicRed.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 3. Storage Tab Content
    
    @ViewBuilder
    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup(title: "OFFLINE MEDIA CACHE") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Current Storage Used")
                                .font(.system(size: 13, weight: .medium))
                            Text("Downloaded and cached tracks are stored locally in your sandboxed container.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Text(libraryVM.formattedCacheSize)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                    
                    Divider().opacity(0.2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SONORIST PARENT FOLDER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        Text(MediaCacheManager.shared.parentDirectory.path)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            FluidHaptics.tap()
                            MediaCacheManager.shared.revealParentFolderInFinder()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                Text("Reveal in Finder")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            FluidHaptics.tap()
                            libraryVM.exportAllTracksToFinder()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export All (.m4a)...")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        Button(action: {
                            FluidHaptics.tap()
                            viewModel.showPurgeCacheAlert = true
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("Purge Library")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(FluidTheme.musicRed)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(FluidTheme.musicRed.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if viewModel.showPurgeSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All offline bundles purged successfully (0 KB).")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(14)
            }
        }
    }
    
    // MARK: - 3. Privacy Tab Content
    
    @ViewBuilder
    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup(title: "ECC & APPLE TRANSPORT SECURITY") {
                VStack(spacing: 0) {
                    HStack {
                        Label("App Transport Security (ATS)", systemImage: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("Strict HTTPS Enforced")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    
                    Divider().opacity(0.2)
                    
                    HStack {
                        Label("Cipher Deobfuscator Sandbox", systemImage: "cpu.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("Apple JavaScriptCore Isolated")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    
                    Divider().opacity(0.2)
                    
                    Text("YouTube stream ciphers and anti-throttling challenges are executed in an isolated JSContext with zero filesystem or network socket privileges.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                }
            }
            
            settingsGroup(title: "PRIVACY DATA") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Listening History & Local Stats")
                            .font(.system(size: 13, weight: .medium))
                        Text("Clear recently played tracks and local listening timestamps.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        FluidHaptics.tap()
                        viewModel.showClearHistoryAlert = true
                    }) {
                        Text("Clear History")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FluidTheme.musicRed)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(FluidTheme.musicRed.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(14)
            }
        }
    }
    
    // MARK: - 4. Shortcuts & About Tab Content
    
    @ViewBuilder
    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup(title: "KEYBOARD SHORTCUTS") {
                VStack(spacing: 8) {
                    shortcutRow(label: "Play / Pause", key: "Space")
                    shortcutRow(label: "Next Track", key: "⌘ →")
                    shortcutRow(label: "Previous Track", key: "⌘ ←")
                    shortcutRow(label: "Toggle Full-Window Now Playing", key: "⌘ F")
                    shortcutRow(label: "Toggle Synced Lyrics", key: "⌘ L")
                    shortcutRow(label: "Toggle Up Next Queue", key: "⌘ U")
                    shortcutRow(label: "Toggle Sidebar", key: "⌃ ⌘ S")
                    shortcutRow(label: "Preferences & Settings", key: "⌘ ,")
                }
                .padding(14)
            }
            
            settingsGroup(title: "ABOUT SONORIST") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sonorist for Mac")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("v2.1.0 • Native Apple Silicon arm64 • macOS 13+")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "applelogo")
                        Text("Apple Silicon")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .padding(14)
            }
        }
    }
    
    // MARK: - Card Wrapper Helper
    
    @ViewBuilder
    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
    
    @ViewBuilder
    private func shortcutRow(label: String, key: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
