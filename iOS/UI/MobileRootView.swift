import SwiftUI

public final class MobileNavigationCoordinator: ObservableObject {
    public static let shared = MobileNavigationCoordinator()
    
    @Published public var selectedTab: MobileTab = .search
    @Published public var isNowPlayingExpanded: Bool = true
    @Published public var sheetDragOffset: CGFloat = 0
    @Published public var isDraggingUpFromMiniPlayer: Bool = false
    
    public init() {}
}

/// Main Root Coordinator for Sonorist on iOS / iPhone
/// Orchestrates the bottom tab bar, floating mini player, and full-screen Now Playing sheet.
/// Supports fluid 1:1 interactive sheet expansion gesture from the mini player dock.
public struct MobileRootView: View {
    @ObservedObject private var coordinator = MobileNavigationCoordinator.shared
    
    public init() {}
    
    public var body: some View {
        GeometryReader { rootGeo in
            let screenHeight = rootGeo.size.height
            
            ZStack(alignment: .bottom) {
                // Main Tab Content Area
                Group {
                    switch coordinator.selectedTab {
                    case .search:
                        MobileSearchView()
                    case .library:
                        MobileLibraryView()
                    case .analytics:
                        MobileAnalyticsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Floating Chrome: MiniPlayer + TabBar
                VStack(spacing: 0) {
                    MobileMiniPlayerView(screenHeight: screenHeight) {
                        withAnimation(FluidTheme.fluidSpring) {
                            coordinator.sheetDragOffset = 0
                            coordinator.isNowPlayingExpanded = true
                        }
                    }
                    
                    MobileTabBarView(selectedTab: $coordinator.selectedTab)
                }
                
                // Native In-App Slide-up Modal Sheet for Now Playing
                // Supports both animated presentation and 1:1 direct manipulation finger tracking
                if coordinator.isNowPlayingExpanded || coordinator.isDraggingUpFromMiniPlayer {
                    MobileNowPlayingSheet(isPresented: $coordinator.isNowPlayingExpanded)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: coordinator.isDraggingUpFromMiniPlayer ? coordinator.sheetDragOffset : 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .zIndex(100)
                }
                
                // Floating Toast Notification HUD
                VStack {
                    ToastOverlayView()
                        .padding(.top, max(60, rootGeo.safeAreaInsets.top + 10))
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(200)
            }
            .background(Color.platformSystemBackground.ignoresSafeArea())
        }
        .onAppear {
            iOSAudioSessionManager.shared.configurePlaybackSession()
        }
        .onChange(of: coordinator.isNowPlayingExpanded) { _, expanded in
            if expanded {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
        }
        .onChange(of: coordinator.selectedTab) { _, _ in
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
    }
}
