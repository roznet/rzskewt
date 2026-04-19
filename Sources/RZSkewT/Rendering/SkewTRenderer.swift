import SwiftUI

/// Main orchestrator for rendering a complete Skew-T log-P diagram.
public struct SkewTRenderer {
    public let profile: SoundingProfile
    public let config: SkewTConfiguration
    public let backgroundLines: BackgroundLines

    /// Precomputed parcel path (from surface level).
    public let parcelPath: [AtmosphericPoint]

    /// Computed LCL for CIN shading bounds and dot marker.
    public let lclResult: LCLResult?

    /// Computed EL pressure (where parcel re-crosses environment going cooler).
    public let elPressureHPa: Double?

    /// Computed LFC pressure (where parcel first becomes warmer than environment above LCL).
    public let lfcPressureHPa: Double?

    public init(profile: SoundingProfile, config: SkewTConfiguration = .default) {
        self.profile = profile
        self.config = config
        self.backgroundLines = BackgroundLines.compute(config: config)

        // Compute parcel path from the lowest level
        if let surface = profile.levels.max(by: { $0.pressureHPa < $1.pressureHPa }),
           let surfaceTd = surface.dewpointC {
            let lcl = Thermodynamics.liftingCondensationLevel(
                tempC: surface.temperatureC,
                dewpointC: surfaceTd,
                pressureHPa: surface.pressureHPa
            )
            self.lclResult = lcl
            self.parcelPath = Thermodynamics.parcelPath(
                surfaceTempC: surface.temperatureC,
                surfaceDewpointC: surfaceTd,
                surfacePressureHPa: surface.pressureHPa,
                topPressureHPa: config.pTop
            )

            // Find LFC and EL from parcel path vs environment
            let sortedEnv = profile.levels.sorted { $0.pressureHPa > $1.pressureHPa }
            var foundLFC: Double? = nil
            var foundEL: Double? = nil
            let lclP = lcl?.pressureHPa ?? 0

            for i in 0..<(self.parcelPath.count - 1) {
                let p = self.parcelPath[i].pressureHPa
                guard p <= lclP else { continue } // only above LCL
                let tParcel = self.parcelPath[i].tempC
                let tParcelNext = self.parcelPath[i + 1].tempC
                let pNext = self.parcelPath[i + 1].pressureHPa
                guard let tEnv = Thermodynamics.interpolateEnvironment(at: p, sortedLevels: sortedEnv),
                      let tEnvNext = Thermodynamics.interpolateEnvironment(at: pNext, sortedLevels: sortedEnv)
                else { continue }

                let buoy = tParcel - tEnv
                let buoyNext = tParcelNext - tEnvNext

                // LFC: first crossing from negative to positive buoyancy above LCL
                if foundLFC == nil && buoy <= 0 && buoyNext > 0 {
                    let frac = -buoy / (buoyNext - buoy)
                    foundLFC = p - frac * (p - pNext)
                }
                // EL: crossing from positive to negative buoyancy above LFC
                if foundLFC != nil && foundEL == nil && buoy >= 0 && buoyNext < 0 {
                    let frac = buoy / (buoy - buoyNext)
                    foundEL = p - frac * (p - pNext)
                }
            }
            self.lfcPressureHPa = foundLFC
            self.elPressureHPa = foundEL
        } else {
            self.parcelPath = []
            self.lclResult = nil
            self.elPressureHPa = nil
            self.lfcPressureHPa = nil
        }
    }

    /// Render the complete Skew-T diagram onto a GraphicsContext.
    public func render(context: inout GraphicsContext, size: CGSize) {
        let transform = SkewTTransform(size: size, config: config)
        let plot = transform.plotArea

        // Background fill
        let plotRect = CGRect(x: plot.left, y: plot.top, width: plot.width, height: plot.height)
        context.fill(Path(plotRect), with: .color(config.backgroundColor))

        // Clip layers to plot area
        var clipped = context
        clipped.clip(to: Path(plotRect))

        // Background reference lines
        BackgroundLinesRenderer.render(context: &clipped, transform: transform,
                                       lines: backgroundLines, config: config)

        // LCL / LFC / EL marker lines (inside clip)
        drawLevelMarkers(context: &clipped, transform: transform)

        // Parcel path with CAPE/CIN shading
        if !parcelPath.isEmpty {
            ProfileRenderer.renderParcelPath(context: &clipped, transform: transform,
                                              parcelPath: parcelPath,
                                              environmentLevels: profile.levels,
                                              config: config,
                                              lclPressureHPa: lclResult?.pressureHPa,
                                              elPressureHPa: elPressureHPa)
        }

        // Temperature and dewpoint profiles
        ProfileRenderer.render(context: &clipped, transform: transform,
                                profile: profile, config: config)

        // Dot markers for LCL, LFC, EL (on top of profiles, inside clip)
        drawLevelDots(context: &clipped, transform: transform)

        // Axes (outside clip)
        drawAxes(context: &context, transform: transform)

        // Wind barbs (outside clip, to the right)
        WindBarbRenderer.render(context: &context, transform: transform,
                                profile: profile, config: config)

        // Indices text panel
        drawIndices(context: &context, transform: transform)
    }

