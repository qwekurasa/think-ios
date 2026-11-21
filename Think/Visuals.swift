import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<256 {
            let a: Double = Double(i) * Double.pi / 128
            let r: Double = 0.46 * (0.37 + 0.63 * pow(abs(cos(4.0 * a)), 6.0))
            let point = CGPoint(x: rect.midX + rect.width * CGFloat(r * cos(a)),
                                y: rect.midY + rect.height * CGFloat(r * sin(a)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct ParticleStar: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    let cool: Bool
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced || phase != .active)) { timeline in
            let time = reduced ? 0 : timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                let scale = min(size.width, size.height) * (0.39 + 0.012 * sin(time * 1.4))
                let cx = size.width / 2, cy = size.height / 2
                for j in 1..<53 {
                    let phi = Double(j) * .pi / 53
                    let u = sin(phi), z = cos(phi)
                    for i in 0..<112 {
                        let a: Double = Double(i) * Double.pi / 56 + time * 0.16
                        let swell = 1.0 + 0.046 * sin(3*a + 4*phi - time) * u
                        let depth = u * sin(a)
                        let x = u * cos(a) * swell
                        let y = (z * 0.95 + depth * 0.24) * swell
                        let light = 0.5 + 0.5 * sin(2*a - phi + time * 0.24)
                        let alpha = (0.2 + 0.77 * light) * (depth > 0 ? 1 : 0.30)
                        let dot = 0.8 + 1.0 * light + max(0,depth) * 0.45
                        let color = cool ? Color(red: 0.7, green: 0.82, blue: 1) : Color(red: 1, green: 0.69 + 0.24 * light, blue: 0.31 + 0.39 * light)
                        context.fill(Path(ellipseIn: CGRect(x: cx + scale * x, y: cy + scale * y, width: dot, height: dot)), with: .color(color.opacity(alpha)))
                    }
                }
                for i in 0..<270 {
                    let a = Double(i) * 2.39996
                    let f = (Double((i * 113) % 271) / 271 + time * 0.11).truncatingRemainder(dividingBy: 1)
                    let r = 0.98 + f * 0.28
                    let x = cx + scale * r * cos(a), y = cy + scale * r * sin(a)
                    let dot = 0.8 + Double(i % 3) * 0.36
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)), with: .color((cool ? Color.cyan : .yellow).opacity(0.55 * (1 - f))))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct QRSheet: View {
    let idea: Idea
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var revealed = false
    @State private var image: UIImage?
    private var payload: String { idea.step.isEmpty ? idea.text : idea.text + "\n\n" + idea.step }
    var body: some View {
        VStack(spacing: 22) {
            Text("Поделиться мыслью").font(.title.bold())
            if let image {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .padding(22).background(.white).frame(maxWidth: 320)
                    .mask { GeometryReader { g in Rectangle().frame(height: g.size.height * (revealed ? 1 : 0)) } }
                    .accessibilityLabel("QR-код с текстом идеи")
            } else { Text("Готовим код…").foregroundStyle(.secondary) }
            Text("Наведи камеру или QR-сканер на код, чтобы прочитать идею.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            ShareLink(item: payload) { Label("Отправить текст", systemImage: "square.and.arrow.up") }
        }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white).preferredColorScheme(.light)
        .task {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "L"
            guard let output = filter.outputImage else { return }
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
            guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return }
            image = UIImage(cgImage: cg)
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(reduced ? nil : .easeOut(duration: 0.65)) { revealed = true }
        }
    }
}
