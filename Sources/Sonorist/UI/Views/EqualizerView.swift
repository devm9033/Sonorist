import SwiftUI

@MainActor
public final class EqualizerViewModel: ObservableObject {
    public static let shared = EqualizerViewModel()
    @Published public var showPresetPopover: Bool = false
    public init() {}
}

public struct EqualizerView: View {
    @ObservedObject var eqModel = EqualizerViewModel.shared
    @ObservedObject var player = AudioPlayerEngine.shared
    @Environment(\.dismiss) private var dismiss
    
    private let frequencies = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    private let presets = ["Flat", "Acoustic", "Bass Booster", "Bass Reducer", "Classical", "Electronic", "Hip-Hop", "Jazz", "Pop", "Rock", "Vocal Booster"]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
                .opacity(0.25)
            
            VStack(spacing: 14) {
                // Top Frequency Response Curve Visualizer
                curveDisplayCard
                
                // Hardware Mixer Sliders Card
                slidersCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 630, height: 420)
        .background(FluidTheme.barMaterial)
    }
    
    // MARK: - Header Bar
    
    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 12) {
            // App / Modal Title
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(FluidTheme.musicRed)
                        .frame(width: 22, height: 22)
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("Equalizer")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(width: 110, alignment: .leading)
            
            Spacer()
            
            // Master Active Toggle Switch Pill
            Toggle(isOn: Binding(
                get: { player.isEqualizerEnabled },
                set: { player.isEqualizerEnabled = $0; FluidHaptics.toggle() }
            )) {
                Text(player.isEqualizerEnabled ? "Active" : "Bypassed")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(player.isEqualizerEnabled ? .primary : .secondary)
            }
            .toggleStyle(SwitchToggleStyle(tint: FluidTheme.musicRed))
            
            // Preset Popover Trigger Button (Sleep Timer / Audio Quality Popover style)
            Button(action: {
                FluidHaptics.tap()
                eqModel.showPresetPopover.toggle()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 10, weight: .bold))
                    Text(player.equalizerPreset)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(eqModel.showPresetPopover ? FluidTheme.musicRed.opacity(0.25) : Color.primary.opacity(0.08))
                .foregroundColor(eqModel.showPresetPopover ? FluidTheme.musicRed : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(eqModel.showPresetPopover ? FluidTheme.musicRed.opacity(0.4) : Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Select Audio Equalizer Preset")
            .popover(isPresented: $eqModel.showPresetPopover, arrowEdge: .top) {
                presetPopoverContent
            }
            
            // Reset Button
            Button(action: {
                FluidHaptics.tap()
                withAnimation(FluidTheme.fluidSpring) {
                    player.applyPreset("Flat")
                    player.equalizerPreamp = 0
                }
            }) {
                Text("Reset")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset all EQ bands to 0 dB Flat")
            
            Spacer()
            
            // Close Button
            Button(action: {
                FluidHaptics.tap()
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 40, alignment: .trailing)
            .keyboardShortcut(.cancelAction)
            .help("Close Equalizer (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Sleep-Timer-Style Preset Popover Card
    
    @ViewBuilder
    private var presetPopoverContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "slider.vertical.3")
                    .foregroundColor(FluidTheme.musicRed)
                    .font(.system(size: 11, weight: .bold))
                Text("Equalizer Presets")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            
            Divider()
                .opacity(0.3)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(presets, id: \.self) { preset in
                        presetRow(preset: preset)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(4)
        .frame(width: 185)
    }
    
    @ViewBuilder
    private func presetRow(preset: String) -> some View {
        let isSelected = player.equalizerPreset == preset
        Button(action: {
            FluidHaptics.toggle()
            withAnimation(FluidTheme.fluidSpring) {
                player.applyPreset(preset)
            }
            eqModel.showPresetPopover = false
        }) {
            HStack {
                Text(preset)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? FluidTheme.musicRed : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(FluidTheme.musicRed)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePopoverRowStyle(isSelected: isSelected))
    }
    
    // MARK: - Frequency Curve Display Card
    
    @ViewBuilder
    private var curveDisplayCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let midY = h / 2
                let count = player.equalizerBands.count
                let leftMargin: CGFloat = 36
                let rightMargin: CGFloat = 20
                let usableW = w - leftMargin - rightMargin
                let step = usableW / CGFloat(max(1, count - 1))
                
                // Reference dB Grid Lines
                Path { path in
                    // +12dB
                    path.move(to: CGPoint(x: leftMargin, y: 14))
                    path.addLine(to: CGPoint(x: w - rightMargin, y: 14))
                    // 0dB center line
                    path.move(to: CGPoint(x: leftMargin, y: midY))
                    path.addLine(to: CGPoint(x: w - rightMargin, y: midY))
                    // -12dB
                    path.move(to: CGPoint(x: leftMargin, y: h - 14))
                    path.addLine(to: CGPoint(x: w - rightMargin, y: h - 14))
                }
                .stroke(Color.primary.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Scale text on left
                VStack(alignment: .trailing) {
                    Text("+12").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("0").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("-12").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                }
                .frame(width: 24, height: h - 24)
                .position(x: 16, y: midY)
                
                // Points
                let points: [CGPoint] = (0..<count).map { i in
                    let val = player.isEqualizerEnabled ? player.equalizerBands[i] : 0
                    let y = midY - CGFloat(val / 12.0) * (midY - 16)
                    let x = leftMargin + CGFloat(i) * step
                    return CGPoint(x: x, y: y)
                }
                
                // Gradient Fill Under Curve
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: midY))
                        path.addLine(to: points[0])
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midX = (p0.x + p1.x) / 2
                            path.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
                        }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: midY))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                (player.isEqualizerEnabled ? FluidTheme.musicRed : Color.secondary).opacity(0.20),
                                (player.isEqualizerEnabled ? FluidTheme.musicRed : Color.secondary).opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Smooth Stroke Curve
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midX = (p0.x + p1.x) / 2
                            path.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
                        }
                    }
                    .stroke(
                        player.isEqualizerEnabled ? FluidTheme.musicRed : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Node Dots
                    ForEach(0..<points.count, id: \.self) { i in
                        Circle()
                            .fill(player.isEqualizerEnabled ? FluidTheme.musicRed : Color.secondary)
                            .frame(width: 5, height: 5)
                            .position(points[i])
                    }
                }
            }
        }
        .frame(height: 72)
    }
    
    // MARK: - Sliders Hardware Mixer Card
    
    @ViewBuilder
    private var slidersCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            
            HStack(spacing: 0) {
                // Preamp Column
                VStack(spacing: 4) {
                    Text(String(format: "%+.1f", player.equalizerPreamp))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(player.equalizerPreamp != 0 ? FluidTheme.musicRed : .secondary)
                        .frame(height: 14)
                    
                    VerticalDBSlider(
                        value: Binding(
                            get: { player.equalizerPreamp },
                            set: { player.equalizerPreamp = $0 }
                        ),
                        isEnabled: player.isEqualizerEnabled
                    )
                    
                    Text("Preamp")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(height: 14)
                }
                .frame(width: 60)
                .padding(.vertical, 12)
                
                // Vertical Separator
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 10)
                
                // 10 Frequency Band Sliders (Clean, uncluttered layout)
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { index in
                        VStack(spacing: 4) {
                            Text(String(format: "%+.1f", player.equalizerBands[index]))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(player.equalizerBands[index] != 0 ? FluidTheme.musicRed : .secondary.opacity(0.7))
                                .frame(height: 14)
                            
                            VerticalDBSlider(
                                value: Binding(
                                    get: { player.equalizerBands[index] },
                                    set: { player.setBand(index: index, value: $0) }
                                ),
                                isEnabled: player.isEqualizerEnabled
                            )
                            
                            Text(frequencies[index])
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(height: 14)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Native Tactile Vertical dB Slider

public struct VerticalDBSlider: View {
    @Binding var value: Double // -12 to +12
    let isEnabled: Bool
    
    private let trackHeight: CGFloat = 118
    
    public init(value: Binding<Double>, isEnabled: Bool) {
        self._value = value
        self.isEnabled = isEnabled
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 4, height: trackHeight)
                
                // Center 0dB Tick Marker
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 12, height: 1)
                
                // Slider Thumb (Hardware mixer style with Apple metal/glass cap)
                let normalized = CGFloat((value + 12.0) / 24.0) // 0...1
                let yOffset = (trackHeight / 2) - (normalized * trackHeight)
                
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isEnabled ? Color.white : Color(white: 0.4))
                    .frame(width: 22, height: 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                    )
                    .overlay(
                        Rectangle()
                            .fill(isEnabled ? FluidTheme.musicRed : Color.secondary)
                            .frame(height: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .offset(y: yOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let mid = trackHeight / 2
                        let deltaY = mid - gesture.location.y
                        let ratio = max(-1.0, min(1.0, deltaY / mid))
                        let target = Double(ratio * 12.0)
                        
                        // Snap smoothly to 0dB with physical Taptic feedback
                        if abs(target) < 0.4 {
                            if value != 0 {
                                FluidHaptics.snap()
                            }
                            value = 0
                        } else {
                            value = target
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }
}