    // MARK: - Axes

    private func drawAxes(context: inout GraphicsContext, transform: SkewTTransform) {
        let plot = transform.plotArea
        let textColor = Color.primary

        // Plot border
        context.stroke(Path(CGRect(x: plot.left, y: plot.top, width: plot.width, height: plot.height)),
                       with: .color(.gray.opacity(0.5)), lineWidth: 0.5)

        // Pressure labels (left axis) + FL labels (right axis)
        for p in transform.visiblePressureLevels {
            let y = transform.pressureToY(p)

            // Left: pressure in hPa
            let pLabel = context.resolve(Text("\(Int(p))").font(.system(size: 11)).foregroundColor(textColor))
            context.draw(pLabel, at: CGPoint(x: plot.left - 4, y: y), anchor: .trailing)

            // Right: flight level (approximate from standard atmosphere)
            let altFt = Thermodynamics.pressureToAltitude(p)
            let flLabel: String
            if altFt >= 5000 {
                flLabel = "FL\(Int(altFt / 100))"
            } else {
                flLabel = "\(Int(altFt))'"
            }
            let flText = context.resolve(Text(flLabel).font(.system(size: 10)).foregroundColor(.secondary))
            context.draw(flText, at: CGPoint(x: plot.right + 4, y: y), anchor: .leading)
        }

        // Temperature labels (bottom axis)
        for t in stride(from: config.tMin, through: config.tMax, by: 10.0) {
            let x = transform.temperatureToX(t, atPressure: config.pBottom)
            guard x >= plot.left && x <= plot.right else { continue }
            let label = context.resolve(Text("\(Int(t))°").font(.system(size: 11)).foregroundColor(textColor))
            context.draw(label, at: CGPoint(x: x, y: plot.bottom + 4), anchor: .top)
        }

        // Axis titles
        let hpaLabel = context.resolve(Text("hPa").font(.system(size: 9)).foregroundColor(.secondary))
        context.draw(hpaLabel, at: CGPoint(x: plot.left - 4, y: plot.top - 8), anchor: .trailing)

        let flTitle = context.resolve(Text("FL").font(.system(size: 9)).foregroundColor(.secondary))
        context.draw(flTitle, at: CGPoint(x: plot.right + 4, y: plot.top - 8), anchor: .leading)
    }

    // MARK: - LCL / LFC / EL marker lines

    private func drawLevelMarkers(context: inout GraphicsContext, transform: SkewTTransform) {
        // Use computed values with profile.indices as fallback
        let lclP = lclResult?.pressureHPa ?? profile.indices?.lclPressureHPa
        let lfcP = lfcPressureHPa ?? profile.indices?.lfcPressureHPa
        let elP = elPressureHPa ?? profile.indices?.elPressureHPa

        if let lcl = lclP {
            drawMarkerLine(context: &context, transform: transform, pressureHPa: lcl,
                          label: "LCL", color: .orange)
        }
        if let lfc = lfcP {
            drawMarkerLine(context: &context, transform: transform, pressureHPa: lfc,
                          label: "LFC", color: .brown)
        }
        if let el = elP {
            drawMarkerLine(context: &context, transform: transform, pressureHPa: el,
                          label: "EL", color: .purple)
        }

        // Freezing level (from altitude, convert to approximate pressure)
        if let fzFt = profile.indices?.freezingLevelFt {
            let fzP = Thermodynamics.altitudeToPressure(fzFt)
            if fzP >= config.pTop && fzP <= config.pBottom {
                drawMarkerLine(context: &context, transform: transform, pressureHPa: fzP,
                              label: "0°C", color: .cyan)
            }
        }
    }

    // MARK: - Level dot markers (like metpy)

    /// Draw dot markers at LCL, LFC, EL on the parcel path, matching metpy's style.
    private func drawLevelDots(context: inout GraphicsContext, transform: SkewTTransform) {
        let markerSize: CGFloat = 8
        let plot = transform.plotArea

        // LCL: green circle at parcel path temperature
        if let lcl = lclResult {
            let pt = transform.point(tempC: lcl.tempC, pressureHPa: lcl.pressureHPa)
            if pt.y >= plot.top && pt.y <= plot.bottom {
                drawDotMarker(context: &context, at: pt, size: markerSize,
                             color: Color(red: 0.17, green: 0.63, blue: 0.17), // #2ca02c
                             shape: .circle)
            }
        }

        // LFC: orange square at parcel path temperature
        if let lfcP = lfcPressureHPa {
            let tAtLFC = interpolateParcelTemp(at: lfcP)
            let pt = transform.point(tempC: tAtLFC, pressureHPa: lfcP)
            if pt.y >= plot.top && pt.y <= plot.bottom {
                drawDotMarker(context: &context, at: pt, size: markerSize,
                             color: Color(red: 1.0, green: 0.50, blue: 0.05), // #ff7f0e
                             shape: .square)
            }
        }

        // EL: red diamond at parcel path temperature
        if let elP = elPressureHPa {
            let tAtEL = interpolateParcelTemp(at: elP)
            let pt = transform.point(tempC: tAtEL, pressureHPa: elP)
            if pt.y >= plot.top && pt.y <= plot.bottom {
                drawDotMarker(context: &context, at: pt, size: markerSize,
                             color: Color(red: 0.84, green: 0.15, blue: 0.16), // #d62728
                             shape: .diamond)
            }
        }
    }

