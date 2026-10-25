import SwiftUI
import Combine

public enum NavigationItem: String, CaseIterable, Identifiable, Codable {
    case search = "Search"
    case library = "Library"
    case analytics = "Analytics"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .search: return "magnifyingglass"
        case .library: return "square.stack.fill"
        case .analytics: return "chart.bar.xaxis"
        }
    }
}

public final class AppNavigationState: ObservableObject {
    public static let shared = AppNavigationState()
    
    public static let lastNavigationItemKey = "SonoristLastNavigationItem"
    public static let isSidebarVisibleKey = "SonoristIsSidebarVisible"
    
    @Published public var selectedItem: NavigationItem? {
        didSet {
            if let item = selectedItem {
                UserDefaults.standard.set(item.rawValue, forKey: Self.lastNavigationItemKey)
            }
        }
    }
    
    @Published public var isSidebarVisible: Bool {
        didSet {
            UserDefaults.standard.set(isSidebarVisible, forKey: Self.isSidebarVisibleKey)
        }
    }
    
    public init() {
        // Restore sidebar visibility (default true)
        if UserDefaults.standard.object(forKey: Self.isSidebarVisibleKey) != nil {
            self.isSidebarVisible = UserDefaults.standard.bool(forKey: Self.isSidebarVisibleKey)
        } else {
            self.isSidebarVisible = true
        }
        
        // Restore last selected tab; default to .search for first-time launch
        if let savedRaw = UserDefaults.standard.string(forKey: Self.lastNavigationItemKey),
           let savedItem = NavigationItem(rawValue: savedRaw) {
            self.selectedItem = savedItem
        } else {
            // First time default: Search window
            self.selectedItem = .search
        }
    }
}

public struct SidebarView: View {
    @ObservedObject var navState = AppNavigationState.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    public static let sidebarWidth: CGFloat = 210
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Branding Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FluidTheme.musicRed)
                        .frame(width: 24, height: 24)
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("Sonorist")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)
            
            // Rock-solid fixed navigation sections (no scrollview dynamic layout shifts)
            VStack(alignment: .leading, spacing: 18) {
                // Discover Section
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discover")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                    
                    sidebarButton(item: .search)
                }
                
                // My Music Section
                VStack(alignment: .leading, spacing: 3) {
                    Text("My Music")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                    
                    sidebarButton(item: .library, badgeCount: player.likedTracks.count)
                }
                
                // Insights Section
                VStack(alignment: .leading, spacing: 3) {
                    Text("Insights")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                    
                    sidebarButton(item: .analytics)
                }
            }
            .padding(.vertical, 4)
            
            Spacer()
        }
        .frame(width: Self.sidebarWidth, alignment: .leading)
        .clipped()
        .background(Color(NSColor.windowBackgroundColor).opacity(0.65))
    }
    
    @ViewBuilder
    private func sidebarButton(item: NavigationItem, badgeCount: Int = 0) -> some View {
        let isSelected = navState.selectedItem == item
        
        Button(action: {
            FluidHaptics.tap()
            // Direct, rock-solid state assignment to prevent pane resizing animations
            navState.selectedItem = item
        }) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? FluidTheme.musicRed : .secondary)
                    .frame(width: 20, alignment: .center)
                
                Text(item.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? FluidTheme.musicRed.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle()) // Entire rectangular area is clickable
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle()) // Ensure outer hit-testing covers the entire frame
        .padding(.horizontal, 8)
    }
}

public struct AmbientArtworkGlowView: View, Equatable {
    public let artworkURL: URL?
    
    public static func == (lhs: AmbientArtworkGlowView, rhs: AmbientArtworkGlowView) -> Bool {
        return lhs.artworkURL == rhs.artworkURL
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let url = artworkURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .blur(radius: 60)
                                .opacity(0.2)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipped()
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

public struct MainContentView: View {
    @ObservedObject var navState = AppNavigationState.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    @ObservedObject var themeManager = AppThemeManager.shared
    
    public init() {}
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Workspace Canvas: Full-Window Now Playing OR Standard Browse/Search/Library
                Group {
                    if player.isImmersiveViewActive {
                        ImmersivePlayerView()
                            .transition(.opacity.combined(with: .scale(scale: 0.99)))
                    } else {
                        // Standard Apple Music Docked Layout:
                        HStack(spacing: 0) {
                            if navState.isSidebarVisible {
                                SidebarView()
                                    .frame(width: SidebarView.sidebarWidth, alignment: .leading)
                                    .clipped()
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                
                                Divider()
                                    .opacity(0.35)
                            }
                            
                            // Main Content Canvas (Zero layout jumps on tab switch)
                            ZStack(alignment: .topLeading) {
                                switch navState.selectedItem {
                                case .analytics:
                                    AnalyticsView()
                                case .search:
                                    SearchView()
                                case .library:
                                    LibraryView()
                                case .none:
                                    SearchView()
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                            .clipped()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                    .opacity(0.35)
                
                // Unified Docked Lower Pane Player Bar (100% consistent across both Standard & Now Playing modes)
                PlayerBarView()
                    .frame(minHeight: 80, idealHeight: 80, maxHeight: 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .background(WindowMinSizeEnforcer(minSize: CGSize(width: 760, height: 560)))
        .background(
            Group {
                if !player.isImmersiveViewActive {
                    AmbientArtworkGlowView(artworkURL: player.currentTrack?.artworkURL)
                        .equatable()
                }
            }
        )
        .clipped()
        .navigationTitle(player.isImmersiveViewActive ? "Now Playing" : (navState.selectedItem?.rawValue ?? "Sonorist"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    FluidHaptics.tap()
                    if player.isImmersiveViewActive {
                        withAnimation(FluidTheme.fluidSpring) {
                            player.isImmersiveViewActive = false
                        }
                    } else {
                        withAnimation(FluidTheme.fluidSpring) {
                            navState.isSidebarVisible.toggle()
                        }
                    }
                }) {
                    Image(systemName: player.isImmersiveViewActive ? "chevron.left" : "sidebar.leading")
                }
                .help(player.isImmersiveViewActive ? "Back to Library (Esc or ⌘F)" : "Toggle Sidebar (⌃⌘S)")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    FluidHaptics.tap()
                    player.showSettingsSheet = true
                }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings & Equalizer (⌘,)")
            }
        }
        // Global Sheets accessible from both Standard & Immersive Views
        .sheet(isPresented: $player.showSettingsSheet) {
            SettingsView()
        }
        .sheet(isPresented: $player.showQueueSheet) {
            QueueView()
        }
        .sheet(isPresented: $player.showLyricsSheet) {
            LyricsView()
        }
        .sheet(isPresented: $player.showEqualizerSheet) {
            EqualizerView()
        }
    }
}

/// Enforces an OS-level physical minimum window size in AppKit without mutating user-configured window frame
public struct WindowMinSizeEnforcer: NSViewRepresentable {
    public let minSize: CGSize
    
    public init(minSize: CGSize) {
        self.minSize = minSize
    }
    
    public func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.minSize = minSize
        return view
    }
    
    public func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.minSize = minSize
        nsView.applyWindowConstraints()
    }
}

final public class WindowObserverView: NSView {
    var minSize: CGSize = CGSize(width: 760, height: 560)
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowConstraints()
    }
    
    func applyWindowConstraints() {
        guard let window = self.window else { return }
        if window.minSize != minSize {
            window.minSize = minSize
        }
    }
}
