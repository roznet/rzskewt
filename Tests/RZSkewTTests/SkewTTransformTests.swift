import CoreGraphics
import Testing
@testable import RZSkewT

@Suite("SkewTTransform")
struct SkewTTransformTests {

    private func makeTransform() -> SkewTTransform {
        SkewTTransform(size: CGSize(width: 600, height: 800))
    }

    @Test("Bottom pressure maps to bottom of plot area")
    func bottomPressure() {
        let t = makeTransform()
        let y = t.pressureToY(t.config.pBottom)
        #expect(abs(y - t.plotArea.bottom) < 1)
    }

    @Test("Top pressure maps to top of plot area")
    func topPressure() {
        let t = makeTransform()
        let y = t.pressureToY(t.config.pTop)
        #expect(abs(y - t.plotArea.top) < 1)
    }

    @Test("Pressure roundtrip: p → y → p")
    func pressureRoundtrip() {
        let t = makeTransform()
        let p: Double = 500
        let y = t.pressureToY(p)
        let pBack = t.yToPressure(y)
        #expect(abs(pBack - p) < 0.1)
    }

    @Test("Temperature roundtrip: T → x → T at same pressure")
    func temperatureRoundtrip() {
        let t = makeTransform()
        let temp: Double = 10
        let p: Double = 700
        let x = t.temperatureToX(temp, atPressure: p)
        let tBack = t.xToTemperature(x, atPressure: p)
        #expect(abs(tBack - temp) < 0.01)
    }

    @Test("Isotherms are skewed: same T at lower pressure maps further right")
    func skewDirection() {
        let t = makeTransform()
        let temp: Double = 0
        let x1000 = t.temperatureToX(temp, atPressure: 1000)
        let x500 = t.temperatureToX(temp, atPressure: 500)
        #expect(x500 > x1000) // skew pushes right at lower pressure
    }

    @Test("Visible pressure levels are within configured range")
    func visibleLevels() {
        let t = makeTransform()
        for p in t.visiblePressureLevels {
            #expect(p >= t.config.pTop)
            #expect(p <= t.config.pBottom)
        }
    }

    @Test("Point helper returns correct CGPoint")
    func pointHelper() {
        let t = makeTransform()
        let pt = t.point(tempC: 0, pressureHPa: 500)
        let x = t.temperatureToX(0, atPressure: 500)
        let y = t.pressureToY(500)
        #expect(abs(pt.x - x) < 0.001)
        #expect(abs(pt.y - y) < 0.001)
    }

    // MARK: - Skew-factor aspect clamp

    /// Horizontal span of one isotherm from the bottom to the top of the plot,
    /// i.e. `skewFactor * plotWidth`. A clean readout of the effective skew.
    private func isothermSpan(_ t: SkewTTransform) -> CGFloat {
        t.temperatureToX(0, atPressure: t.config.pTop)
            - t.temperatureToX(0, atPressure: t.config.pBottom)
    }

    @Test("Tall/narrow plot clamps the skew to the square-aspect value")
    func tallPlotClampsSkew() {
        // height ≫ width (an embedded iPhone-portrait Skew-T). The unclamped
        // factor would be tan45·h/w ≈ 2.5; the clamp pins it at 1.0, so an
        // isotherm spans exactly the plot width from bottom to top.
        let t = SkewTTransform(size: CGSize(width: 280, height: 480))
        #expect(abs(isothermSpan(t) - t.plotArea.width) < 1)
    }

    @Test("Wide plot keeps the true visual 45° skew (clamp inactive)")
    func widePlotKeepsVisualAngle() {
        // width > height → tan45·h/w < 1, below the cap. A true 45° isotherm
        // spans the plot *height* from bottom to top.
        let t = SkewTTransform(size: CGSize(width: 800, height: 400))
        #expect(abs(isothermSpan(t) - t.plotArea.height) < 1)
    }

    @Test("Cold upper-air data stays on the chart on a tall plot")
    func coldUpperAirStaysOnChart() {
        // The regression: without the clamp, cold air aloft skewed off the right
        // edge of a tall/narrow plot.
        let t = SkewTTransform(size: CGSize(width: 280, height: 480))
        let x = t.temperatureToX(-50, atPressure: 250)
        #expect(x >= t.plotArea.left)
        #expect(x <= t.plotArea.right)
    }

    @Test("maxSkewFactor is the square-aspect value")
    func maxSkewFactorValue() {
        #expect(SkewTTransform.maxSkewFactor == 1.0)
    }
}
