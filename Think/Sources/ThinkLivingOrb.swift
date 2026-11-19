import SwiftUI

/// A procedural light sphere. Every highlight and ribbon is drawn in real time:
/// no prerecorded movie, static render, or remote asset is used.
struct ThinkLivingOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: scenePhase != .active)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false, colorMode: .linear) { context, size in
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let radius = min(size.width, size.height) * 0.405
                let t = reduceMotion ? 0 : elapsed
                let cycle = (t.truncatingRemainder(dividingBy: 10) / 10) * 2 * Double.pi
                let pulse = 0.5 + 0.5 * cos(cycle)
                let reveal = 0.12 + 0.88 * pow(pulse, 1.15)

                drawAtmosphere(in: &context, center: center, radius: radius, time: t)
                drawSphere(in: &context, center: center, radius: radius, time: t, reveal: reveal)
                drawRibbons(in: &context, center: center, radius: radius, time: t, reveal: reveal)
                drawOrbitSparks(in: &context, center: center, radius: radius, time: t, reveal: reveal)
                // No outline: the light is allowed to feather naturally into white.
            }
            .drawingGroup(opaque: false, colorMode: .linear)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Светящийся шар Think с движущимися потоками света")
    }

    private func drawAtmosphere(in context: inout GraphicsContext,
                                center: CGPoint, radius: CGFloat, time: Double) {
        let breathe = 1 + 0.035 * sin(time * 0.62)
        let rect = CGRect(x: center.x - radius * 1.48 * breathe,
                          y: center.y - radius * 1.48 * breathe,
                          width: radius * 2.96 * breathe,
                          height: radius * 2.96 * breathe)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.48, green: 0.24, blue: 0.92).opacity(0.25),
                    Color(red: 0.22, green: 0.57, blue: 1.0).opacity(0.11),
                    Color(red: 0.94, green: 0.34, blue: 0.78).opacity(0.08),
                    .clear
                ]),
                center: center,
                startRadius: radius * 0.25,
                endRadius: radius * 1.48 * breathe
            )
        )
    }

    private func drawSphere(in context: inout GraphicsContext,
                            center: CGPoint, radius: CGFloat,
                            time: Double, reveal: Double) {
        // There is deliberately no solid circle or border.
        // The core fades to fully transparent before reaching its outer bounds.
        let fadeRadius = radius * 1.38
        let softCore = Path(ellipseIn: CGRect(
            x: center.x - fadeRadius, y: center.y - fadeRadius,
            width: fadeRadius * 2, height: fadeRadius * 2
        ))
        let light = CGPoint(
            x: center.x + CGFloat(sin(time * 0.24)) * radius * 0.10,
            y: center.y - radius * 0.10
        )
        context.fill(
            softCore,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.09, green: 0.07, blue: 0.21).opacity(0.77 * reveal), location: 0),
                    .init(color: Color(red: 0.14, green: 0.11, blue: 0.30).opacity(0.63 * reveal), location: 0.36),
                    .init(color: Color(red: 0.30, green: 0.17, blue: 0.53).opacity(0.24 * reveal), location: 0.68),
                    .init(color: Color(red: 0.47, green: 0.28, blue: 0.78).opacity(0.04 * reveal), location: 0.91),
                    .init(color: .clear, location: 1)
                ]),
                center: light,
                startRadius: 0,
                endRadius: fadeRadius
            )
        )

        // Soft, internal glass highlight without any hard ellipse cutoff.
        let sheen = Path(ellipseIn: CGRect(
            x: center.x - radius * 0.86,
            y: center.y - radius * 0.95,
            width: radius * 1.37,
            height: radius * 0.62
        ))
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: radius * 0.19))
            glow.fill(
                sheen,
                with: .linearGradient(
                    Gradient(colors: [
                        .white.opacity(0.27 * reveal),
                        Color(red: 0.68, green: 0.79, blue: 1).opacity(0.10 * reveal),
                        .clear
                    ]),
                    startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                    endPoint: CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 0.10)
                )
            )
        }
    }

    private func drawRibbons(in context: inout GraphicsContext,
                             center: CGPoint, radius: CGFloat,
                             time: Double, reveal: Double) {
        let palette: [[Color]] = [
            [
                Color(red: 0.24, green: 0.75, blue: 1.0),
                Color(red: 0.67, green: 0.43, blue: 1.0),
                Color(red: 1.0, green: 0.43, blue: 0.79),
                Color(red: 1.0, green: 0.84, blue: 0.98)
            ],
            [
                Color(red: 0.94, green: 0.37, blue: 0.78),
                Color(red: 0.58, green: 0.45, blue: 1.0),
                Color(red: 0.28, green: 0.77, blue: 1.0),
                Color(red: 0.88, green: 0.75, blue: 1.0)
            ],
            [
                Color(red: 0.36, green: 0.62, blue: 1.0),
                Color(red: 0.91, green: 0.45, blue: 0.94),
                Color(red: 1.0, green: 0.68, blue: 0.84)
            ]
        ]

        // No hard clipping to a circular silhouette: light blends into the background.
        var clipped = context

        for index in 0..<3 {
            let phase = time * (0.42 + Double(index) * 0.075) + Double(index) * 2.05
            let path = flowingRibbon(center: center, radius: radius * (0.78 - CGFloat(index) * 0.055),
                                     phase: phase, index: index)
            let colors = palette[index]
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors.map { $0.opacity(0.92 * reveal) }),
                startPoint: CGPoint(x: center.x - radius, y: center.y - radius * 0.55),
                endPoint: CGPoint(x: center.x + radius, y: center.y + radius * 0.62)
            )

            clipped.drawLayer { glow in
                glow.addFilter(.blur(radius: radius * 0.105))
                glow.stroke(path, with: gradient,
                            style: StrokeStyle(lineWidth: radius * 0.145,
                                               lineCap: .round, lineJoin: .round))
            }
            clipped.drawLayer { bloom in
                bloom.addFilter(.blur(radius: radius * 0.035))
                bloom.stroke(path, with: gradient,
                             style: StrokeStyle(lineWidth: radius * 0.052,
                                                lineCap: .round, lineJoin: .round))
            }
            clipped.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        .white.opacity(0.92 * reveal),
                        colors[0].opacity(0.95 * reveal),
                        colors[1].opacity(0.95 * reveal),
                        colors[2].opacity(0.98 * reveal),
                        .white.opacity(0.82 * reveal)
                    ]),
                    startPoint: CGPoint(x: center.x - radius, y: center.y - radius * 0.7),
                    endPoint: CGPoint(x: center.x + radius, y: center.y + radius * 0.7)
                ),
                style: StrokeStyle(lineWidth: max(1.15, radius * 0.014),
                                   lineCap: .round, lineJoin: .round)
            )
        }

        // A moving bright knot makes the light paths feel connected and alive.
        let knot = CGPoint(
            x: center.x + CGFloat(cos(time * 0.48)) * radius * 0.13,
            y: center.y + CGFloat(sin(time * 0.61)) * radius * 0.12
        )
        let knotRect = CGRect(x: knot.x - radius * 0.085, y: knot.y - radius * 0.085,
                              width: radius * 0.17, height: radius * 0.17)
        clipped.drawLayer { glow in
            glow.addFilter(.blur(radius: radius * 0.10))
            glow.fill(Path(ellipseIn: knotRect), with: .color(Color(red: 0.98, green: 0.65, blue: 1).opacity(0.95 * reveal)))
        }
        clipped.fill(Path(ellipseIn: knotRect.insetBy(dx: radius * 0.045, dy: radius * 0.045)),
                     with: .color(.white.opacity(0.85 * reveal)))
    }

    private func flowingRibbon(center: CGPoint, radius: CGFloat,
                               phase: Double, index: Int) -> Path {
        var path = Path()
        let steps = 150
        let direction = index == 1 ? -1.0 : 1.0
        for step in 0...steps {
            let u = Double(step) / Double(steps)
            let angle = u * 2 * Double.pi
            let waveA = sin(angle * 2 + phase * direction)
            let waveB = cos(angle * 3 - phase * 0.72 + Double(index))
            let waveC = sin(angle * 1.5 + phase * 0.48)
            let radial = Double(radius) * (0.48 + 0.17 * waveA + 0.095 * waveB)
            let x = center.x + CGFloat(cos(angle + phase * 0.16) * radial)
            let y = center.y + CGFloat(sin(angle + phase * 0.16) * radial * (0.74 + 0.08 * waveC))
            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawOrbitSparks(in context: inout GraphicsContext,
                                 center: CGPoint, radius: CGFloat,
                                 time: Double, reveal: Double) {
        for index in 0..<9 {
            let n = Double(index)
            let angle = n * 2.39996 + time * (index.isMultiple(of: 2) ? 0.13 : -0.10)
            let orbit = Double(radius) * (0.76 + 0.12 * sin(n * 1.8 + time * 0.2))
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * CGFloat(orbit),
                                y: center.y + CGFloat(sin(angle)) * CGFloat(orbit))
            let starSize = CGFloat(2.0 + 2.2 * (0.5 + 0.5 * sin(time * 1.1 + n)))
            let star = fourPointStar(at: point, size: starSize)
            let tint = index.isMultiple(of: 2)
                ? Color(red: 0.47, green: 0.75, blue: 1)
                : Color(red: 1, green: 0.62, blue: 0.86)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 5))
                glow.fill(star, with: .color(tint.opacity(0.78 * reveal)))
            }
            context.fill(star, with: .color(.white.opacity(0.9 * reveal)))
        }
    }

    private func fourPointStar(at center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - size))
        path.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y),
                          control: CGPoint(x: center.x + size * 0.17, y: center.y - size * 0.17))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size),
                          control: CGPoint(x: center.x + size * 0.17, y: center.y + size * 0.17))
        path.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y),
                          control: CGPoint(x: center.x - size * 0.17, y: center.y + size * 0.17))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size),
                          control: CGPoint(x: center.x - size * 0.17, y: center.y - size * 0.17))
        path.closeSubpath()
        return path
    }
}
