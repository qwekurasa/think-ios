import SwiftUI

enum SketchFont {
    static func regular(_ size: CGFloat) -> Font {
        .custom("Noteworthy-Light", size: size, relativeTo: .body)
    }
    static func bold(_ size: CGFloat) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: .body)
    }
}

/// A deliberately imperfect rounded rectangle, built from a softly wobbling
/// superellipse instead of a mathematically perfect system shape.
struct SketchRoundedRectangle: Shape {
    var cornerRadius: CGFloat = 16
    var style: RoundedCornerStyle = .continuous
    var wobble: CGFloat = 0.85
    var seed: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: max(1, wobble), dy: max(1, wobble))
        let corner = min(cornerRadius, bounds.width * 0.30, bounds.height * 0.30)
        let wave = max(0.25, wobble * 0.52)
        var path = Path()
        var count = 0

        func add(_ x: CGFloat, _ y: CGFloat, _ nx: CGFloat, _ ny: CGFloat) {
            let jitter = wave * CGFloat(
                0.52 * sin(Double(count) * 1.17 + Double(seed)) +
                0.28 * sin(Double(count) * 0.39 + Double(seed) * 2.31)
            )
            let point = CGPoint(x: x + nx * jitter, y: y + ny * jitter)
            if count == 0 { path.move(to: point) } else { path.addLine(to: point) }
            count += 1
        }

        let steps = 19
        let arcs = 11
        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            add(bounds.minX + corner + (bounds.width - 2 * corner) * u,
                bounds.minY, 0, -1)
        }
        for i in 1...arcs {
            let angle = (-Double.pi / 2) + Double(i) / Double(arcs) * (Double.pi / 2)
            add(bounds.maxX - corner + cos(angle) * corner,
                bounds.minY + corner + sin(angle) * corner,
                CGFloat(cos(angle)), CGFloat(sin(angle)))
        }
        for i in 1...steps {
            let u = CGFloat(i) / CGFloat(steps)
            add(bounds.maxX, bounds.minY + corner + (bounds.height - 2 * corner) * u, 1, 0)
        }
        for i in 1...arcs {
            let angle = Double(i) / Double(arcs) * (Double.pi / 2)
            add(bounds.maxX - corner + cos(angle) * corner,
                bounds.maxY - corner + sin(angle) * corner,
                CGFloat(cos(angle)), CGFloat(sin(angle)))
        }
        for i in 1...steps {
            let u = CGFloat(i) / CGFloat(steps)
            add(bounds.maxX - corner - (bounds.width - 2 * corner) * u,
                bounds.maxY, 0, 1)
        }
        for i in 1...arcs {
            let angle = Double.pi / 2 + Double(i) / Double(arcs) * (Double.pi / 2)
            add(bounds.minX + corner + cos(angle) * corner,
                bounds.maxY - corner + sin(angle) * corner,
                CGFloat(cos(angle)), CGFloat(sin(angle)))
        }
        for i in 1...steps {
            let u = CGFloat(i) / CGFloat(steps)
            add(bounds.minX, bounds.maxY - corner - (bounds.height - 2 * corner) * u, -1, 0)
        }
        for i in 1...arcs {
            let angle = Double.pi + Double(i) / Double(arcs) * (Double.pi / 2)
            add(bounds.minX + corner + cos(angle) * corner,
                bounds.minY + corner + sin(angle) * corner,
                CGFloat(cos(angle)), CGFloat(sin(angle)))
        }
        path.closeSubpath()
        return path
    }
}


