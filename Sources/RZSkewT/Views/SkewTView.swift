import SwiftUI

/// SwiftUI view that renders a Skew-T log-P diagram for a sounding profile.
public struct SkewTView: View {
    private let profile: SoundingProfile
    private let config: SkewTConfiguration
    @State private var selectedPressureHPa: Double?
    @State private var canvasSize: CGSize = .zero

    public init(profile: SoundingProfile, config: SkewTConfiguration = .default) {
        self.profile = profile
        self.config = config
    }

    private var renderer: SkewTRenderer {
        SkewTRenderer(profile: profile, config: config)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let readout = levelReadout {
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
            }
            GeometryReader { geo in
                Canvas { context, size in
                    renderer.render(context: &context, size: size)
                    if let p = selectedPressureHPa {
                        drawCrosshair(context: &context, size: size, pressureHPa: p)
                    }
                }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectedPressureHPa = pressureAt(y: value.location.y)
                        }
                )
            }
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private func pressureAt(y: CGFloat) -> Double? {
        guard canvasSize.height > 0 else { return nil }
        let transform = SkewTTransform(size: canvasSize, config: config)
        let p = transform.yToPressure(y)
        guard p >= config.pTop && p <= config.pBottom else { return nil }
        return p
    }

    private var levelReadout: String? {
        guard let p = selectedPressureHPa else { return nil }
        guard let level = profile.levels.min(by: { abs($0.pressureHPa - p) < abs($1.pressureHPa - p) }) else { return nil }
        var parts = ["\(Int(level.pressureHPa)) hPa", String(format: "%.1f°C", level.temperatureC)]
        if let td = level.dewpointC { parts.append(String(format: "Td %.1f°C", td)) }
        if let ws = level.windSpeedKt, let wd = level.windDirectionDeg {
            parts.append(String(format: "%.0f/%03.0f", ws, wd))
        }
        return parts.joined(separator: " · ")
    }

    private func drawCrosshair(context: inout GraphicsContext, size: CGSize, pressureHPa: Double) {
        let transform = SkewTTransform(size: size, config: config)
        let plot = transform.plotArea
        let y = transform.pressureToY(pressureHPa)
        guard y >= plot.top && y <= plot.bottom else { return }
        var path = Path()
        path.move(to: CGPoint(x: plot.left, y: y))
        path.addLine(to: CGPoint(x: plot.right, y: y))
        context.stroke(path, with: .color(.red.opacity(0.7)), lineWidth: 1)
    }

    private var accessibilityDescription: String {
        var parts = ["Skew-T log-P diagram", "\(profile.levels.count) sounding levels"]
        if let cape = profile.indices?.capeSurfaceJkg { parts.append("CAPE \(Int(cape)) J per kg") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Sample Sounding") {
    SkewTView(profile: .previewSample)
        .frame(width: 600, height: 800)
}

extension SoundingProfile {
  public static let previewSample = SoundingProfile(
        levels: [
            SoundingLevel(pressureHPa: 1000, temperatureC: 28, dewpointC: 20, windSpeedKt: 5, windDirectionDeg: 180),
            SoundingLevel(pressureHPa: 850, temperatureC: 16, dewpointC: 10, windSpeedKt: 20, windDirectionDeg: 220),
            SoundingLevel(pressureHPa: 500, temperatureC: -15, dewpointC: -30, windSpeedKt: 50, windDirectionDeg: 270),
        ],
        indices: SkewTIndices(lclPressureHPa: 880, capeSurfaceJkg: 1250, cinSurfaceJkg: -45, freezingLevelFt: 12500, liftedIndex: -4.2)
    )
}
