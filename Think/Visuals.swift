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
                let radius = min(size.width,size.height) * 0.345
                let cx = size.width / 2, cy = size.height / 2
                let phase = time.truncatingRemainder(dividingBy: 7.6)
                let sweep = phase < 3.2 ? min(1,max(0,(phase-0.8)/2.4)) : min(1,max(0,(7.1-phase)/2.1))
                for row in 1..<52 {
                    let phi = Double(row) * Double.pi / 52
                    let count = max(8,Int(110*sin(phi)))
                    for column in 0..<count {
                        let a = 2*Double.pi*Double(column)/Double(count) + time*0.12
                        let x = sin(phi)*cos(a), z = sin(phi)*sin(a), y = cos(phi)
                        let seed = Double((column*317 + row*751 + row*column*29) % 997)/997
                        let local = max(0,min(1,(sweep*2.5 - (1-x))*2))
                        let drift = local*(0.02+seed*0.13)
                        let px = x + drift*(0.5+cos(a*3+time*2+seed*18))
                        let py = y + drift*(sin(phi*6+seed*20-time*1.7)-0.4)
                        let light = 0.23 + 0.67*(z+1)/2
                        let dot = 0.68 + 0.75*seed + local*0.45
                        let color = cool ? Color(red: 0.76, green: 0.85, blue: 1) : Color(white: 0.94)
                        let rect = CGRect(x:cx+radius*px,y:cy+radius*py,width:dot,height:dot)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(light*(1-0.38*local))))
                    }
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
