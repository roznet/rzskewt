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
    /// When true the auto-scaled range is symmetrized around zero and a dashed
    /// zero reference line is drawn (for signed quantities like headwind/lapse).
    public let zeroLine: Bool
    public let value: @Sendable (SoundingLevel) -> Double?
    /// Optional second line plotted on the SAME axis as `value` (e.g. crosswind
    /// alongside headwind), in `secondaryColor`. The shared range spans both.
    public let secondaryValue: (@Sendable (SoundingLevel) -> Double?)?
    public let secondaryColor: Color?

    public init(
        id: String,
        label: String,
        unit: String = "",
        color: Color = .accentColor,
        range: ClosedRange<Double>? = nil,
        zeroLine: Bool = false,
        secondaryValue: (@Sendable (SoundingLevel) -> Double?)? = nil,
        secondaryColor: Color? = nil,
        value: @escaping @Sendable (SoundingLevel) -> Double?
    ) {
        self.id = id
        self.label = label
        self.unit = unit
        self.color = color
        self.range = range
        self.zeroLine = zeroLine
        self.secondaryValue = secondaryValue
        self.secondaryColor = secondaryColor
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
        let primary = samples(for: variable.value)
        let secondary = variable.secondaryValue.map { samples(for: $0) } ?? []
        guard !primary.isEmpty || !secondary.isEmpty else { return }

        // Shared range spans both lines so primary + secondary use one scale.
        let bounds: ClosedRange<Double>
        if let fixed = variable.range {
            bounds = fixed
        } else {
            var range = autoRange(primary.map(\.v) + secondary.map(\.v))
            if variable.zeroLine {
                let absMax = Swift.max(abs(range.lowerBound), abs(range.upperBound))
                range = (absMax == 0 ? -1 : -absMax)...(absMax == 0 ? 1 : absMax)
            }
            bounds = range
        }
        let span = bounds.upperBound - bounds.lowerBound
        func xFor(_ v: Double) -> CGFloat {
            let frac = span == 0 ? 0.5 : (v - bounds.lowerBound) / span
            return plot.left + CGFloat(min(max(frac, 0), 1)) * plot.width
        }

        // Dashed zero reference for signed quantities.
        if variable.zeroLine, bounds.lowerBound < 0, bounds.upperBound > 0 {
            let zx = xFor(0)
            var zero = Path()
            zero.move(to: CGPoint(x: zx, y: plot.top))
            zero.addLine(to: CGPoint(x: zx, y: plot.bottom))
            context.stroke(zero, with: .color(.gray.opacity(0.5)),
                           style: StrokeStyle(lineWidth: config.gridLineWidth, dash: [2, 2]))
        }

        drawLine(primary, color: variable.color, xFor: xFor, context: &context, transform: transform)
        if let secondaryColor = variable.secondaryColor, !secondary.isEmpty {
            drawLine(secondary, color: secondaryColor, xFor: xFor, context: &context, transform: transform)
        }

        drawAxisLabels(
            variable: variable, bounds: bounds, atTop: axisIndex == 1,
            context: &context, transform: transform
        )
    }

    /// Sounding samples for a value closure, sorted high→low pressure.
    private func samples(for value: @Sendable (SoundingLevel) -> Double?) -> [(p: Double, v: Double)] {
        profile.levels
            .compactMap { level -> (p: Double, v: Double)? in
                guard let v = value(level) else { return nil }
                return (level.pressureHPa, v)
            }
            .sorted { $0.p > $1.p }
    }

    private func drawLine(
        _ samples: [(p: Double, v: Double)],
        color: Color,
        xFor: (Double) -> CGFloat,
        context: inout GraphicsContext,
        transform: SkewTTransform
    ) {
        guard !samples.isEmpty else { return }
        if samples.count == 1 {
            // A single point has no line segment to stroke — draw a dot so the
            // value is still visible.
            let s = samples[0]
            let pt = CGPoint(x: xFor(s.v), y: transform.pressureToY(s.p))
            let r = config.profileLineWidth + 1
            context.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                with: .color(color)
            )
        } else {
            var path = Path()
            for (i, s) in samples.enumerated() {
                let pt = CGPoint(x: xFor(s.v), y: transform.pressureToY(s.p))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), lineWidth: config.profileLineWidth)
        }
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
