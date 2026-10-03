import SwiftUI

/// A parallelogram leaning right by `slant` points (Persona 5 cards and tab highlights).
struct SlantedRectangle: Shape {
    var slant: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(slant, rect.width / 4)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
