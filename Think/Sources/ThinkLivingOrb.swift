import SwiftUI

/// The original hand-drawn Think mark: a solid five-point ink star,
/// surrounded by a lively, tangled cloud of elliptical pen strokes.
/// Each stroke has its own slowly drifting orbit: no solid sphere,
/// no perfect outline and no color or glow.
struct ThinkLivingOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: scenePhase != .active)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false, colorMode: .nonLinear) { context, size in
                let side = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rx = side * 0.385
                let ry = side * 0.265

                // The drawing is a tangle of individual, imperfect strokes.
                // Their angular phases advance at different speeds, giving
                // the impression of loose ink orbiting a fixed thought.
                for index in 0..<29 {
                    let n = Double(index)
                    let path = roamingStroke(center: center, rx: rx, ry: ry,
                                             index: index, time: time)
                    let opacity = (0.42 + 0.38 * (0.5 + 0.5 * sin(n * 3.71)))
                    let width: CGFloat = index.isMultiple(of: 5) ? 2.1 :
                                         (index.isMultiple(of: 3) ? 1.55 : 0.85)
                    context.stroke(path, with: .color(Color.black.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: width,
                                                      lineCap: .round, lineJoin: .round))
                }

                // A few purposeful long loose ends keep it human, like ink
                // that runs beyond the silhouette in the user's sketch.
                for index in 0..<5 {
                    let path = strayLine(center: center, rx: rx, ry: ry,
                                         index: index, time: time)
                    context.stroke(path, with: .color(.black.opacity(index.isMultiple(of:2) ? 0.72 : 0.47)),
                                   style: StrokeStyle(lineWidth: index.isMultiple(of:2) ? 1.45 : 0.9,
                                                      lineCap: .round))
                }

                let starCenter = CGPoint(
                    x: center.x + CGFloat(sin(time * 0.31)) * side * 0.008,
                    y: center.y + CGFloat(cos(time * 0.24)) * side * 0.007
                )
                let star = inkStar(center: starCenter, radius: side * 0.095)
                context.fill(star, with: .color(Color(red: 0.095, green: 0.095, blue: 0.10)))
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Звезда, вокруг которой хаотично движутся нарисованные ручкой линии")
    }

    private func roamingStroke(center: CGPoint, rx: CGFloat, ry: CGFloat,
                               index: Int, time: Double) -> Path {
        let n = Double(index)
        let turns = 0.76 + 0.18 * sin(n * 1.11)
        let start = n * 2.39996 + time * (index.isMultiple(of: 2) ? 0.065 : -0.044)
        let tilt = -0.32 + 0.16 * sin(n * 0.81 + time * 0.17)
        let stretch = 0.67 + 0.50 * (0.5 + 0.5 * cos(n * 2.15))
        let rX = Double(rx) * stretch
        let rY = Double(ry) * (0.76 + 0.48 * (0.5 + 0.5 * sin(n * 1.62)))
        let offsetX = Double(rx) * 0.11 * sin(n * 1.88 + time * 0.21)
        let offsetY = Double(ry) * 0.11 * cos(n * 2.13 - time * 0.19)

        var path = Path()
        let steps = 70
        for step in 0...steps {
            let u = Double(step) / Double(steps)
            let angle = start + 2 * Double.pi * turns * u
            let wander = 1 + 0.095 * sin(angle * 3.1 + n * 1.77 + time * 0.14)
                           + 0.036 * sin(angle * 8.0 + n * 0.93)
            let rawX = cos(angle) * rX * wander
            let rawY = sin(angle) * rY * wander
            let x = rawX * cos(tilt) - rawY * sin(tilt)
            let y = rawX * sin(tilt) + rawY * cos(tilt)
            let point = CGPoint(x: center.x + CGFloat(x + offsetX),
                                y: center.y + CGFloat(y + offsetY))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func strayLine(center: CGPoint, rx: CGFloat, ry: CGFloat,
                           index: Int, time: Double) -> Path {
        let n = Double(index)
        let sway = 0.08 * sin(time * 0.27 + n)
        let side = index.isMultiple(of: 2) ? -1.0 : 1.0
        let from = CGPoint(x: center.x + CGFloat(side * Double(rx) * (0.37 + sway)),
                           y: center.y + CGFloat(Double(ry) * (0.55 * sin(n * 1.3))))
        let to = CGPoint(x: center.x - CGFloat(side * Double(rx) * (1.05 + sway)),
                         y: center.y + CGFloat(Double(ry) * (0.82 * cos(n * 1.2))))
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to,
                      control1: CGPoint(x: center.x + CGFloat(side * Double(rx) * 1.15),
                                       y: center.y - ry * CGFloat(0.88 + 0.07 * sin(time * 0.3 + n))),
                      control2: CGPoint(x: center.x - CGFloat(side * Double(rx) * 0.5),
                                       y: center.y + ry * CGFloat(1.4 + 0.05 * cos(time * 0.2 + n))))
        return path
    }

    private func inkStar(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for vertex in 0..<10 {
            let angle = -Double.pi / 2 + Double(vertex) * Double.pi / 5
            let irregular = [1.04, 0.47, 0.93, 0.43, 1.07, 0.48, 0.96, 0.44, 1.02, 0.50][vertex]
            let r = Double(radius) * irregular
            let p = CGPoint(x: center.x + CGFloat(cos(angle) * r),
                            y: center.y + CGFloat(sin(angle) * r))
            if vertex == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
