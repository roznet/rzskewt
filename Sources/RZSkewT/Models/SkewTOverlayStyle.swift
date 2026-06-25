import SwiftUI

/// Appearance knobs for the overlay bands (cloud / icing / inversion / convective),
/// the cruise-altitude line and the interactive cursor.
///
/// Lifted out of `OverlayBandsRenderer` so the colors are a single, themeable
/// source of truth a host can override (and keep in sync with the web renderer),
/// rather than magic numbers buried in drawing code.
///
/// Cloud bands default to a neutral grey with a hairline border: a white fill is
/// invisible on the default near-white background (especially thin `FEW` layers),
/// so the border keeps even faint layers locatable.
public struct SkewTOverlayStyle: Sendable {
    public var cloudColor: Color
    public var cloudBorderColor: Color
    public var icingLightColor: Color
    public var icingModerateColor: Color
    public var icingSevereColor: Color
    public var icingDefaultColor: Color
    /// Base colour for inversions; the rendered opacity scales with inversion strength.
    public var inversionColor: Color
    public var convectiveColor: Color
    public var cruiseLineColor: Color
    public var cursorColor: Color

    public init(
        cloudColor: Color = Color(white: 0.45),
        cloudBorderColor: Color = Color(white: 0.4).opacity(0.55),
        icingLightColor: Color = Color(red: 0.4, green: 0.6, blue: 1.0, opacity: 0.30),
        icingModerateColor: Color = Color(red: 1.0, green: 0.6, blue: 0.2, opacity: 0.38),
        icingSevereColor: Color = Color(red: 1.0, green: 0.2, blue: 0.2, opacity: 0.45),
        icingDefaultColor: Color = Color.blue.opacity(0.2),
        inversionColor: Color = Color(red: 233 / 255, green: 30 / 255, blue: 99 / 255),
        convectiveColor: Color = Color.orange.opacity(0.18),
        cruiseLineColor: Color = Color.primary.opacity(0.35),
        cursorColor: Color = Color.red.opacity(0.7)
    ) {
        self.cloudColor = cloudColor
        self.cloudBorderColor = cloudBorderColor
        self.icingLightColor = icingLightColor
        self.icingModerateColor = icingModerateColor
        self.icingSevereColor = icingSevereColor
        self.icingDefaultColor = icingDefaultColor
        self.inversionColor = inversionColor
        self.convectiveColor = convectiveColor
        self.cruiseLineColor = cruiseLineColor
        self.cursorColor = cursorColor
    }

    public static let `default` = SkewTOverlayStyle()

    // MARK: - Mappings (single source of truth, shared with the web renderer)

    /// Fill opacity for a cloud band keyed on its METAR coverage label.
    public func cloudFillOpacity(forCoverage label: String) -> Double {
        switch label.uppercased() {
        case "OVC": return 0.55
        case "BKN": return 0.40
        case "SCT": return 0.28
        case "FEW": return 0.15
        default: return 0.35
        }
    }

    /// Color for an icing band keyed on its risk label.
    public func icingColor(forRisk risk: String) -> Color {
        switch risk.lowercased() {
        case "light": return icingLightColor
        case "moderate": return icingModerateColor
        case "severe": return icingSevereColor
        default: return icingDefaultColor
        }
    }

    /// Rendered opacity for an inversion band, scaling with its strength (°C) and clamped.
    public func inversionOpacity(forStrengthC strengthC: Double) -> Double {
        min(0.65, 0.15 + 0.5 * min(strengthC / 3.0, 1.0))
    }
}