    private enum MarkerShape { case circle, square, diamond }

    private func drawDotMarker(
        context: inout GraphicsContext,
        at point: CGPoint,
        size: CGFloat,
        color: Color,
        shape: MarkerShape
    ) {
        let half = size / 2
        var path = Path()

        switch shape {
        case .circle:
            path.addEllipse(in: CGRect(x: point.x - half, y: point.y - half,
                                        width: size, height: size))
        case .square:
            path.addRect(CGRect(x: point.x - half, y: point.y - half,
                                width: size, height: size))
        case .diamond:
            path.move(to: CGPoint(x: point.x, y: point.y - half))
            path.addLine(to: CGPoint(x: point.x + half, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y + half))
            path.addLine(to: CGPoint(x: point.x - half, y: point.y))
            path.closeSubpath()
        }

        // White edge + fill (like metpy's markeredgecolor="white", markeredgewidth=1)
        context.stroke(path, with: .color(.white), lineWidth: 2)
        context.fill(path, with: .color(color))
    }

    /// Interpolate parcel temperature at a given pressure from the parcel path.
    private func interpolateParcelTemp(at pressureHPa: Double) -> Double {
        for i in 0..<(parcelPath.count - 1) {
            let p1 = parcelPath[i].pressureHPa
            let p2 = parcelPath[i + 1].pressureHPa
            if pressureHPa <= p1 && pressureHPa >= p2 {
                let frac = (p1 - pressureHPa) / (p1 - p2)
                return parcelPath[i].tempC + frac * (parcelPath[i + 1].tempC - parcelPath[i].tempC)
            }
        }
        // Fallback: nearest point
        return parcelPath.min(by: { abs($0.pressureHPa - pressureHPa) < abs($1.pressureHPa - pressureHPa) })?.tempC ?? 0
    }

    private func drawMarkerLine(
        context: inout GraphicsContext,
        transform: SkewTTransform,
        pressureHPa: Double,
        label: String,
        color: Color
    ) {
        let plot = transform.plotArea
        let y = transform.pressureToY(pressureHPa)
        guard y >= plot.top && y <= plot.bottom else { return }

        // Dashed horizontal line
        var path = Path()
        path.move(to: CGPoint(x: plot.left, y: y))
        path.addLine(to: CGPoint(x: plot.right, y: y))
        context.stroke(path, with: .color(color.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1.0, dash: [6, 3]))

        // Label pill on the left edge
        let text = context.resolve(Text(label).font(.system(size: 7, weight: .bold)).foregroundColor(color))
        let textSize = text.measure(in: CGSize(width: 60, height: 20))
        let padding: CGFloat = 2
        let pillRect = CGRect(
            x: plot.left + 2,
            y: y - textSize.height / 2 - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        context.fill(Path(roundedRect: pillRect, cornerRadius: 2),
                     with: .color(config.panelBackgroundColor))
        context.draw(text, at: CGPoint(x: pillRect.midX, y: pillRect.midY), anchor: .center)
    }

    // MARK: - Indices panel

    private func drawIndices(context: inout GraphicsContext, transform: SkewTTransform) {
        guard let indices = profile.indices else { return }
        let plot = transform.plotArea

        var lines: [String] = []
        if let cape = indices.capeSurfaceJkg {
            lines.append("CAPE: \(Int(cape)) J/kg")
        }
        if let cin = indices.cinSurfaceJkg {
            lines.append("CIN: \(Int(cin)) J/kg")
        }
        if let li = indices.liftedIndex {
            lines.append("LI: \(String(format: "%.1f", li))")
        }

        guard !lines.isEmpty else { return }

        let textStr = lines.joined(separator: "\n")
        let text = context.resolve(
            Text(textStr)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.primary)
        )
        let textSize = text.measure(in: CGSize(width: 200, height: 200))
        let padding: CGFloat = 6
        let boxRect = CGRect(
            x: plot.right - textSize.width - padding * 2 - 4,
            y: plot.top + 4,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        context.fill(Path(roundedRect: boxRect, cornerRadius: 4),
                     with: .color(config.panelBackgroundColor))
        context.draw(text, at: CGPoint(x: boxRect.midX, y: boxRect.midY), anchor: .center)
    }
}
