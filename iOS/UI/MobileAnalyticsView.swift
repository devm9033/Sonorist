import SwiftUI

public final class MobileAnalyticsModel: ObservableObject {
    public static let shared = MobileAnalyticsModel()
    @Published public var showSettings: Bool = false
    @Published public var selectedLanguage: String? = nil
    @Published public var selectedTimeSlot: TimeOfDaySlot? = nil
    @Published public var selectedMetricChip: String? = nil
    @Published public var isRefreshing: Bool = false
    public init() {}
}

/// iOS-optimized Listening Insights & Music Profile View for iPhone
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
            // Pinned Header (Pinned comfortably below Dynamic Island / status bar)
            headerSection
            
            // Scrollable Content with Native Pull-To-Refresh
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if analytics.totalSongsPlayed == 0 {
                        zeroStateView
                    } else if !insights.isThresholdReached {
                        // Calibration state (1 to 9 songs)
                        calibrationCard
                        
                        // Show current rotation so user still sees their real data immediately
                        if let topTrack = analytics.topTracks.first {
                            heroMostPlayedCard(topTrack: topTrack)
                        }
                        
                        if !insights.computedLanguageSpectrum.isEmpty {
                            soundSpectrumCard
                        }
                    } else {
                        // Full Music Profile (>= 10 songs)
                        
                        // 1. #1 Most Played Track (Hero Card)
                        if let topTrack = analytics.topTracks.first {
                            heroMostPlayedCard(topTrack: topTrack)
                        }
                        
                        // 2. Interactive Sound & Cultural Spectrum
                        soundSpectrumCard
                        
                        // 3. Circadian Listening Dial (Day & Night)
                        circadianDialCard
                        
                        // 4. Listening Rhythm (Full Plays vs Skips)
                        listeningRhythmCard
                        
                        // 5. Top Artists Roster
                        if !analytics.topArtists.isEmpty {
                            topArtistsCard
                        }
                        
                        // 6. Objective Musicologist Commentary (AI or Local Grounded)
                        musicologistCard
                        
                        // 7. Data Freedom & Offline Footprint
                        dataFreedomCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 180) // Generous space so content scrolls clear of MiniPlayer & TabBar
            }
            .refreshable {
                MobileHaptics.trigger(.medium)
                model.isRefreshing = true
                await insights.generateInsights(force: true)
                model.isRefreshing = false
            }
        }
        .sheet(isPresented: $model.showSettings) {
            MobileSettingsView(isPresentedAsSheet: true)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task {
            if insights.shouldAutoSync {
                await insights.generateInsights(force: false)
            }
        }
    }
    
    // MARK: - Header (Clean, Pinned, Zero AI Badges)
    
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Insights")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Your listening habits & sound profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
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
    
    // MARK: - Zero State (Brand New App Install)
    
    private var zeroStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 16)
            
            ZStack {
                Circle()
                    .fill(FluidTheme.musicRed.opacity(0.12))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            VStack(spacing: 6) {
                Text("No Listening Data Yet")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                
                Text("Sonorist logs your authentic playback locally on your device. Play a few songs to view your real listening time, top tracks, and sound profile.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("100% on-device & private")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            
            Spacer().frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(cardBackground)
    }
    
    // MARK: - Calibration State (1 to 9 Tracks)
    
    private var calibrationCard: some View {
        let count = analytics.totalSongsPlayed
        let progress = insights.thresholdProgress
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("BUILDING SOUND PROFILE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(count) / 10 songs")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            // Visual Progress Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [FluidTheme.musicRed, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, geo.size.width * CGFloat(progress)), height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
                }
            }
            .frame(height: 8)
            
            Text("Logged \(analytics.formattedTotalTime) of authentic listening. Once you reach 10 songs, deep audio habits and cultural breakdown will fully activate.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 1. Hero Most Played Track ("Heavy Rotation")
    
    private func heroMostPlayedCard(topTrack: TrackAnalytics) -> some View {
        let track = topTrack.track
        let playCount = topTrack.playCount
        let mins = max(1, Int(topTrack.totalSeconds / 60))
        let isSelected = model.selectedMetricChip != nil
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("MOST PLAYED TRACK")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Mini Visualizer Indicator
                HStack(spacing: 2) {
                    ForEach(0..<4) { idx in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(FluidTheme.musicRed)
                            .frame(width: 2.5, height: CGFloat([8, 14, 11, 6][idx]))
                    }
                }
            }
            
            HStack(spacing: 14) {
                // Large Artwork Tile with Glow
                ZStack {
                    TrackArtworkView(
                        url: track.artworkURL,
                        contentMode: .fill,
                        cornerRadius: 14,
                        placeholderIconSize: 24
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: FluidTheme.musicRed.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Style & Quality Tag
                    HStack(spacing: 6) {
                        Text("Lossless M4A")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(FluidTheme.downloadGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FluidTheme.downloadGreen.opacity(0.12))
                            .clipShape(Capsule())
                        
                        let detected = AIPlaylistEngine.shared.classifyTrackHeuristically(track).language
                        Text(detected)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            
            // Interactive Metric Chips (Tap to inspect)
            HStack(spacing: 8) {
                metricChip(
                    id: "plays",
                    icon: "repeat",
                    title: "\(playCount) \(playCount == 1 ? "play" : "plays")",
                    detail: "Repeated in rotation"
                )
                
                metricChip(
                    id: "time",
                    icon: "clock.fill",
                    title: "\(mins) mins",
                    detail: "Total listening time"
                )
                
                metricChip(
                    id: "completion",
                    icon: "checkmark.circle.fill",
                    title: "\(Int(analytics.completionPercentage * 100))%",
                    detail: "Finished in full"
                )
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func metricChip(id: String, icon: String, title: String, detail: String) -> some View {
        let isSelected = model.selectedMetricChip == id
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if model.selectedMetricChip == id {
                    model.selectedMetricChip = nil
                } else {
                    model.selectedMetricChip = id
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .white : FluidTheme.musicRed)
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                Text(isSelected ? detail : "Tap for details")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? Color.white.opacity(0.85) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? FluidTheme.musicRed : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 2. Sound & Cultural Spectrum (Interactive Proportional Bar)
    
    private var soundSpectrumCard: some View {
        let spectrum = insights.computedLanguageSpectrum
        let activeLang = model.selectedLanguage ?? spectrum.first?.language
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.indigo)
                        Text("SOUND & LANGUAGE SPECTRUM")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text("Cultural breakdown of your library")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(spectrum.count) \(spectrum.count == 1 ? "Style" : "Styles")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            // Continuous Proportional Bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(spectrum) { item in
                        let isHighlighted = activeLang == item.language
                        colorForName(item.colorName)
                            .opacity(model.selectedLanguage == nil || isHighlighted ? 1.0 : 0.35)
                            .frame(width: max(4, geo.size.width * CGFloat(item.percentage)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            
            // Interactive Language Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(spectrum) { item in
                        let isSelected = activeLang == item.language
                        Button {
                            MobileHaptics.trigger(.selection)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                if model.selectedLanguage == item.language {
                                    model.selectedLanguage = nil
                                } else {
                                    model.selectedLanguage = item.language
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(colorForName(item.colorName))
                                    .frame(width: 8, height: 8)
                                Text("\(item.language) \(Int(item.percentage * 100))%")
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? colorForName(item.colorName) : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Contextual Detail for Selected Language
            if let target = spectrum.first(where: { $0.language == activeLang }) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(target.count) \(target.count == 1 ? "song" : "songs") in \(target.language) • \(Int(target.percentage * 100))% of your total rotation")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 3. Circadian Listening Dial (Interactive Day & Night)
    
    private var circadianDialCard: some View {
        let total = Double(max(1, analytics.totalSongsPlayed))
        let slots = analytics.timeSlotDistribution
        let primaryWindow = analytics.peakListeningWindow
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.and.horizon.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                        Text("CIRCADIAN SOUNDSCAPE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Text("When music accompanies your day")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(analytics.primaryTimeOfDay)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            // 4-Quadrant Visual Grid
            HStack(spacing: 8) {
                circadianQuadrant(
                    slot: .morning,
                    title: "Morning",
                    hours: "6AM-12PM",
                    icon: "sun.and.horizon",
                    color: .orange
                )
                
                circadianQuadrant(
                    slot: .afternoon,
                    title: "Afternoon",
                    hours: "12PM-5PM",
                    icon: "sun.max.fill",
                    color: .yellow
                )
                
                circadianQuadrant(
                    slot: .evening,
                    title: "Evening",
                    hours: "5PM-10PM",
                    icon: "sunset.fill",
                    color: .purple
                )
                
                circadianQuadrant(
                    slot: .night,
                    title: "Night",
                    hours: "10PM-6AM",
                    icon: "moon.stars.fill",
                    color: FluidTheme.musicRed
                )
            }
            
            // Tap hint or detail
            if let sel = model.selectedTimeSlot {
                let count = slots[sel, default: 0]
                let pct = Int((Double(count) / total) * 100)
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("\(sel.rawValue): \(count) songs played (\(pct)% of listening)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func circadianQuadrant(slot: TimeOfDaySlot, title: String, hours: String, icon: String, color: Color) -> some View {
        let count = analytics.timeSlotDistribution[slot, default: 0]
        let pct = Int(analytics.timeSlotPercentage(for: slot) * 100)
        let isPeak = analytics.peakListeningWindow.contains(title)
        let isSelected = model.selectedTimeSlot == slot
        
        return Button {
            MobileHaptics.trigger(.selection)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if model.selectedTimeSlot == slot {
                    model.selectedTimeSlot = nil
                } else {
                    model.selectedTimeSlot = slot
                }
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isSelected ? 0.25 : 0.12))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? color : .primary)
                
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                if isPeak {
                    Text("PEAK")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(FluidTheme.musicRed)
                        .clipShape(Capsule())
                } else {
                    Text(hours)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 4. Listening Rhythm (Full Plays vs Skips)
    
    private var listeningRhythmCard: some View {
        let stats = analytics.completionCounts
        let completionPct = Int(analytics.completionPercentage * 100)
        let skipPct = max(0, 100 - completionPct)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.downloadGreen)
                    Text("LISTENING RHYTHM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(completionPct >= 85 ? "Patient Listener" : "Curator Mode")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(FluidTheme.downloadGreen)
            }
            
            // Dual-tone balance track
            GeometryReader { geo in
                HStack(spacing: 3) {
                    // Full Plays (Green/Teal)
                    FluidTheme.downloadGreen
                        .frame(width: max(8, geo.size.width * CGFloat(analytics.completionPercentage)))
                    
                    // Skips (Muted Gray/Coral)
                    Color.primary.opacity(0.15)
                        .frame(maxWidth: .infinity)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(FluidTheme.downloadGreen)
                        .frame(width: 8, height: 8)
                    Text("Deep Play: \(completionPct)% (\(stats.fullPlays) songs)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("Quick Skips: \(skipPct)% (\(stats.earlySkips) skipped)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 5. Top Artists Roster
    
    private var topArtistsCard: some View {
        let artists = analytics.topArtists.prefix(3)
        let total = Double(max(1, analytics.totalSongsPlayed))
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.purple)
                    Text("TOP ARTISTS IN ROTATION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(analytics.topArtists.count) Total")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, item in
                    let rankColor: Color = index == 0 ? FluidTheme.musicRed : (index == 1 ? .orange : .purple)
                    
                    HStack(spacing: 12) {
                        // Rank Badge
                        Text("#\(index + 1)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(rankColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.artist)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            // Visual percentage bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 5)
                                    
                                    Capsule()
                                        .fill(rankColor)
                                        .frame(width: max(6, geo.size.width * CGFloat(item.percentage)), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                        
                        Spacer()
                        
                        Text("\(item.count) \(item.count == 1 ? "play" : "plays")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 6. Musicologist Commentary (Objective & Grounded)
    
    private var musicologistCard: some View {
        let story = insights.currentStory
        let hasAPIKey = !AIProviderConfig.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                    Text("MUSICOLOGIST ANALYSIS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(story?.modelUsed ?? (hasAPIKey ? "AI Musicologist" : "On-Device"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text(story?.narrativeStory ?? "Your listening patterns show deep engagement with melodic acoustic arrangements, listening through songs with high consistency.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineSpacing(3)
            
            if !hasAPIKey {
                Divider()
                    .padding(.vertical, 2)
                
                Button {
                    model.showSettings = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                            .foregroundColor(FluidTheme.musicRed)
                        Text("Connect API Key in Settings for deep LLM commentary")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(FluidTheme.musicRed)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if let date = insights.lastGeneratedDate {
                HStack {
                    Spacer()
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened)) • Pull down to refresh")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - 7. Data Freedom & Offline Footprint
    
    private var dataFreedomCard: some View {
        let offlinePlays = analytics.formatDistribution["Offline Cached", default: 0]
        let offlineMins = offlinePlays * 3
        let savedMB = offlinePlays * 4
        
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
