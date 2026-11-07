import Foundation
#if canImport(AVFAudio)
import AVFAudio
#endif
#if os(iOS)
import UIKit
import SwiftUI
import AVKit
#endif

/// Configures iOS background audio playback and hardware route handling.
/// When running on iOS, this registers the audio session with the system to enable:
/// 1. Background audio playback when the screen is locked or app is minimized.
/// 2. Lock screen media controls and Dynamic Island live activity integration.
/// 3. Headphone disconnect auto-pause and Bluetooth route switching.
/// 4. Real-time dynamic audio output route detection (AirPods, Speaker, Bluetooth, CarPlay).
public final class iOSAudioSessionManager: ObservableObject, @unchecked Sendable {
    public static let shared = iOSAudioSessionManager()
    private var isConfigured = false
    private var wasPlayingBeforeInterruption = false
    
    @Published public var currentRouteName: String = "iPhone Speaker"
    @Published public var currentRouteIcon: String = "speaker.wave.2.fill"
    
    private init() {}
    
    @MainActor
    public func configurePlaybackSession() {
        #if os(iOS)
        guard !isConfigured else { return }
        isConfigured = true
        
        let session = AVAudioSession.sharedInstance()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
                try session.setActive(true)
            } catch {
                print("[Sonorist iOS] Failed to activate AVAudioSession: \(error)")
            }
        }
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        AudioPlayerEngine.shared.setupRemoteCommands()
        
        // Initial route detection
        updateCurrentAudioRoute()
        
        // 1. Listen for route changes (e.g. unplugging AirPods / disconnecting Bluetooth)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
        
        // 2. Listen for phone calls, FaceTime, alarms, Siri interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        #endif
    }
    
    #if os(iOS)
    @MainActor
    public func updateCurrentAudioRoute() {
        DispatchQueue.global(qos: .userInitiated).async {
            let route = AVAudioSession.sharedInstance().currentRoute
            guard let output = route.outputs.first else {
                DispatchQueue.main.async {
                    self.currentRouteName = "iPhone Speaker"
                    self.currentRouteIcon = "speaker.wave.2.fill"
                }
                return
            }
            
            let portType = output.portType
            let portName = output.portName
            var name: String
            var icon: String
            
            switch portType {
            case .headphones, .headsetMic:
                name = portName.isEmpty ? "Headphones" : portName
                icon = "headphones"
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                name = portName.isEmpty ? "Bluetooth" : portName
                let lower = portName.lowercased()
                if lower.contains("airpods pro") {
                    icon = "airpodspro"
                } else if lower.contains("airpods max") {
                    icon = "airpodsmax"
                } else if lower.contains("airpods") {
                    icon = "airpods"
                } else {
                    icon = "headphones"
                }
            case .airPlay:
                name = portName.isEmpty ? "AirPlay" : portName
                icon = "airplayaudio"
            case .carAudio:
                name = "CarPlay"
                icon = "car.fill"
            case .builtInSpeaker:
                name = "iPhone Speaker"
                icon = "speaker.wave.2.fill"
            case .builtInReceiver:
                name = "iPhone Receiver"
                icon = "phone.fill"
            default:
                name = portName.isEmpty ? "Speaker" : portName
                icon = "speaker.wave.2.fill"
            }
            
            DispatchQueue.main.async {
                self.currentRouteName = name
                self.currentRouteIcon = icon
            }
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        Task { @MainActor in
            self.updateCurrentAudioRoute()
        }
        
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Auto-pause if headphones or external speaker disconnected
        if reason == .oldDeviceUnavailable {
            Task { @MainActor in
                AudioPlayerEngine.shared.pause()
            }
        }
    }
    
    /// Handles incoming phone calls, FaceTime, Siri, and alarm interruptions.
    /// When an incoming call begins: pauses playback smoothly and saves head position.
    /// When the call is hung up / disconnected: automatically resumes playback from where it stopped.
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            Task { @MainActor in
                let player = AudioPlayerEngine.shared
                self.wasPlayingBeforeInterruption = player.isPlaying
                if self.wasPlayingBeforeInterruption {
                    player.pause()
                }
            }
            
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            Task { @MainActor in
                let player = AudioPlayerEngine.shared
                player.assertAudioSession()
                
                // If iOS signals .shouldResume or the track was actively playing when the phone rang
                if options.contains(.shouldResume) || self.wasPlayingBeforeInterruption {
                    self.wasPlayingBeforeInterruption = false
                    player.resume()
                }
            }
            
        @unknown default:
            break
        }
    }
    #endif
}

#if os(iOS)
/// Native iOS AirPlay / Audio Route Picker overlay.
/// When overlaid on the route indicator, tapping pops up Apple's system audio sheet.
public struct AirPlayRoutePickerOverlay: UIViewRepresentable {
    public init() {}
    
    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.backgroundColor = .clear
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        picker.prioritizesVideoDevices = false
        // Make inner button nearly transparent so custom SwiftUI design displays cleanly underneath
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.alpha = 0.015
            }
        }
        return picker
    }
    
    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
