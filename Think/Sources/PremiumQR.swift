import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct ThinkQRMatrix {
    let side: Int
    let filled: [CGPoint]

    static func generate(from text: String) -> ThinkQRMatrix? {
        // Raw text in the QR means any QR scanner can read it.
        // Very long notes are shared as text because a dense QR is unreliable.
        guard !text.isEmpty, text.utf8.count <= 550 else { return nil }
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(text.utf8)
        generator.correctionLevel = "M"
        guard let image = generator.outputImage else { return nil }
        let n = Int(image.extent.width)
        guard n > 0, n <= 145 else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var rgba = [UInt8](repeating: 255, count: n * n * 4)
        rgba.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress {
                context.render(
                    image,
                    toBitmap: base,
                    rowBytes: n * 4,
                    bounds: image.extent,
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
            }
        }
        var cells: [CGPoint] = []
        cells.reserveCapacity(n * n / 2)
        for row in 0..<n {
            for column in 0..<n {
                let i = (row * n + column) * 4
                if rgba[i] < 128 {
                    cells.append(CGPoint(x: column, y: n - 1 - row))
                }
            }
        }
        return ThinkQRMatrix(side: n, filled: cells)
    }
}

struct AnimatedThinkQR: View {
    let matrix: ThinkQRMatrix
    var radiant: Bool = false
    @State private var began = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = max(0, timeline.date.timeIntervalSince(began))
            let progress = min(1.0, t / 1.6)
            let eased = progress * progress * (3 - 2 * progress)
            Canvas { context, size in
                let padding: CGFloat = 23
                let span = min(size.width, size.height) - padding * 2
                let cell = span / CGFloat(matrix.side)
                let radius = cell * 0.40
                for (index, module) in matrix.filled.enumerated() {
                    let i = Double(index)
                    let fx = (sin(i * 89.171) * 0.5 + 0.5) * Double(span) + Double(padding)
                    let fy = (cos(i * 41.993) * 0.5 + 0.5) * Double(span) + Double(padding)
                    let destinationX = padding + (module.x + 0.5) * cell
                    let destinationY = padding + (module.y + 0.5) * cell
                    let x = CGFloat(fx) * (1 - eased) + destinationX * eased
                    let y = CGFloat(fy) * (1 - eased) + destinationY * eased
                    let r = radius * CGFloat(0.7 + eased * 0.3)
                    let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(
                        (radiant ? Color(red: 0.65 + 0.26 * sin(i * 0.015), green: 0.20 + 0.12 * sin(i * 0.025), blue: 0.85) : Color(red: 0.38, green: 0.13, blue: 0.65)).opacity(0.35 + eased * 0.65)
                    ))
                }
            }
        }
        .background(.white)
        .onAppear { began = Date() }
        .accessibilityLabel("QR-код с текстом идеи")
    }
}

struct PremiumQRScreen: View {
    @EnvironmentObject private var store: IdeaStore
    let text: String
    @Environment(\.dismiss) private var dismiss
    private var matrix: ThinkQRMatrix? {
        ThinkQRMatrix.generate(from: text)
    }

    var body: some View {
        ZStack {
            SoftPurpleAtmosphere()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17))
                            .frame(width: 43, height: 43)
                    }
                    Spacer()
                    Text("ПОДЕЛИТЬСЯ ИДЕЕЙ")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.6)
                    Spacer()
                    Color.clear.frame(width: 43, height: 43)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 19).padding(.top, 13)
                Spacer()
                if let matrix {
                    AnimatedThinkQR(matrix: matrix, radiant: store.qrStyleUnlocked)
                        .frame(width: 302, height: 302)
                        .accessibilityAddTraits(.isImage)
                        .padding(.bottom, 29)
                    Text("Открой мысль на любом устройстве")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text("Наведи камеру на QR-код.\nПриложение Think не требуется.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                } else {
                    ThinkStar().fill(Theme.purple).frame(width: 55, height: 55)
                    Text("Слишком много текста для QR")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.ink).padding(.top, 22)
                    Text("Отправь эту идею обычным текстом.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 12)
                }
                Spacer()
                ShareLink(item: text) {
                    Label("Поделиться текстом", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ThinkActionStyle(filled: true))
                .padding(.horizontal, 28).padding(.bottom, 28)
            }
        }
    }
}
