import CoreGraphics
import Foundation
import Testing
@testable import RZSkewT

@Suite("Overlay bands")
struct OverlayBandsTests {

    private func makeTransform() -> SkewTTransform {
        SkewTTransform(size: CGSize(width: 600, height: 800))
    }

    private var plotRect: CGRect {
        let p = makeTransform().plotArea
        return CGRect(x: p.left, y: p.top, width: p.width, height: p.height)
    }

    // MARK: - Band geometry

    @Test("Band rect spans full plot width and has positive height")
    func bandRectBasic() throws {
        let t = makeTransform()
        let rect = try #require(OverlayBandsRenderer.bandRect(
            transform: t, plotRect: plotRect, baseFt: 3000, topFt: 8000))
        #expect(abs(rect.minX - plotRect.minX) < 1e-6)
        #expect(abs(rect.width - plotRect.width) < 1e-6)
        #expect(rect.height > 0)
    }

    @Test("Higher band sits higher on the diagram (smaller y)")
    func bandRectOrdering() throws {
        let t = makeTransform()
        let low = try #require(OverlayBandsRenderer.bandRect(
            transform: t, plotRect: plotRect, baseFt: 1000, topFt: 3000))
        let high = try #require(OverlayBandsRenderer.bandRect(
            transform: t, plotRect: plotRect, baseFt: 20000, topFt: 25000))
        #expect(high.minY < low.minY)
    }

    @Test("Inverted base/top produces the same rect as the right way round")
    func bandRectInverted() throws {
        let t = makeTransform()
        let normal = try #require(OverlayBandsRenderer.bandRect(
            transform: t, plotRect: plotRect, baseFt: 3000, topFt: 8000))
        let inverted = try #require(OverlayBandsRenderer.bandRect(
            transform: t, plotRect: plotRect, baseFt: 8000, topFt: 3000))
        #expect(abs(normal.minY - inverted.minY) < 1e-6)
        #expect(abs(normal.height - inverted.height) < 1e-6)
    }

    @Test("Zero-thickness band yields no rect")
    func bandRectZeroThickness() {
        let t = makeTransform()
        #expect(OverlayBandsRenderer.bandRect(
            transform: t, plotRect: plotRect, baseFt: 5000, topFt: 5000) == nil)
    }

    // MARK: - Style mappings

    @Test("Cloud fill opacity increases with coverage")
    func cloudOpacityRamp() {
        let s = SkewTOverlayStyle.default
        #expect(s.cloudFillOpacity(forCoverage: "FEW") < s.cloudFillOpacity(forCoverage: "SCT"))
        #expect(s.cloudFillOpacity(forCoverage: "SCT") < s.cloudFillOpacity(forCoverage: "BKN"))
        #expect(s.cloudFillOpacity(forCoverage: "BKN") < s.cloudFillOpacity(forCoverage: "OVC"))
    }

    @Test("Cloud coverage label is case-insensitive with a default fallback")
    func cloudOpacityCaseAndDefault() {
        let s = SkewTOverlayStyle.default
        #expect(s.cloudFillOpacity(forCoverage: "ovc") == s.cloudFillOpacity(forCoverage: "OVC"))
        #expect(s.cloudFillOpacity(forCoverage: "???") == 0.35)
    }

    @Test("Icing risk maps to distinct colours, unknown to default")
    func icingColors() {
        let s = SkewTOverlayStyle.default
        #expect(s.icingColor(forRisk: "severe") == s.icingSevereColor)
        #expect(s.icingColor(forRisk: "Moderate") == s.icingModerateColor)
        #expect(s.icingColor(forRisk: "unknown") == s.icingDefaultColor)
    }

    @Test("Inversion opacity is monotonic in strength and clamped")
    func inversionOpacity() {
        let s = SkewTOverlayStyle.default
        #expect(s.inversionOpacity(forStrengthC: 0) < s.inversionOpacity(forStrengthC: 1.5))
        #expect(s.inversionOpacity(forStrengthC: 1.5) < s.inversionOpacity(forStrengthC: 3))
        // Clamped above for very strong inversions.
        #expect(s.inversionOpacity(forStrengthC: 100) <= 0.65)
        #expect(s.inversionOpacity(forStrengthC: 3) == s.inversionOpacity(forStrengthC: 10))
    }

    // MARK: - Model

    @Test("Empty overlays carry no convective zone")
    func emptyOverlays() {
        #expect(SkewTOverlays.empty.convectiveLfcFt == nil)
        #expect(SkewTOverlays.empty.convectiveElFt == nil)
    }

    @Test("SkewTOverlays Codable roundtrip including convective fields")
    func overlaysCodable() throws {
        let overlays = SkewTOverlays(
            cloudLayers: [OverlayBand(baseFt: 2000, topFt: 6000, label: "BKN")],
            icingZones: [OverlayBand(baseFt: 8000, topFt: 12000, label: "moderate")],
            inversions: [InversionBand(baseFt: 1000, topFt: 2000, strengthC: 2.5)],
            cruiseAltitudeFt: 9000,
            convectiveLfcFt: 4000,
            convectiveElFt: 28000
        )
        let data = try JSONEncoder().encode(overlays)
        let decoded = try JSONDecoder().decode(SkewTOverlays.self, from: data)
        #expect(decoded == overlays)
    }

    @Test("Renderer accepts a profile carrying overlays")
    func rendererWithOverlays() {
        let profile = SoundingProfile(
            levels: [
                SoundingLevel(pressureHPa: 1000, temperatureC: 20, dewpointC: 14),
                SoundingLevel(pressureHPa: 500, temperatureC: -15, dewpointC: -25),
            ],
            overlays: SkewTOverlays(
                cloudLayers: [OverlayBand(baseFt: 2000, topFt: 6000, label: "OVC")],
                icingZones: [], inversions: [], cruiseAltitudeFt: 9000,
                convectiveLfcFt: 4000, convectiveElFt: 20000
            )
        )
        let renderer = SkewTRenderer(profile: profile)
        #expect(renderer.profile.overlays.cloudLayers.count == 1)
    }
}
