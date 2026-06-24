import SwiftUI

/// Horizontal altitude bands for cloud, icing, and inversion overlays.
public enum OverlayBandsRenderer {
    public static func render(
        context: inout GraphicsContext,
        transform: SkewTTransform,
        overlays: SkewTOverlays,
        config: SkewTConfiguration
    ) {
        let plot = transform.plotArea
        let plotRect = CGRect(x: plot.left, y: plot.top, width: plot.width, height: plot.height)

        for band in overlays.cloudLayers {
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: band.baseFt, topFt: band.topFt,
                color: Color.white.opacity(cloudAlpha(for: band.label))
            )
        }
        for band in overlays.icingZones {
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: band.baseFt, topFt: band.topFt,
                color: icingColor(for: band.label)
            )
        }
        for inv in overlays.inversions {
            let opacity = min(0.65, 0.15 + 0.5 * min(inv.strengthC / 3.0, 1.0))
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: inv.baseFt, topFt: inv.topFt,
                color: Color(red: 233 / 255, green: 30 / 255, blue: 99 / 255, opacity: opacity)
            )
        }
        if let lfc = overlays.convectiveLfcFt, let el = overlays.convectiveElFt {
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: lfc, topFt: el,
                color: Color.orange.opacity(0.18)
            )
        }
        if let cruise = overlays.cruiseAltitudeFt {
            let p = Thermodynamics.altitudeToPressure(cruise)
            if p >= config.pTop && p <= config.pBottom {
                let y = transform.pressureToY(p)
                var path = Path()
                path.move(to: CGPoint(x: plot.left, y: y))
                path.addLine(to: CGPoint(x: plot.right, y: y))
                context.stroke(path, with: .color(.primary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private static func drawBand(
        context: inout GraphicsContext,
        transform: SkewTTransform,
        plotRect: CGRect,
        baseFt: Double,
        topFt: Double,
        color: Color
    ) {
        let baseP = Thermodynamics.altitudeToPressure(baseFt)
        let topP = Thermodynamics.altitudeToPressure(topFt)
        let yTop = transform.pressureToY(max(baseP, topP))
        let yBase = transform.pressureToY(min(baseP, topP))
        guard yBase > yTop else { return }
        let rect = CGRect(x: plotRect.minX, y: yTop, width: plotRect.width, height: yBase - yTop)
        context.fill(Path(rect), with: .color(color))
    }

    private static func cloudAlpha(for label: String) -> Double {
        switch label.uppercased() {
        case "OVC": return 0.55
        case "BKN": return 0.40
        case "SCT": return 0.28
        case "FEW": return 0.15
        default: return 0.35
        }
    }

    private static func icingColor(for risk: String) -> Color {
        switch risk.lowercased() {
        case "light": return Color(red: 0.4, green: 0.6, blue: 1.0, opacity: 0.30)
        case "moderate": return Color(red: 1.0, green: 0.6, blue: 0.2, opacity: 0.38)
        case "severe": return Color(red: 1.0, green: 0.2, blue: 0.2, opacity: 0.45)
        default: return Color.blue.opacity(0.2)
        }
    }
}
