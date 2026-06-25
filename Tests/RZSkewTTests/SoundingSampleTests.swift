import Testing
@testable import RZSkewT

@Suite("Sounding sample interpolation")
struct SoundingSampleTests {

    private let profile = SoundingProfile(levels: [
        SoundingLevel(pressureHPa: 1000, altitudeFt: 0, temperatureC: 20, dewpointC: 12,
                      windSpeedKt: 10, windDirectionDeg: 180),
        SoundingLevel(pressureHPa: 850, altitudeFt: 5000, temperatureC: 10, dewpointC: 4,
                      windSpeedKt: 20, windDirectionDeg: 220),
        SoundingLevel(pressureHPa: 500, altitudeFt: 18000, temperatureC: -15, dewpointC: -25,
                      windSpeedKt: 40, windDirectionDeg: 270),
    ])

    @Test("Sample at an exact level returns that level's values")
    func exactLevel() throws {
        let s = try #require(profile.sample(atPressureHPa: 850))
        #expect(abs(s.temperatureC - 10) < 1e-6)
        #expect(abs((s.dewpointC ?? .nan) - 4) < 1e-6)
        #expect(s.windSpeedKt == 20)
    }

    @Test("Sample between levels interpolates monotonically within bounds")
    func betweenLevels() throws {
        let s = try #require(profile.sample(atPressureHPa: 700))
        // 700 hPa sits between 850 (10°C) and 500 (-15°C), so T is in (−15, 10).
        #expect(s.temperatureC < 10 && s.temperatureC > -15)
        #expect(s.dewpointC! < 4 && s.dewpointC! > -25)
        // Altitude likewise bracketed.
        #expect(s.altitudeFt > 5000 && s.altitudeFt < 18000)
    }

    @Test("Log-linear midpoint in pressure")
    func logLinearMidpoint() throws {
        // Geometric mean of 1000 and 850 ≈ 922.3 hPa is the log-pressure midpoint,
        // so T should be the average of 20 and 10 = 15°C.
        let pMid = (1000.0 * 850.0).squareRoot()
        let s = try #require(profile.sample(atPressureHPa: pMid))
        #expect(abs(s.temperatureC - 15) < 0.01)
    }

    @Test("Out-of-range pressure clamps to nearest end")
    func clamps() throws {
        let high = try #require(profile.sample(atPressureHPa: 1200))
        #expect(abs(high.temperatureC - 20) < 1e-6)
        let low = try #require(profile.sample(atPressureHPa: 200))
        #expect(abs(low.temperatureC - (-15)) < 1e-6)
    }

    @Test("Empty profile yields no sample")
    func emptyProfile() {
        #expect(SoundingProfile(levels: []).sample(atPressureHPa: 850) == nil)
    }

    @Test("Missing altitude falls back to standard atmosphere")
    func altitudeFallback() throws {
        let noAlt = SoundingProfile(levels: [
            SoundingLevel(pressureHPa: 1000, temperatureC: 15),
            SoundingLevel(pressureHPa: 500, temperatureC: -20),
        ])
        let s = try #require(noAlt.sample(atPressureHPa: 700))
        let expected = Thermodynamics.pressureToAltitude(700)
        #expect(abs(s.altitudeFt - expected) < 1e-6)
    }

    @Test("One-sided optional uses the present neighbour, even when nearer the missing one")
    func oneSidedOptionalFallback() throws {
        // Only the high-pressure level carries altitude/dewpoint; sample nearer the
        // upper (missing) level. The present neighbour should be used rather than
        // discarded (no standard-atmosphere fallback for altitude).
        let partial = SoundingProfile(levels: [
            SoundingLevel(pressureHPa: 1000, altitudeFt: 0, temperatureC: 15, dewpointC: 10),
            SoundingLevel(pressureHPa: 500, temperatureC: -20),
        ])
        let s = try #require(partial.sample(atPressureHPa: 550))  // f > 0.5, nearer 500 hPa
        #expect(s.altitudeFt == 0)
        #expect(s.dewpointC == 10)
    }
}
