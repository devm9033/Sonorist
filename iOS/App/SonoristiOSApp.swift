import SwiftUI

#if os(iOS)
/// Native iOS Entry Point for Sonorist on iPhone 17 (iOS 18+)
@main
struct SonoristiOSApp: App {
    @ObservedObject private var themeManager = AppThemeManager.shared
    
    init() {
        // High-performance image and network cache (50 MB Memory, 200 MB Disk)
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "SonoristHTTPCache")
        URLCache.shared = cache
        
        iOSAudioSessionManager.shared.configurePlaybackSession()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let scheme = themeManager.currentTheme.colorScheme {
                    MobileRootView()
                        .preferredColorScheme(scheme)
                } else {
                    MobileRootView()
                }
            }
            .onAppear {
                themeManager.applyAppearance()
            }
        }
    }
}
#endif
