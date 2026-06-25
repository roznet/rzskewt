import Foundation

// MARK: - Atmospheric data point

/// A point in temperature-pressure space on a Skew-T diagram.
public struct AtmosphericPoint: Sendable, Equatable, Hashable, Codable {
    public let tempC: Double
    public let pressureHPa: Double

    public init(tempC: Double, pressureHPa: Double) {
        self.tempC = tempC
        self.pressureHPa = pressureHPa
    }
}

// MARK: - Computation result types

/// Result of a Lifting Condensation Level computation.
public struct LCLResult: Sendable, Equatable, Hashable {
    public let pressureHPa: Double
    public let tempC: Double
}

/// Result of CAPE and CIN computation (J/kg).
public struct CAPECINResult: Sendable, Equatable, Hashable {
    public let cape: Double
    public let cin: Double
}

/// A constant-mixing-ratio line with its value (g/kg) and curve points.
public struct MixingRatioLine: Sendable, Equatable, Hashable {
    public let mixingRatioGkg: Double
    public let points: [AtmosphericPoint]
}

// MARK: - Sounding data

/// A single pressure level in a sounding profile.
public struct SoundingLevel: Sendable, Equatable, Hashable, Codable {
    public let pressureHPa: Double
    public let altitudeFt: Double?
    public let temperatureC: Double
    public let dewpointC: Double?
    public let windSpeedKt: Double?
    public let windDirectionDeg: Double?

    public init(
        pressureHPa: Double,
        altitudeFt: Double? = nil,
        temperatureC: Double,
        dewpointC: Double? = nil,
        windSpeedKt: Double? = nil,
        windDirectionDeg: Double? = nil
    ) {
        self.pressureHPa = pressureHPa
        self.altitudeFt = altitudeFt
        self.temperatureC = temperatureC
        self.dewpointC = dewpointC
        self.windSpeedKt = windSpeedKt
        self.windDirectionDeg = windDirectionDeg
    }
}

/// Complete sounding data for a Skew-T plot.
public struct SoundingProfile: Sendable, Equatable, Hashable, Codable {
    public let levels: [SoundingLevel]
    public let indices: SkewTIndices?
    public let overlays: SkewTOverlays

    public init(levels: [SoundingLevel], indices: SkewTIndices? = nil, overlays: SkewTOverlays = .empty) {
        self.levels = levels
        self.indices = indices
        self.overlays = overlays
    }

    /// Interpolate the profile at an arbitrary pressure for cursor readouts and host sync.
    ///
    /// Temperature, dewpoint and altitude are log-linearly interpolated between the two
    /// bracketing levels (linear in `ln(p)`, which matches the diagram's vertical axis).
    /// Wind is taken from the nearest level (no circular interpolation of direction).
    /// Returns `nil` if the profile is empty.
    public func sample(atPressureHPa p: Double) -> SkewTSample? {
        guard !levels.isEmpty else { return nil }
        // Soundings are normally supplied high → low pressure; only pay for a sort when
        // they aren't, so the interactive (per-drag) path stays O(n) in the common case.
        let isDescending = zip(levels, levels.dropFirst()).allSatisfy { $0.pressureHPa >= $1.pressureHPa }
        let sorted = isDescending ? levels : levels.sorted { $0.pressureHPa > $1.pressureHPa }

        // Clamp the request to the available range so edge taps still read out.
        let pMax = sorted.first!.pressureHPa
        let pMin = sorted.last!.pressureHPa
        let pc = min(max(p, pMin), pMax)

        // Find the bracketing pair (lower index = higher pressure).
        var lo = sorted.first!
        var hi = sorted.last!
        for i in 0..<(sorted.count - 1) where sorted[i].pressureHPa >= pc && sorted[i + 1].pressureHPa <= pc {
            lo = sorted[i]
            hi = sorted[i + 1]
            break
        }

        // Fraction in log-pressure space between lo (high p) and hi (low p).
        let denom = log(lo.pressureHPa) - log(hi.pressureHPa)
        let f = denom == 0 ? 0 : (log(lo.pressureHPa) - log(pc)) / denom

        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        func lerpOpt(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case let (a?, b?): return lerp(a, b)   // both present → interpolate
            case let (a?, nil): return a           // only one present → use it rather than discard
            case let (nil, b?): return b
            default: return nil                    // neither present
            }
        }

        let nearest = f < 0.5 ? lo : hi
        let altitude = lerpOpt(lo.altitudeFt, hi.altitudeFt) ?? Thermodynamics.pressureToAltitude(pc)

