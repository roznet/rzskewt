import SwiftUI

extension GraphicsContext {
    /// Draw the shared linked-cursor line between two endpoints.
    ///
    /// Used by both `SkewTView` and `SkewTVariablePanel` (paired with
    /// `SkewTTransform.crosshairEndpoints(atPressureHPa:)`) so the cursor's
    /// geometry and style stay identical across the two linked views.
    mutating func strokeCrosshair(from a: CGPoint, to b: CGPoint) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        stroke(path, with: .color(.red.opacity(0.7)), lineWidth: 1)
    }
}
