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
        let inset = max(1, wobble)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rx = max(1, bounds.width / 2)
        let ry = max(1, bounds.height / 2)
        let exponent = max(2.5, min(4.2, 2.15 + max(bounds.width, bounds.height) / max(12, cornerRadius) * 0.035))
        let count = 96
        var path = Path()
        for index in 0..<count {
            let angle = Double(index) * 2 * Double.pi / Double(count)
            let c = cos(angle)
            let s = sin(angle)
            let baseX = (c < 0 ? -1.0 : 1.0) * pow(abs(c), 2 / Double(exponent)) * Double(rx)
            let baseY = (s < 0 ? -1.0 : 1.0) * pow(abs(s), 2 / Double(exponent)) * Double(ry)
            let drift = Double(wobble) * (
                0.43 * sin(Double(index) * 1.71 + Double(seed)) +
                0.22 * sin(Double(index) * 0.63 + Double(seed) * 2.1)
            )
            let point = CGPoint(
                x: center.x + CGFloat(baseX) + CGFloat(c) * CGFloat(drift),
                y: center.y + CGFloat(baseY) + CGFloat(s) * CGFloat(drift)
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
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
                path.move(to: point(0.10, 0.47))
                path.addQuadCurve(to: point(0.50, 0.10), control: point(0.28, 0.24))
                path.addQuadCurve(to: point(0.91, 0.48), control: point(0.75, 0.24))
                path.move(to: point(0.22, 0.40))
                path.addLine(to: point(0.23, 0.91))
                path.addQuadCurve(to: point(0.76, 0.90), control: point(0.49, 0.94))
                path.addLine(to: point(0.78, 0.40))
                path.move(to: point(0.43, 0.91))
                path.addLine(to: point(0.43, 0.64))
                path.addQuadCurve(to: point(0.59, 0.64), control: point(0.50, 0.60))
                path.addLine(to: point(0.59, 0.91))
            case "square.stack":
                path.move(to: point(0.20, 0.22))
                path.addQuadCurve(to: point(0.78, 0.20), control: point(0.52, 0.18))
                path.addLine(to: point(0.80, 0.82))
                path.addQuadCurve(to: point(0.19, 0.84), control: point(0.48, 0.88))
                path.closeSubpath()
                path.move(to: point(0.28, 0.12))
                path.addQuadCurve(to: point(0.70, 0.11), control: point(0.48, 0.08))
                path.move(to: point(0.31, 0.91))
                path.addQuadCurve(to: point(0.70, 0.90), control: point(0.50, 0.94))
            case "sparkle":
                path.move(to: point(0.50, 0.06))
                path.addQuadCurve(to: point(0.61, 0.40), control: point(0.54, 0.29))
                path.addQuadCurve(to: point(0.94, 0.51), control: point(0.77, 0.46))
                path.addQuadCurve(to: point(0.60, 0.62), control: point(0.76, 0.57))
                path.addQuadCurve(to: point(0.49, 0.95), control: point(0.55, 0.77))
                path.addQuadCurve(to: point(0.39, 0.61), control: point(0.44, 0.77))
                path.addQuadCurve(to: point(0.06, 0.50), control: point(0.22, 0.56))
                path.addQuadCurve(to: point(0.40, 0.39), control: point(0.22, 0.44))
                path.addQuadCurve(to: point(0.50, 0.06), control: point(0.45, 0.23))
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

            // A second, faint pencil pass gives every icon a human-drawn edge.
            context.stroke(path, with: .color(color.opacity(0.34)),
                           style: StrokeStyle(lineWidth: lineWidth * 1.9, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
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
