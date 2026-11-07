import SwiftUI

public struct MusicGenreDNA: Identifiable {
    public var id: String { name }
    public let name: String
    public let count: Int
    public let percentage: Double
    public let color: Color
    public let icon: String
}

public final class MobileAnalyticsModel: ObservableObject {
    public static let shared = MobileAnalyticsModel()
    @Published public var showSettings: Bool = false
    public init() {}
}

/// iOS-optimized Listening Insights & Apple Music Replay style view for iPhone
public struct MobileAnalyticsView: View {
    @ObservedObject private var analytics = ListeningAnalyticsManager.shared
    @ObservedObject private var player = AudioPlayerEngine.shared
    @ObservedObject private var themeManager = AppThemeManager.shared
    @ObservedObject private var model = MobileAnalyticsModel.shared
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header (Aligned comfortably below Dynamic Island / status bar)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Replay Insights")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("Your personal listening DNA")
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
                    HStack(spacing: 5) {
                        Image(systemName: themeManager.currentTheme.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(themeManager.currentTheme.displayName)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                
                // Native Settings Shortcut Button
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
            .padding(.bottom, 12)
            
            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Hero Total Listening Card
                    heroCard
                    
                    // Music DNA / Top Genres Spectrum
                    musicDNACard
                    
                    // Listener Persona Card
                    personaCard
                    
                    // Most Played Tracks
                    topTracksSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 180) // Generous space so content scrolls completely clear of MiniPlayer & TabBar
            }
        }
        .sheet(isPresented: $model.showSettings) {
            MobileSettingsView(isPresentedAsSheet: true)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }
    
    // MARK: - Subviews
    
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TOTAL TIME STREAMED")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.0)
            
            Text(analytics.formattedTotalTime)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                    Text("\(analytics.totalSongsPlayed) songs")
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                    Text("\(analytics.formatDistribution["Offline Cached", default: 0]) offline")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [FluidTheme.musicRed, Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: FluidTheme.musicRed.opacity(0.25), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Music DNA / Genre Breakdown
    
    private var computedGenreDNA: [MusicGenreDNA] {
        // Collect tracks from analytics and playback history
        var allTracks: [Track] = analytics.topTracks.map { $0.track }
        for t in player.playHistory {
            if !allTracks.contains(where: { $0.id == t.id }) {
                allTracks.append(t)
            }
        }
        
        guard !allTracks.isEmpty else {
            return [
                MusicGenreDNA(name: "Pop Hits", count: 1, percentage: 0.50, color: FluidTheme.musicRed, icon: "sparkles"),
                MusicGenreDNA(name: "R&B & Soul", count: 1, percentage: 0.30, color: Color.purple, icon: "heart.fill"),
                MusicGenreDNA(name: "Classical & Devotional", count: 1, percentage: 0.20, color: Color.orange, icon: "music.quarternote.3")
            ]
        }
        
        var counts: [String: Int] = [:]
        
        for t in allTracks {
            let text = "\(t.title) \(t.artist) \(t.album ?? "")".lowercased()
            
            if text.contains("ramprasad") || text.contains("kishore") || text.contains("rabindra") ||
               text.contains("sarkar") || text.contains("chakraborty") || text.contains("classical") ||
               text.contains("bhajan") || text.contains("kirtan") || text.contains("devotional") || text.contains("spiritual") {
                counts["Classical & Spiritual", default: 0] += 1
            } else if text.contains("enrique") || text.contains("ayer") || text.contains("subeme") ||
                      text.contains("lopez") || text.contains("dua lipa") || text.contains("sheeran") ||
                      text.contains("pop") || text.contains("dance") {
                counts["Pop & Latin", default: 0] += 1
            } else if text.contains("weeknd") || text.contains("jay sean") || text.contains("flo rida") ||
                      text.contains("r&b") || text.contains("soul") || text.contains("direction") {
                counts["R&B & Soul", default: 0] += 1
            } else if text.contains("chill") || text.contains("lo-fi") || text.contains("ambient") || text.contains("relax") {
                counts["Lo-Fi & Ambient", default: 0] += 1
            } else {
                counts["Melodic Pop", default: 0] += 1
            }
        }
        
        let totalCount = max(1, counts.values.reduce(0, +))
        
        let palette: [(name: String, color: Color, icon: String)] = [
            ("Classical & Spiritual", Color.orange, "hands.sparkles.fill"),
            ("Pop & Latin", FluidTheme.musicRed, "flame.fill"),
            ("R&B & Soul", Color.purple, "waveform.badge.magnifyingglass"),
            ("Lo-Fi & Ambient", Color.teal, "leaf.fill"),
            ("Melodic Pop", Color.blue, "music.note")
        ]
        
        var result: [MusicGenreDNA] = []
        for item in palette {
            if let count = counts[item.name], count > 0 {
                let pct = Double(count) / Double(totalCount)
                result.append(MusicGenreDNA(name: item.name, count: count, percentage: pct, color: item.color, icon: item.icon))
            }
        }
        
        if result.isEmpty {
            result.append(MusicGenreDNA(name: "Pop Hits", count: 1, percentage: 1.0, color: FluidTheme.musicRed, icon: "music.note"))
        }
        
        return result.sorted { $0.percentage > $1.percentage }
    }
    
    private var musicDNACard: some View {
        let genres = computedGenreDNA
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MUSIC DNA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                    Text("Top Genres & Vibe")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FluidTheme.musicRed)
            }
            
            // Apple-Style Continuous Segmented Spectrum Bar
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 3) {
                    ForEach(genres) { g in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(g.color)
                            .frame(width: max(6, (w - CGFloat(genres.count - 1) * 3) * CGFloat(g.percentage)))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            
            // Genre Breakdown Chips
            VStack(spacing: 8) {
                ForEach(genres) { g in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(g.color)
                            .frame(width: 8, height: 8)
                        
                        Image(systemName: g.icon)
                            .font(.system(size: 12))
                            .foregroundColor(g.color)
                        
                        Text(g.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(Int(round(g.percentage * 100)))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(isLight ? Color.white : FluidTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var personaCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LISTENER PERSONA")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
                
                Text(analytics.primaryTimeOfDay)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Peak: \(analytics.peakListeningWindow)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundColor(FluidTheme.musicRed)
                .padding(14)
                .background(FluidTheme.musicRed.opacity(0.12))
                .clipShape(Circle())
        }
        .padding(16)
        .background(isLight ? Color.white : FluidTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MOST PLAYED TRACKS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.8)
            
            VStack(spacing: 8) {
                ForEach(Array(analytics.topTracks.prefix(5).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        TrackArtworkView(
                            url: item.track.artworkURL,
                            contentMode: .fill,
                            cornerRadius: 8,
                            placeholderIconSize: 14
                        )
                        .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            
                            Text(item.track.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text("\(item.playCount) \(item.playCount == 1 ? "play" : "plays")")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(isLight ? Color.black.opacity(0.03) : Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(isLight ? Color.white : FluidTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
