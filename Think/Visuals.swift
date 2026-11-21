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



enum AppPalette: String, CaseIterable, Identifiable {
    case white, silver, ice, lavender, rose, amber, sage, mint, coral
    var id: String { rawValue }
    var name: String {
        switch self {
        case .white: "Белый"
        case .silver: "Серебро"
        case .ice: "Лёд"
        case .lavender: "Лаванда"
        case .rose: "Роза"
        case .amber: "Янтарь"
        case .sage: "Шалфей"
        case .mint: "Мята"
        case .coral: "Коралл"
        }
    }
    var accent: Color {
        switch self {
        case .white: .white
        case .silver: Color(red:0.84,green:0.85,blue:0.88)
        case .ice: Color(red:0.67,green:0.76,blue:0.94)
        case .lavender: Color(red:0.79,green:0.71,blue:1)
        case .rose: Color(red:1,green:0.69,blue:0.82)
        case .amber: Color(red:1,green:0.79,blue:0.47)
        case .sage: Color(red:0.72,green:0.84,blue:0.64)
        case .mint: Color(red:0.58,green:0.90,blue:0.83)
        case .coral: Color(red:1,green:0.69,blue:0.58)
        }
    }
    var ink: Color { accent }
    var muted: Color { self == .white ? .white : accent.opacity(0.63) }
    var sheet: Color { accent.opacity(0.032).overBlack }
    var card: Color { accent.opacity(0.105).overBlack }
}

private extension Color {
    var overBlack: Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r,green:&g,blue:&b,alpha:&a)
        return Color(red:r*a,green:g*a,blue:b*a)
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = AppPalette.white }
extension EnvironmentValues {
    var appPalette: AppPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum Bloom: String, Codable, CaseIterable, Identifiable {
    case daisy, rose, lily, tulip, poppy, lavender, iris, sunflower, bell, lotus
    var id: String { rawValue }
    var name: String {
        switch self {
        case .daisy: "Ромашка"
        case .rose: "Роза"
        case .lily: "Лилия"
        case .tulip: "Тюльпан"
        case .poppy: "Мак"
        case .lavender: "Лаванда"
        case .iris: "Ирис"
        case .sunflower: "Подсолнух"
        case .bell: "Колокольчик"
        case .lotus: "Лотос"
        }
    }
}

struct Flower: View {
    var kind: Bloom = .daisy
    @Environment(\.appPalette) private var palette
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x:size.width/44,y:size.height/64)
            var p = Path()
            func point(_ x: Double,_ y: Double) -> CGPoint { CGPoint(x:x,y:y) }
            func loop(cx: Double,cy: Double,rx: Double,ry: Double,petals: Double,depth: Double,phase: Double = 0) {
                for i in 0...100 {
                    let a = Double(i)*Double.pi/50
                    let r = 1 + depth*cos(petals*a+phase) + 0.035*sin(a*3)
                    let pt = point(cx+rx*r*cos(a),cy+ry*r*sin(a))
                    if i == 0 { p.move(to:pt) } else { p.addLine(to:pt) }
                }
                p.closeSubpath()
            }
            func petal(_ tip: CGPoint,_ left: CGPoint,_ right: CGPoint,_ base: CGPoint) {
                p.move(to:base); p.addQuadCurve(to:tip,control:left)
                p.addQuadCurve(to:base,control:right)
            }
            switch kind {
            case .daisy,.poppy,.sunflower:
                let count: Double = kind == .daisy ? 6 : kind == .poppy ? 4 : 12
                loop(cx:22,cy:21,rx:13,ry:12,petals:count,depth:kind == .sunflower ? 0.13 : 0.23,phase:0.5)
                p.addEllipse(in:CGRect(x:kind == .sunflower ? 16 : 19,y:kind == .sunflower ? 15 : 18,width:kind == .sunflower ? 12 : 6,height:kind == .sunflower ? 12 : 6))
            case .rose:
                loop(cx:22,cy:21,rx:13,ry:11,petals:5,depth:0.14)
                for i in 0...75 {
                    let a = Double(i)/75*4.6*Double.pi
                    let r = 0.7+Double(i)*0.117
                    let pt = point(22+r*cos(a),21+r*0.87*sin(a))
                    if i == 0 { p.move(to:pt) } else { p.addLine(to:pt) }
                }
            case .lily,.iris,.lotus:
                let base = point(22,33)
                let height: Double = kind == .iris ? 12 : 6
                petal(point(22,height),point(11,20),point(33,20),base)
                petal(point(5,kind == .lotus ? 15 : 11),point(7,30),point(20,11),base)
                petal(point(39,kind == .lotus ? 15 : 11),point(37,30),point(24,11),base)
                if kind != .lily {
                    petal(point(3,25),point(9,39),point(15,23),base)
                    petal(point(41,25),point(35,39),point(29,23),base)
                } else { p.addEllipse(in:CGRect(x:20,y:20,width:4,height:5)) }
            case .tulip:
                let base = point(22,34)
                p.move(to:base); p.addQuadCurve(to:point(9,10),control:point(8,29))
                p.addQuadCurve(to:point(19,17), control:point(16,10))
                p.addQuadCurve(to:point(22,8),control:point(20,11))
                p.addQuadCurve(to:point(28,17),control:point(27,11))
                p.addQuadCurve(to:point(36,10),control:point(31,12))
                p.addQuadCurve(to:base,control:point(37,32)); p.closeSubpath()
            case .lavender:
                p.move(to:point(22,10)); p.addQuadCurve(to:point(22,36),control:point(24,21))
                for i in 0..<5 {
                    let y = 9+Double(i)*5
                    p.addEllipse(in:CGRect(x:15-Double(i)*0.6,y:y,width:7,height:4))
                    p.addEllipse(in:CGRect(x:23,y:y+1,width:7+Double(i)*0.6,height:4))
                }
            case .bell:
                p.move(to:point(22,7)); p.addQuadCurve(to:point(8,31),control:point(12,10))
                p.addQuadCurve(to:point(37,31),control:point(23,39))
                p.addQuadCurve(to:point(22,7),control:point(34,11))
                p.move(to:point(9,31));p.addQuadCurve(to:point(36,31),control:point(22,20))
            }
            p.move(to:point(22,35)); p.addQuadCurve(to:point(21,60),control:point(23,48))
            let leaf = point(22,52)
            petal(point(10,41),point(10,52),point(21,39),leaf)
            petal(point(34,42),point(34,51),point(25,39),leaf)
            ctx.stroke(p,with:.color(palette.accent),style:StrokeStyle(lineWidth:1.7,lineCap:.round,lineJoin:.round))
        }.accessibilityHidden(true)
    }
}


