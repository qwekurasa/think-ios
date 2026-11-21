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
    let onTap: () -> Void
    @State private var yaw = 0.0
    @State private var pitch = 0.0
    @State private var spinX = 0.0
    @State private var spinY = 0.0
    @State private var released = Date()
    @State private var dragging = false
    @State private var previous = CGSize.zero
    @State private var motionPhase = 0.0
    private func coast(_ now: Date) -> Double {
        (1-exp(-3*max(0,now.timeIntervalSince(released))))/3
    }
    private var interaction: some Gesture {
        DragGesture(minimumDistance: 6).onChanged { value in
            if !dragging {
                let distance = reduced ? 0 : coast(value.time)
                yaw += spinX*distance; pitch += spinY*distance
                motionPhase += hypot(spinX,spinY)*distance
                previous = .zero; dragging = true
            }
            let dx = Double(value.translation.width-previous.width)*0.013
            let dy = Double(value.translation.height-previous.height)*0.013
            yaw += dx; pitch += dy
            motionPhase += hypot(dx,dy)
            previous = value.translation
            spinX = max(-12,min(12,Double(value.velocity.width)*0.013))
            spinY = max(-12,min(12,Double(value.velocity.height)*0.013))
        }.onEnded { value in
            spinX = reduced ? 0 : max(-12,min(12,Double(value.velocity.width)*0.013))
            spinY = reduced ? 0 : max(-12,min(12,Double(value.velocity.height)*0.013))
            released = value.time; dragging = false
        }.exclusively(before: TapGesture().onEnded { onTap() })
    }
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced || phase != .active)) { timeline in
            let time = reduced ? 0 : timeline.date.timeIntervalSince(start)
            let distance = dragging || reduced ? 0 : coast(timeline.date)
            let turn = yaw + spinX*distance
            let tilt = pitch + spinY*distance
            let travel = reduced ? 0 : motionPhase + hypot(spinX,spinY)*distance
            let particleTime = time + travel*1.6
            Canvas { context, size in
                let radius = min(size.width,size.height) * 0.345
                let cx = size.width / 2, cy = size.height / 2
                let phase = particleTime.truncatingRemainder(dividingBy: 7.6)
                let sweep = phase < 3.2 ? min(1,max(0,(phase-0.8)/2.4)) : min(1,max(0,(7.1-phase)/2.1))
                for row in 1..<52 {
                    let phi = Double(row) * Double.pi / 52
                    let count = max(8,Int(110*sin(phi)))
                    for column in 0..<count {
                        let a = 2*Double.pi*Double(column)/Double(count) + time*0.12 - turn
                        let x = sin(phi)*cos(a)
                        let depth = sin(phi)*sin(a)
                        let y = cos(phi)*cos(tilt) + depth*sin(tilt)
                        let z = depth*cos(tilt) - cos(phi)*sin(tilt)
                        let seed = Double((column*317 + row*751 + row*column*29) % 997)/997
                        let local = max(0,min(1,(sweep*2.5 - (1-x))*2))
                        let drift = local*(0.02+seed*0.13)
                        let px = x + drift*(0.5+cos(a*3+particleTime*2+seed*18))
                        let py = y + drift*(sin(phi*6+seed*20-particleTime*1.7)-0.4)
                        let light = 0.23 + 0.67*(z+1)/2
                        let dot = 0.68 + 0.75*seed + local*0.45
                        let color = Color(white: cool ? 1.0 : 0.84)
                        let rect = CGRect(x:cx+radius*px,y:cy+radius*py,width:dot,height:dot)
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(light*(1-0.38*local))))
                    }
                }
            }
        }.contentShape(Rectangle()).gesture(interaction)
         .accessibilityElement(children:.ignore).accessibilityLabel("Записать идею")
         .accessibilityAddTraits(.isButton).accessibilityAction { onTap() }
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
        .background(Color.white).preferredColorScheme(.light).tint(.black)
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
