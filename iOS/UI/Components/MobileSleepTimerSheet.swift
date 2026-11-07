import SwiftUI

/// Bedtime Sleep Timer modal sheet conforming to Apple Human Interface Guidelines
public struct MobileSleepTimerSheet: View {
    @ObservedObject private var player = AudioPlayerEngine.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    private var isLight: Bool {
        colorScheme == .light
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(player.sleepTimerRemainingSeconds > 0 ? FluidTheme.musicRed : .primary)
                    
                    Text("Sleep Timer")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                
                if player.sleepTimerRemainingSeconds > 0 {
                    Text("Music stops in \(player.formattedSleepTimerRemaining)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(FluidTheme.musicRed)
                } else {
                    Text("Music will gently fade out when the timer ends.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            
            // Timer Options
            VStack(spacing: 8) {
                ForEach(SleepTimerOption.allCases) { opt in
                    if opt != .off {
                        timerRow(opt: opt)
                    }
                }
                
                // Turn Off Option (if active)
                if player.sleepTimerRemainingSeconds > 0 || player.sleepTimerOption != .off {
                    Divider()
                        .padding(.vertical, 4)
                    
                    Button {
                        MobileHaptics.trigger(.selection)
                        player.setSleepTimer(.off)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Turn Off Timer")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            
            Spacer(minLength: 20)
        }
        .presentationDetents([.fraction(player.sleepTimerOption == .off ? 0.50 : 0.58)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .background(isLight ? Color(UIColor.systemBackground) : FluidTheme.cardBackground)
    }
    
    private func timerRow(opt: SleepTimerOption) -> some View {
        let isSelected = player.sleepTimerOption == opt
        
        return Button {
            MobileHaptics.trigger(.selection)
            player.setSleepTimer(opt)
            dismiss()
        } label: {
            HStack {
                Text(opt.rawValue)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? FluidTheme.musicRed : .primary)
                
                Spacer()
                
                if isSelected {
                    HStack(spacing: 6) {
                        if player.sleepTimerRemainingSeconds > 0 {
                            Text(player.formattedSleepTimerRemaining)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(FluidTheme.musicRed)
                        }
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(FluidTheme.musicRed)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? FluidTheme.musicRed.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? FluidTheme.musicRed.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
