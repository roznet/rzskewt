import SwiftUI

/// A host-supplied variable plotted against pressure beside the Skew-T.
///
/// The host decides which variables to show (and how many — typically one on
/// iPhone, two on iPad). The `value` closure extracts the plotted quantity from
/// each sounding level; levels for which it returns `nil` are skipped.
public struct SkewTVariable: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let unit: String
    public let color: Color
    /// Fixed x-axis range. When `nil` the panel auto-scales to the data with a small margin.
    public let range: ClosedRange<Double>?
    public let value: @Sendable (SoundingLevel) -> Double?

    public init(
        id: String,
        label: String,
        unit: String = "",
        color: Color = .accentColor,
        range: ClosedRange<Double>? = nil,
        value: @escaping @Sendable (SoundingLevel) -> Double?
    ) {
        self.id = id
        self.label = label
        self.unit = unit
        self.color = color
        self.range = range
        self.value = value
    }
}

/// Side panel that plots one or two host-chosen variables against the same
/// log-pressure axis as ``SkewTView``, so the two line up vertically in an `HStack`.
///
/// - One variable → single x-axis (labelled at the bottom). Suited to iPhone.
/// - Two variables → dual x-axis (first labelled at the bottom, second at the
///   top, each auto-scaled independently). Suited to iPad.
///
/// Pass `selectedPressureHPa` to share the crosshair with a ``SkewTView`` for a
/// linked readout across both views.
///
/// - Important: Construct this panel with the **same `SkewTConfiguration`** as the
///   adjacent ``SkewTView``. Row alignment depends on identical axis ranges and
///   top/bottom margins; a mismatched `config` silently misaligns the pressure rows.
public struct SkewTVariablePanel: View {
    private let profile: SoundingProfile
    private let variables: [SkewTVariable]
    private let config: SkewTConfiguration
    private let selectedPressureHPa: Double?

    public init(
        profile: SoundingProfile,
        variables: [SkewTVariable],
        config: SkewTConfiguration = .default,
        selectedPressureHPa: Double? = nil
    ) {
        self.profile = profile
        // Dual-axis is the practical maximum for a readable side panel.
        self.variables = Array(variables.prefix(2))
        self.config = config
        self.selectedPressureHPa = selectedPressureHPa
    }

    public var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let transform = SkewTTransform(size: size, config: config)
            drawFrame(context: &context, transform: transform)
            for (index, variable) in variables.enumerated() {
                draw(variable: variable, axisIndex: index, context: &context, transform: transform)
            }
            if let p = selectedPressureHPa {
                drawCrosshair(context: &context, transform: transform, pressureHPa: p)
            }
        }
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Drawing

    private func drawFrame(context: inout GraphicsContext, transform: SkewTTransform) {
        let plot = transform.plotArea
        let rect = CGRect(x: plot.left, y: plot.top, width: plot.width, height: plot.height)
        context.stroke(Path(rect), with: .color(.gray.opacity(0.4)), lineWidth: config.gridLineWidth)

        // Pressure gridlines aligned with the Skew-T's vertical axis — same level set
        // as the diagram (single source of truth) so the rows match exactly.
        for p in transform.visiblePressureLevels {
            let y = transform.pressureToY(p)
            var line = Path()
            line.move(to: CGPoint(x: plot.left, y: y))
            line.addLine(to: CGPoint(x: plot.right, y: y))
            context.stroke(line, with: .color(.gray.opacity(0.18)), lineWidth: config.gridLineWidth)
        }
    }

    private func draw(
        variable: SkewTVariable,
        axisIndex: Int,
        context: inout GraphicsContext,
        transform: SkewTTransform
    ) {
        let plot = transform.plotArea
        let samples = profile.levels
            .compactMap { level -> (p: Double, v: Double)? in
                guard let v = variable.value(level) else { return nil }
                return (level.pressureHPa, v)
            }
            .sorted { $0.p > $1.p }
        guard samples.count >= 1 else { return }

        let bounds = variable.range ?? autoRange(samples.map(\.v))
        let span = bounds.upperBound - bounds.lowerBound
        func xFor(_ v: Double) -> CGFloat {
            let frac = span == 0 ? 0.5 : (v - bounds.lowerBound) / span
            return plot.left + CGFloat(min(max(frac, 0), 1)) * plot.width
        }

        if samples.count == 1 {
            // A single point has no line segment to stroke — draw a dot so the
            // value is still visible.
            let s = samples[0]
            let pt = CGPoint(x: xFor(s.v), y: transform.pressureToY(s.p))
            let r = config.profileLineWidth + 1
            context.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                with: .color(variable.color)
            )
        } else {
            var path = Path()
            for (i, s) in samples.enumerated() {
                let pt = CGPoint(x: xFor(s.v), y: transform.pressureToY(s.p))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(variable.color), lineWidth: config.profileLineWidth)
        }

        drawAxisLabels(
            variable: variable, bounds: bounds, atTop: axisIndex == 1,
            context: &context, transform: transform
        )
    }

    private func drawAxisLabels(
        variable: SkewTVariable,
        bounds: ClosedRange<Double>,
        atTop: Bool,
        context: inout GraphicsContext,
        transform: SkewTTransform
    ) {
        let plot = transform.plotArea
        let y = atTop ? plot.top - 9 : plot.bottom + 9
        func label(_ text: String, x: CGFloat, anchor: UnitPoint) {
            context.draw(
                Text(text).font(.system(size: 8)).foregroundColor(variable.color),
                at: CGPoint(x: x, y: y), anchor: anchor
            )
        }
        label(format(bounds.lowerBound), x: plot.left, anchor: .leading)
        label(format(bounds.upperBound), x: plot.right, anchor: .trailing)
        let title = variable.unit.isEmpty ? variable.label : "\(variable.label) (\(variable.unit))"
        label(title, x: plot.midX, anchor: .center)
    }

    private func drawCrosshair(context: inout GraphicsContext, transform: SkewTTransform, pressureHPa: Double) {
        guard let (a, b) = transform.crosshairEndpoints(atPressureHPa: pressureHPa) else { return }
        context.strokeCrosshair(from: a, to: b, color: config.overlayStyle.cursorColor)
    }

    // MARK: - Helpers

    private func autoRange(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let margin = (hi - lo) * 0.08
        return (lo - margin)...(hi + margin)
    }

    private func format(_ v: Double) -> String {
        abs(v) >= 100 || v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private var accessibilityDescription: String {
        let names = variables.map(\.label).joined(separator: ", ")
        return variables.isEmpty ? "Variable panel" : "Variable panel plotting \(names) against pressure"
    }
}

private extension SkewTTransform.PlotArea {
    var midX: CGFloat { left + width / 2 }
}

// MARK: - Preview

#Preview("Variable Panel — dual") {
    HStack(spacing: 0) {
        SkewTView(profile: .previewSample)
        SkewTVariablePanel(
            profile: .previewSample,
            variables: [
                SkewTVariable(id: "rh", label: "RH", unit: "%", color: .blue, range: 0...100) { level in
                    guard let td = level.dewpointC else { return nil }
                    let e = Thermodynamics.saturationVaporPressure(tempC: td)
                    let es = Thermodynamics.saturationVaporPressure(tempC: level.temperatureC)
                    return es == 0 ? nil : min(100, 100 * e / es)
                },
                SkewTVariable(id: "wind", label: "Wind", unit: "kt", color: .purple) { $0.windSpeedKt },
            ]
        )
        .frame(width: 160)
    }
    .frame(width: 700, height: 600)
}