struct SketchOval: Shape {
    var wobble: CGFloat = 1.0
    var seed: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width * 0.5
        let ry = rect.height * 0.5
        var path = Path()
        let count = 88
        for index in 0..<count {
            let angle = Double(index) * 2 * Double.pi / Double(count)
            let drift = Double(wobble) * (
                0.48 * sin(Double(index) * 1.91 + Double(seed)) +
                0.20 * cos(Double(index) * 0.77 + Double(seed) * 1.7)
            )
            let x = center.x + CGFloat(cos(angle) * (Double(rx) + drift))
            let y = center.y + CGFloat(sin(angle) * (Double(ry) + drift))
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct SketchRule: Shape {
    var seed: CGFloat = 0
    var amplitude: CGFloat = 0.8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        for index in 0...steps {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(steps)
            let phase = CGFloat(index) * 0.73 + seed
            let y = rect.midY + amplitude * (0.65 * sin(phase) + 0.25 * sin(phase * 0.41))
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct SketchGlyph: View {
    let name: String
    var size: CGFloat = 23
    var lineWidth: CGFloat = 1.65
    var color: Color = Color(red: 0.16, green: 0.16, blue: 0.17)

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * w, y: y * h)
            }
            var path = Path()
            func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
                path.move(to: point(a.0, a.1))
                path.addLine(to: point(b.0, b.1))
            }
            switch name {
            case "house":
                // Loose pencil roof and slightly crooked walls, not a stock house glyph.
                path.move(to: point(0.09, 0.51))
                path.addCurve(to: point(0.49, 0.11), control1: point(0.23, 0.36), control2: point(0.40, 0.13))
                path.addCurve(to: point(0.91, 0.49), control1: point(0.56, 0.11), control2: point(0.80, 0.33))
                path.move(to: point(0.24, 0.42))
                path.addQuadCurve(to: point(0.21, 0.89), control: point(0.23, 0.69))
                path.addQuadCurve(to: point(0.79, 0.88), control: point(0.47, 0.92))
                path.addQuadCurve(to: point(0.77, 0.41), control: point(0.80, 0.65))
                path.move(to: point(0.43, 0.90))
                path.addQuadCurve(to: point(0.41, 0.64), control: point(0.42, 0.75))
                path.addQuadCurve(to: point(0.61, 0.63), control: point(0.52, 0.56))
                path.addLine(to: point(0.60, 0.89))
                path.move(to: point(0.18, 0.50))
                path.addQuadCurve(to: point(0.50, 0.18), control: point(0.32, 0.31))
            case "square.stack":
                // Torn notebook with an uneven binding and crooked inner lines.
                path.move(to: point(0.27, 0.17))
                path.addCurve(to: point(0.77, 0.20), control1: point(0.40, 0.13), control2: point(0.62, 0.14))
                path.addQuadCurve(to: point(0.79, 0.85), control: point(0.82, 0.52))
                path.addCurve(to: point(0.24, 0.87), control1: point(0.61, 0.88), control2: point(0.41, 0.89))
                path.addQuadCurve(to: point(0.27, 0.17), control: point(0.20, 0.52))
                path.move(to: point(0.18, 0.27))
                path.addQuadCurve(to: point(0.19, 0.79), control: point(0.15, 0.49))
                path.move(to: point(0.33, 0.40))
                path.addQuadCurve(to: point(0.66, 0.38), control: point(0.50, 0.35))
                path.move(to: point(0.34, 0.54))
                path.addQuadCurve(to: point(0.69, 0.56), control: point(0.49, 0.59))
                path.move(to: point(0.36, 0.69))
                path.addQuadCurve(to: point(0.58, 0.68), control: point(0.45, 0.66))
            case "sparkle":
                // A slightly lopsided four-tip star, as if drawn in one motion.
                path.move(to: point(0.49, 0.05))
                path.addQuadCurve(to: point(0.61, 0.38), control: point(0.57, 0.29))
                path.addQuadCurve(to: point(0.96, 0.48), control: point(0.76, 0.42))
                path.addQuadCurve(to: point(0.60, 0.63), control: point(0.76, 0.58))
                path.addQuadCurve(to: point(0.50, 0.96), control: point(0.54, 0.78))
                path.addQuadCurve(to: point(0.38, 0.61), control: point(0.43, 0.77))
                path.addQuadCurve(to: point(0.04, 0.52), control: point(0.21, 0.57))
                path.addQuadCurve(to: point(0.39, 0.39), control: point(0.21, 0.44))
                path.addQuadCurve(to: point(0.49, 0.05), control: point(0.44, 0.25))
            case "plus":
                line((0.50, 0.13), (0.50, 0.87))
                line((0.13, 0.50), (0.87, 0.50))
            case "chevron.left":
                path.move(to: point(0.66, 0.12))
                path.addQuadCurve(to: point(0.30, 0.50), control: point(0.47, 0.30))
                path.addQuadCurve(to: point(0.66, 0.88), control: point(0.47, 0.70))
            case "xmark":
                line((0.18, 0.18), (0.82, 0.82))
                line((0.82, 0.18), (0.18, 0.82))
            case "mic":
                path.move(to: point(0.39, 0.17))
                path.addQuadCurve(to: point(0.61, 0.17), control: point(0.50, 0.10))
                path.addLine(to: point(0.61, 0.57))
                path.addQuadCurve(to: point(0.39, 0.57), control: point(0.50, 0.70))
                path.closeSubpath()
                path.move(to: point(0.24, 0.48))
                path.addQuadCurve(to: point(0.76, 0.48), control: point(0.51, 0.91))
                path.move(to: point(0.50, 0.79))
                path.addLine(to: point(0.50, 0.94))
                path.move(to: point(0.35, 0.94))
                path.addLine(to: point(0.65, 0.94))
            case "keyboard":
                path.move(to: point(0.10, 0.24))
                path.addQuadCurve(to: point(0.90, 0.24), control: point(0.50, 0.20))
                path.addLine(to: point(0.90, 0.76))
                path.addQuadCurve(to: point(0.10, 0.76), control: point(0.50, 0.80))
                path.closeSubpath()
                for row in 0..<2 {
                    for col in 0..<5 {
                        let x = 0.23 + CGFloat(col) * 0.135
                        let y = 0.40 + CGFloat(row) * 0.19
                        let r = CGRect(x: x * w, y: y * h, width: 0.055 * w, height: 0.06 * h)
                        path.addEllipse(in: r)
                    }
                }
                line((0.36, 0.68), (0.66, 0.68))
            case "pencil":
                path.move(to: point(0.19, 0.79))
                path.addLine(to: point(0.68, 0.23))
                path.addQuadCurve(to: point(0.82, 0.36), control: point(0.78, 0.20))
                path.addLine(to: point(0.31, 0.91))
                path.addLine(to: point(0.19, 0.79))
                path.move(to: point(0.19, 0.79))
                path.addLine(to: point(0.15, 0.94))
            case "qrcode":
                for (x, y) in [(CGFloat(0.12),CGFloat(0.12)),(CGFloat(0.62),CGFloat(0.12)),(CGFloat(0.12),CGFloat(0.62))] {
                    path.addRect(CGRect(x: x*w, y: y*h, width: 0.25*w, height: 0.25*h))
                    path.addRect(CGRect(x: (x+0.07)*w, y: (y+0.07)*h, width: 0.11*w, height: 0.11*h))
                }
                for i in 0..<4 {
                    let x = 0.52 + CGFloat(i%2)*0.16
                    let y = 0.55 + CGFloat(i/2)*0.16
                    path.addEllipse(in: CGRect(x:x*w,y:y*h,width:0.07*w,height:0.07*h))
                }
            case "arrow.up.right":
                line((0.28, 0.72), (0.76, 0.24))
                line((0.43, 0.24), (0.76, 0.24))
                line((0.76, 0.24), (0.76, 0.57))
            case "magnifyingglass":
                path.addEllipse(in: CGRect(x: 0.12*w, y: 0.10*h, width: 0.56*w, height: 0.56*h))
                line((0.60, 0.61), (0.91, 0.91))
            case "hourglass":
                path.move(to: point(0.23, 0.12))
                path.addQuadCurve(to: point(0.77, 0.12), control: point(0.50, 0.16))
                path.addLine(to: point(0.70, 0.38))
                path.addLine(to: point(0.50, 0.51))
                path.addLine(to: point(0.30, 0.38))
                path.addLine(to: point(0.23, 0.12))
                path.move(to: point(0.30, 0.88))
                path.addQuadCurve(to: point(0.70, 0.88), control: point(0.50, 0.84))
                path.addLine(to: point(0.77, 0.62))
                path.addLine(to: point(0.50, 0.49))
                path.addLine(to: point(0.23, 0.62))
                path.addLine(to: point(0.30, 0.88))
            case "checkmark.circle.fill":
                path.addEllipse(in: CGRect(x: 0.08*w, y: 0.08*h, width: 0.84*w, height: 0.84*h))
                path.move(to: point(0.27, 0.51))
                path.addLine(to: point(0.44, 0.68))
                path.addLine(to: point(0.76, 0.32))
            case "ellipsis":
                for index in 0..<3 {
                    let x = CGFloat(0.22 + Double(index) * 0.28)
                    path.addEllipse(in: CGRect(x: x*w, y: 0.46*h, width: 0.10*w, height: 0.10*h))
                }
            case "trash":
                path.move(to: point(0.24, 0.28))
                path.addLine(to: point(0.76, 0.28))
                path.move(to: point(0.34, 0.20))
                path.addQuadCurve(to: point(0.66, 0.20), control: point(0.50, 0.14))
                path.move(to: point(0.29, 0.32))
                path.addLine(to: point(0.34, 0.87))
                path.addQuadCurve(to: point(0.67, 0.87), control: point(0.52, 0.92))
                path.addLine(to: point(0.72, 0.32))
                path.move(to: point(0.43, 0.42))
                path.addLine(to: point(0.44, 0.75))
                path.move(to: point(0.57, 0.42))
                path.addLine(to: point(0.56, 0.75))
            case "pin.fill":
                path.move(to: point(0.50, 0.08))
                path.addQuadCurve(to: point(0.80, 0.39), control: point(0.81, 0.12))
                path.addQuadCurve(to: point(0.50, 0.70), control: point(0.81, 0.65))
                path.addQuadCurve(to: point(0.20, 0.39), control: point(0.19, 0.65))
                path.addQuadCurve(to: point(0.50, 0.08), control: point(0.19, 0.12))
                path.move(to: point(0.50, 0.67))
                path.addLine(to: point(0.48, 0.96))
            case "square.and.arrow.up":
                path.move(to: point(0.18, 0.43))
                path.addLine(to: point(0.18, 0.83))
                path.addQuadCurve(to: point(0.82, 0.83), control: point(0.50, 0.88))
                path.addLine(to: point(0.82, 0.43))
                path.move(to: point(0.50, 0.62))
                path.addLine(to: point(0.50, 0.10))
                path.move(to: point(0.31, 0.30))
                path.addLine(to: point(0.50, 0.10))
                path.addLine(to: point(0.69, 0.30))
            case "arrow.uturn.backward":
                path.move(to: point(0.76, 0.75))
                path.addQuadCurve(to: point(0.32, 0.37), control: point(0.74, 0.35))
                path.addLine(to: point(0.32, 0.16))
                path.move(to: point(0.12, 0.34))
                path.addLine(to: point(0.32, 0.16))
                path.addLine(to: point(0.52, 0.34))
            default:
                path.move(to: point(0.50, 0.10))
                path.addLine(to: point(0.50, 0.90))
                path.move(to: point(0.10, 0.50))
                path.addLine(to: point(0.90, 0.50))
            }

            // One confident ink stroke avoids the old doubled/outlined effect.
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth * 1.08, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SketchLabel: View {
    let title: String
    let symbol: String
    var size: CGFloat = 18

    init(_ title: String, symbol: String, size: CGFloat = 18) {
        self.title = title
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        HStack(spacing: 8) {
            SketchGlyph(name: symbol, size: size, lineWidth: 1.35)
            Text(title).font(SketchFont.regular(15))
        }
    }
}

struct SketchEdge: ViewModifier {
    var radius: CGFloat = 15
    var seed: CGFloat = 1
    func body(content: Content) -> some View {
        content
            .background(Color.white, in: SketchRoundedRectangle(cornerRadius: radius, seed: seed))
            .overlay(SketchRoundedRectangle(cornerRadius: radius, seed: seed + 3.7)
                .stroke(Color(red: 0.28, green: 0.28, blue: 0.29).opacity(0.82), lineWidth: 1.0))
            .overlay(SketchRoundedRectangle(cornerRadius: radius, wobble: 1.25, seed: seed + 8.2)
                .stroke(Color(red: 0.55, green: 0.55, blue: 0.56).opacity(0.42), lineWidth: 0.65)
                .padding(1.5))
    }
}

extension View {
    func sketchEdge(radius: CGFloat = 15, seed: CGFloat = 1) -> some View {
        modifier(SketchEdge(radius: radius, seed: seed))
    }
}


/// Subtle, deterministic imperfections for short headlines. The character
/// offsets remain stable while the view updates, unlike random jitter.
struct SketchHeading: View {
    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat = 32) {
        self.text = text
        self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: -0.9) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(SketchFont.regular(size))
                    .rotationEffect(.degrees(Double(((index * 7 + text.count) % 9) - 4) * 0.42))
                    .offset(y: CGFloat(((index * 11 + text.count) % 5) - 2) * 0.46)
            }
        }
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
