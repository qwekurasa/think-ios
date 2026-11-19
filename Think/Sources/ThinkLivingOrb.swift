import SwiftUI

/// A breathing, pencil-sketched thought orb. Every line is drawn live in Canvas;
/// the imperfect double strokes intentionally keep the hand-made character.
struct ThinkLivingOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0,
                                paused: scenePhase != .active)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false, colorMode: .nonLinear) { context, size in
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let radius = min(size.width, size.height) * 0.34
                let breath = 1 + 0.018 * sin(time * 0.72)

                // A faint graphite under-sketch gives the sphere a soft, unfinished edge.
                for pass in 0..<3 {
                    let scale = CGFloat(1 + Double(pass - 1) * 0.018) * CGFloat(breath)
                    let path = looseLoop(center: center, radius: radius * scale,
                                         time: time, seed: Double(pass) * 2.3)
                    let alpha = [0.17, 0.72, 0.31][pass]
                    let width = [2.3, 1.45, 0.85][pass]
                    context.stroke(path, with: .color(graphite.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: width,
                                                      lineCap: .round, lineJoin: .round))
                }

                // A few short, broken pencil strokes suggest volume without any gradient or fill.
                drawHatching(in: &context, center: center, radius: radius, time: time)

                // Two wandering orbital curves pass behind the little central spark.
                for pass in 0..<2 {
                    let orbit = orbitPath(center: center, radius: radius,
                                          time: time, seed: Double(pass) * 2.6 + 1.1)
                    context.stroke(orbit, with: .color(graphite.opacity(pass == 0 ? 0.34 : 0.16)),
                                   style: StrokeStyle(lineWidth: pass == 0 ? 1.05 : 0.75,
                                                      lineCap: .round, dash: pass == 0 ? [] : [2.2, 4.2]))
                }

                let sparkSize = radius * CGFloat(0.15 + 0.012 * sin(time * 1.2))
                let spark = handStar(center: CGPoint(
                    x: center.x + CGFloat(sin(time * 0.42)) * radius * 0.045,
                    y: center.y + CGFloat(cos(time * 0.36)) * radius * 0.04
                ), size: sparkSize, time: time)
                context.stroke(spark, with: .color(graphite.opacity(0.78)),
                               style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))

                // Tiny graphite flecks drift gently around the sphere.
                for index in 0..<7 {
                    let n = Double(index)
                    let angle = n * 2.39996 + time * (index.isMultiple(of: 2) ? 0.10 : -0.075)
                    let orbitRadius = radius * CGFloat(1.08 + 0.07 * sin(time * 0.31 + n))
                    let point = CGPoint(
                        x: center.x + CGFloat(cos(angle)) * orbitRadius,
                        y: center.y + CGFloat(sin(angle)) * orbitRadius
                    )
                    let dotSize = CGFloat(1.2 + 0.9 * (0.5 + 0.5 * sin(time + n)))
                    let dot = Path(ellipseIn: CGRect(x: point.x - dotSize / 2,
                                                     y: point.y - dotSize / 2,
                                                     width: dotSize, height: dotSize))
                    context.fill(dot, with: .color(graphite.opacity(0.38 + 0.28 * sin(time * 0.8 + n))))
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Нарисованный карандашом шар с движущимися искрами")
    }

    private var graphite: Color {
        Color(red: 0.16, green: 0.16, blue: 0.17)
    }

    private func looseLoop(center: CGPoint, radius: CGFloat,
                           time: Double, seed: Double) -> Path {
        var path = Path()
        let steps = 144
        for step in 0...steps {
            let u = Double(step) / Double(steps)
            let angle = u * 2 * Double.pi
            let broad = sin(angle * 3 + seed + time * 0.23) * 0.022
            let fine = sin(angle * 9 + seed * 1.7 + time * 0.19) * 0.010
            let hand = sin(angle * 17 + seed * 2.1) * 0.004
            let r = Double(radius) * (1 + broad + fine + hand)
            let x = center.x + CGFloat(cos(angle) * r) + CGFloat(sin(angle * 2 + seed)) * radius * 0.008
            let y = center.y + CGFloat(sin(angle) * r * 0.985) + CGFloat(cos(angle * 3 + seed)) * radius * 0.008
            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func orbitPath(center: CGPoint, radius: CGFloat,
                           time: Double, seed: Double) -> Path {
        var path = Path()
        let steps = 100
        for step in 0...steps {
            let u = Double(step) / Double(steps)
            let angle = u * 2 * Double.pi + time * 0.12 + seed
            let radial = Double(radius) * (0.72 + 0.08 * sin(angle * 2.0 + time * 0.28))
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle) * radial),
                y: center.y + CGFloat(sin(angle) * radial * 0.73)
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func drawHatching(in context: inout GraphicsContext,
                              center: CGPoint, radius: CGFloat, time: Double) {
        for index in 0..<13 {
            let n = CGFloat(index)
            let x = center.x - radius * 0.60 + n * radius * 0.055
            let y = center.y - radius * 0.52 + n * radius * 0.014
            let length = radius * (0.12 + 0.035 * sin(Double(index) * 0.9))
            var stroke = Path()
            stroke.move(to: CGPoint(x: x, y: y))
            stroke.addLine(to: CGPoint(x: x + length, y: y - length * 0.20))
            context.stroke(stroke, with: .color(graphite.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
    }

    private func handStar(center: CGPoint, size: CGFloat, time: Double) -> Path {
        var path = Path()
        let wobble = CGFloat(0.035 * sin(time * 0.8))
        let points: [CGPoint] = [
            CGPoint(x: center.x, y: center.y - size),
            CGPoint(x: center.x + size * 0.24, y: center.y - size * 0.22),
            CGPoint(x: center.x + size, y: center.y + wobble),
            CGPoint(x: center.x + size * 0.22, y: center.y + size * 0.23),
            CGPoint(x: center.x + wobble, y: center.y + size),
            CGPoint(x: center.x - size * 0.22, y: center.y + size * 0.22),
            CGPoint(x: center.x - size, y: center.y),
            CGPoint(x: center.x - size * 0.22, y: center.y - size * 0.23)
        ]
        path.move(to: points[0])
        for index in 1..<points.count {
            let p = points[index]
            let previous = points[index - 1]
            let mid = CGPoint(x: (p.x + previous.x) * 0.5,
                              y: (p.y + previous.y) * 0.5)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addQuadCurve(to: points[0], control: points[points.count - 1])
        return path
    }
}
