import SwiftUI

public final class MobileAnalyticsModel: ObservableObject {
    public static let shared = MobileAnalyticsModel()
    @Published public var showSettings: Bool = false
    public init() {}
}

/// iOS-optimized AI-Powered Listening Insights & Music Replay View for iPhone
public struct MobileAnalyticsView: View {
    @ObservedObject private var analytics = ListeningAnalyticsManager.shared
    @ObservedObject private var insights = AIInsightsEngine.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var themeManager = AppThemeManager.shared
    @ObservedObject private var model = MobileAnalyticsModel.shared
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    private var isLight: Bool { colorScheme == .light }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header (Pinned comfortably below Dynamic Island / status bar)
            headerSection
            
            // Tone Selector (Always visible directly beneath header)
            if analytics.totalSongsPlayed >= 2 {
                toneSelectorSection
            }
            
            // Scrollable Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if analytics.totalSongsPlayed < 2 {
                        zeroStateView
                    } else {
                        // 1. Hero AI Archetype Persona
                        heroPersonaCard
                        
                        // 2. Soundscape Narrative Story
                        soundscapeStoryCard
                        
                        // 3. Multilingual Horizon (Sonorist Exclusive!)
                        multilingualHorizonCard
                        
                        // 4. The Obsession Index (Heavy Rotation)
                        if let obsession = insights.obsessionTrack {
                            obsessionIndexCard(obsession: obsession)
                        }
                        
                        // 5. 24-Hour Circadian Soundscape
                        circadianSoundscapeCard
                        
                        // 6. Data Freedom & Offline Footprint
                        dataFreedomCard
                        
                        // 7. Save Capsule Playlist Action
                        capsulePlaylistButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 180) // Generous space so content scrolls clear of MiniPlayer & TabBar
            }
        }
        .sheet(isPresented: $model.showSettings) {
            MobileSettingsView(isPresentedAsSheet: true)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task {
            if analytics.totalSongsPlayed >= 2 && insights.currentStory == nil {
                await insights.generateInsights()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Insights")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("AI REPLAY")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(FluidTheme.musicRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(FluidTheme.musicRed.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Text("Decoded from your authentic listening")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // AI Refresh Button
            if analytics.totalSongsPlayed >= 2 {
                Button {
                    MobileHaptics.trigger(.medium)
                    Task {
                        await insights.generateInsights(force: true)
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FluidTheme.musicRed)
                        .frame(width: 32, height: 32)
                        .background(FluidTheme.musicRed.opacity(0.12))
                        .clipShape(Circle())
                        .rotationEffect(.degrees(insights.isGenerating ? 360 : 0))
                        .animation(
                            insights.isGenerating
                                ? Animation.linear(duration: 1.0).repeatForever(autoreverses: false)
                                : .default,
                            value: insights.isGenerating
                        )
                }
                .disabled(insights.isGenerating)
            }
            
            // Theme Switcher Menu
            Menu {
                ForEach(AppThemeMode.allCases) { mode in
                    Button {
                        themeManager.setTheme(mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode.icon)
                    }
                }
            } label: {
                Image(systemName: themeManager.currentTheme.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            
            // Settings Button
            Button {
                MobileHaptics.trigger(.selection)
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    
    // MARK: - Tone Selector
    
    private var toneSelectorSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AIInsightsTone.allCases) { tone in
                    let isSelected = insights.selectedTone == tone
                    Button {
                        MobileHaptics.trigger(.selection)
                        insights.selectedTone = tone
                    } label: {
                        Text(tone.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Zero State
    
    private var zeroStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)
            
            ZStack {
                Circle()
                    .fill(FluidTheme.musicRed.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            VStack(spacing: 8) {
                Text("Your Story Starts Here")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                
                Text("No fake numbers or mock tracks. As you listen to songs in Sonorist, your personal AI music biographer will decode your listening DNA, time rhythms, and genuine soundscape.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Unlocks after playing your first few tracks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
            
            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 1. Hero Persona Card
    
    private var heroPersonaCard: some View {
        let story = insights.currentStory
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("WEEKLY SOUND ARCHETYPE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color.white.opacity(0.9))
                
                Spacer()
                
                Text(analytics.formattedTotalTime)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.8))
            }
            
            Text(story?.archetypeTitle ?? "The Mindful Listener")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(story?.archetypeDescription ?? "Your soundscape turns meditative, seeking lyrical depth and acoustic sanctuary over noise.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.92))
                .lineSpacing(2)
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 2)
            
            HStack {
                HStack(spacing: 4) {
                    Text("Peak hour:")
                        .foregroundColor(Color.white.opacity(0.75))
                    Text(story?.peakListeningHour ?? "11:15 PM")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Patience:")
                        .foregroundColor(Color.white.opacity(0.75))
                    Text(story?.patienceRateText ?? "94% Zero-Skip")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
            .font(.system(size: 11))
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [FluidTheme.musicRed, Color.purple.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: FluidTheme.musicRed.opacity(0.3), radius: 14, x: 0, y: 6)
    }
    
    // MARK: - 2. Soundscape Narrative Story
    
    private var soundscapeStoryCard: some View {
        let story = insights.currentStory
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("YOUR SOUNDSCAPE STORY")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(story?.modelUsed ?? "Sonorist Biographer")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text(story?.narrativeStory ?? "Your listening patterns celebrate balance and warmth, choosing acoustic depth over passive background noise.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineSpacing(3)
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 3. Multilingual Horizon
    
    private var multilingualHorizonCard: some View {
        let spectrum = insights.computedLanguageSpectrum
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MULTILINGUAL HORIZON")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("Cultural spectrum of your songs")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(spectrum.count) \(spectrum.count == 1 ? "Language" : "Languages")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            if spectrum.isEmpty {
                Text("Listen to songs across different languages to map your cultural horizon here.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                // Segmented visual bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(spectrum) { item in
                            colorForName(item.colorName)
                                .frame(width: max(4, geo.size.width * CGFloat(item.percentage)))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                
                // Legend
                HStack(spacing: 16) {
                    ForEach(spectrum.prefix(4)) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(colorForName(item.colorName))
                                .frame(width: 8, height: 8)
                            Text("\(Int(item.percentage * 100))% \(item.language)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 4. The Obsession Index
    
    private func obsessionIndexCard(obsession: (track: Track, repeats: Int, rateText: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("THE OBSESSION INDEX")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(obsession.repeats)x in rotation")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(FluidTheme.musicRed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(FluidTheme.musicRed.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 12) {
                TrackArtworkView(
                    url: obsession.track.artworkURL,
                    contentMode: .fill,
                    cornerRadius: 10,
                    placeholderIconSize: 18
                )
                .frame(width: 48, height: 48)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(obsession.track.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(obsession.track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text(obsession.rateText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FluidTheme.musicRed)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 5. 24-Hour Circadian Soundscape
    
    private var circadianSoundscapeCard: some View {
        let total = Double(max(1, analytics.totalSongsPlayed))
        let slots = analytics.timeSlotDistribution
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CIRCADIAN SOUNDSCAPE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("When music accompanies your day")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(analytics.primaryTimeOfDay)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            HStack(spacing: 8) {
                slotBox(title: "Morning", slot: .morning, count: slots[.morning, default: 0], total: total, color: .orange)
                slotBox(title: "Afternoon", slot: .afternoon, count: slots[.afternoon, default: 0], total: total, color: .blue)
                slotBox(title: "Evening", slot: .evening, count: slots[.evening, default: 0], total: total, color: .purple)
                slotBox(title: "Midnight", slot: .night, count: slots[.night, default: 0], total: total, color: FluidTheme.musicRed)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func slotBox(title: String, slot: TimeOfDaySlot, count: Int, total: Double, color: Color) -> some View {
        let pct = Int((Double(count) / total) * 100)
        return VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text("\(pct)%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text("\(count) plays")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - 6. Data Freedom & Offline Footprint
    
    private var dataFreedomCard: some View {
        let offlinePlays = analytics.formatDistribution["Offline Cached", default: 0]
        let offlineMins = offlinePlays * 3 // estimate ~3 mins per track
        let savedMB = offlinePlays * 4     // estimate ~4MB per track
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(FluidTheme.downloadGreen)
                        .font(.system(size: 13))
                    Text("DATA FREEDOM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Zero-Data Offline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FluidTheme.downloadGreen)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(offlineMins) mins")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Offline listening")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("~\(savedMB) MB")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(FluidTheme.downloadGreen)
                    Text("Cellular saved")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("LZFSE")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.purple)
                    Text("Lossless packaging")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 7. Capsule Playlist Button
    
    private var capsulePlaylistButton: some View {
        Button {
            saveCapsulePlaylist()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.rectangle.on.folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
                Text("Save This Month's Capsule Playlist")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FluidTheme.musicRed.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func saveCapsulePlaylist() {
        let top = analytics.topTracks.prefix(15).map { $0.track }
        guard !top.isEmpty else { return }
        
        let monthName = DateFormatter().monthSymbols[Calendar.current.component(.month, from: Date()) - 1]
        let playlistName = "\(monthName) Soundscape"
        
        var library = AIPlaylistEngine.shared.curatedLibrary
        var cat = library.categories.first(where: { $0.language == "Capsules" }) ?? AILanguageCategory(
            id: "capsules_category",
            language: "Capsules",
            icon: "sparkles",
            genres: [],
            directTrackIds: []
        )
        
        var group = cat.genres.first(where: { $0.name == playlistName }) ?? AIGenreGroup(
            name: playlistName,
            icon: "star.fill",
            description: "Your top played songs in \(monthName)"
        )
        
        for t in top {
            if !group.trackIds.contains(t.id) {
                group.trackIds.append(t.id)
            }
        }
        
        cat.genres.removeAll(where: { $0.name == playlistName })
        cat.genres.insert(group, at: 0)
        
        library.categories.removeAll(where: { $0.language == "Capsules" })
        library.categories.insert(cat, at: 0)
        
        AIPlaylistEngine.shared.curatedLibrary = library
        AIPlaylistEngine.shared.saveLibrary()
        
        MobileHaptics.trigger(.heavy)
        MobileToastManager.shared.show(message: "Saved '\(playlistName)' to Library Playlists!", icon: "folder.badge.plus")
    }
    
    // MARK: - Helpers
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(isLight ? 0.04 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(isLight ? 0.08 : 0.09), lineWidth: 0.5)
            )
    }
    
    private func colorForName(_ name: String) -> Color {
        switch name {
        case "musicRed": return FluidTheme.musicRed
        case "amber": return .orange
        case "indigo": return .indigo
        case "teal": return .teal
        case "purple": return .purple
        case "emerald": return .green
        default: return FluidTheme.musicRed
        }
    }
}