        return SkewTSample(
            pressureHPa: pc,
            altitudeFt: altitude,
            temperatureC: lerp(lo.temperatureC, hi.temperatureC),
            dewpointC: lerpOpt(lo.dewpointC, hi.dewpointC),
            windSpeedKt: nearest.windSpeedKt,
            windDirectionDeg: nearest.windDirectionDeg
        )
    }
}

/// An interpolated readout of a sounding at one pressure level.
///
/// Emitted by `SkewTView` on cursor changes so a host can drive a linked
/// cross-section (or any other vertically-aligned view) from the same level.
public struct SkewTSample: Sendable, Equatable, Hashable, Codable {
    public let pressureHPa: Double
    public let altitudeFt: Double
    public let temperatureC: Double
    public let dewpointC: Double?
    public let windSpeedKt: Double?
    public let windDirectionDeg: Double?

    public init(
        pressureHPa: Double,
        altitudeFt: Double,
        temperatureC: Double,
        dewpointC: Double? = nil,
        windSpeedKt: Double? = nil,
        windDirectionDeg: Double? = nil
    ) {
        self.pressureHPa = pressureHPa
        self.altitudeFt = altitudeFt
        self.temperatureC = temperatureC
        self.dewpointC = dewpointC
        self.windSpeedKt = windSpeedKt
        self.windDirectionDeg = windDirectionDeg
    }
}

/// Thermodynamic indices for annotation.
public struct SkewTIndices: Sendable, Equatable, Hashable, Codable {
    public let lclPressureHPa: Double?
    public let lfcPressureHPa: Double?
    public let elPressureHPa: Double?
    public let capeSurfaceJkg: Double?
    public let cinSurfaceJkg: Double?
    public let freezingLevelFt: Double?
    public let liftedIndex: Double?

    public init(
        lclPressureHPa: Double? = nil,
        lfcPressureHPa: Double? = nil,
        elPressureHPa: Double? = nil,
        capeSurfaceJkg: Double? = nil,
        cinSurfaceJkg: Double? = nil,
        freezingLevelFt: Double? = nil,
        liftedIndex: Double? = nil
    ) {
        self.lclPressureHPa = lclPressureHPa
        self.lfcPressureHPa = lfcPressureHPa
        self.elPressureHPa = elPressureHPa
        self.capeSurfaceJkg = capeSurfaceJkg
        self.cinSurfaceJkg = cinSurfaceJkg
        self.freezingLevelFt = freezingLevelFt
        self.liftedIndex = liftedIndex
    }
}

/// Overlay data to draw on the Skew-T (cloud/icing/inversion bands).
public struct SkewTOverlays: Sendable, Equatable, Hashable, Codable {
    public let cloudLayers: [OverlayBand]
    public let icingZones: [OverlayBand]
    public let inversions: [InversionBand]
    public let cruiseAltitudeFt: Double?
    /// Convective zone from LFC to EL (ft).
    public let convectiveLfcFt: Double?
    public let convectiveElFt: Double?

    public static let empty = SkewTOverlays(
        cloudLayers: [], icingZones: [], inversions: [],
        cruiseAltitudeFt: nil, convectiveLfcFt: nil, convectiveElFt: nil
    )

    public init(
        cloudLayers: [OverlayBand],
        icingZones: [OverlayBand],
        inversions: [InversionBand],
        cruiseAltitudeFt: Double?,
        convectiveLfcFt: Double? = nil,
        convectiveElFt: Double? = nil
    ) {
        self.cloudLayers = cloudLayers
        self.icingZones = icingZones
        self.inversions = inversions
        self.cruiseAltitudeFt = cruiseAltitudeFt
        self.convectiveLfcFt = convectiveLfcFt
        self.convectiveElFt = convectiveElFt
    }
}

/// A vertical band (e.g. cloud layer or icing zone) defined by altitude.
public struct OverlayBand: Sendable, Equatable, Hashable, Codable {
    public let baseFt: Double
    public let topFt: Double
    public let label: String

    public init(baseFt: Double, topFt: Double, label: String) {
        self.baseFt = baseFt
        self.topFt = topFt
        self.label = label
    }
}

/// A temperature inversion band defined by altitude and strength.
public struct InversionBand: Sendable, Equatable, Hashable, Codable {
    public let baseFt: Double
    public let topFt: Double
    public let strengthC: Double

    public init(baseFt: Double, topFt: Double, strengthC: Double) {
        self.baseFt = baseFt
        self.topFt = topFt
        self.strengthC = strengthC
    }
}
