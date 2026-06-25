import SwiftUI

/// Horizontal altitude bands for cloud, icing, inversion and convective overlays.
///
/// Colors come from `config.overlayStyle` (see `SkewTOverlayStyle`) so they are
/// themeable and a single source of truth; the band geometry is computed by the
/// pure, testable `bandRect(...)` helper.
public enum OverlayBandsRenderer {
    public static func render(
        context: inout GraphicsContext,
        transform: SkewTTransform,
        overlays: SkewTOverlays,
        config: SkewTConfiguration
    ) {
        let style = config.overlayStyle
        let plot = transform.plotArea
        let plotRect = CGRect(x: plot.left, y: plot.top, width: plot.width, height: plot.height)

        for band in overlays.cloudLayers {
            // White cloud fills vanish on the light background; a hairline border
            // keeps even thin (FEW) layers locatable.
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: band.baseFt, topFt: band.topFt,
                fill: style.cloudColor.opacity(style.cloudFillOpacity(forCoverage: band.label)),
                border: style.cloudBorderColor
            )
        }
        for band in overlays.icingZones {
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: band.baseFt, topFt: band.topFt,
                fill: style.icingColor(forRisk: band.label)
            )
        }
        for inv in overlays.inversions {
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: inv.baseFt, topFt: inv.topFt,
                fill: style.inversionColor.opacity(style.inversionOpacity(forStrengthC: inv.strengthC))
            )
        }
        if let lfc = overlays.convectiveLfcFt, let el = overlays.convectiveElFt {
            drawBand(
                context: &context, transform: transform, plotRect: plotRect,
                baseFt: lfc, topFt: el,
                fill: style.convectiveColor
            )
        }
        if let cruise = overlays.cruiseAltitudeFt {
            let p = Thermodynamics.altitudeToPressure(cruise)
            if p >= config.pTop && p <= config.pBottom {
                let y = transform.pressureToY(p)
                var path = Path()
                path.move(to: CGPoint(x: plot.left, y: y))
                path.addLine(to: CGPoint(x: plot.right, y: y))
                context.stroke(path, with: .color(style.cruiseLineColor),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    /// Pixel rect for a band between two altitudes, clamped to the plot width, or
    /// `nil` if the band has no height on the diagram. Pure (no `GraphicsContext`)
    /// so the altitude→pressure→pixel geometry is unit-testable.
    static func bandRect(
        transform: SkewTTransform,
        plotRect: CGRect,
        baseFt: Double,
        topFt: Double
    ) -> CGRect? {
        let baseP = Thermodynamics.altitudeToPressure(baseFt)
        let topP = Thermodynamics.altitudeToPressure(topFt)
        // The higher altitude (lower pressure) sits at the top of the plot (smaller y).
        let yTop = transform.pressureToY(min(baseP, topP))
        let yBottom = transform.pressureToY(max(baseP, topP))
        guard yBottom > yTop else { return nil }
        return CGRect(x: plotRect.minX, y: yTop, width: plotRect.width, height: yBottom - yTop)
    }

    private static func drawBand(
        context: inout GraphicsContext,
        transform: SkewTTransform,
        plotRect: CGRect,
        baseFt: Double,
        topFt: Double,
        fill: Color,
        border: Color? = nil
    ) {
        guard let rect = bandRect(transform: transform, plotRect: plotRect, baseFt: baseFt, topFt: topFt) else { return }
        let path = Path(rect)
        context.fill(path, with: .color(fill))
        if let border {
            context.stroke(path, with: .color(border), lineWidth: 0.75)
        }
    }
}
