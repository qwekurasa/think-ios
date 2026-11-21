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


import simd

enum Paper {
    private static func inkColor(_ light: UIColor,_ dark: UIColor) -> Color {
        Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let sheet = inkColor(UIColor(white:0.965,alpha:1),UIColor(white:0.075,alpha:1))
    static let ink = inkColor(UIColor(white:0.085,alpha:1),UIColor(white:0.94,alpha:1))
    static let blue = inkColor(UIColor(red:0.22,green:0.35,blue:0.50,alpha:1),UIColor(red:0.67,green:0.76,blue:0.89,alpha:1))
    static let card = inkColor(UIColor.white,UIColor(white:0.14,alpha:1))
}

struct Flower: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width/44, sy = size.height/64
            ctx.scaleBy(x:sx,y:sy)
            var bloom = Path()
            for i in 0...144 {
                let a = Double(i)*Double.pi/72
                let r = 11.5 + 3.3*cos(5*a + 0.6) + 1.1*sin(3*a)
                let pt = CGPoint(x:22+r*cos(a),y:20+r*sin(a))
                if i == 0 { bloom.move(to:pt) } else { bloom.addLine(to:pt) }
            }
            bloom.closeSubpath()
            bloom.addEllipse(in:CGRect(x:19,y:17,width:6,height:7))
            bloom.move(to:CGPoint(x:22,y:36))
            bloom.addQuadCurve(to:CGPoint(x:21,y:60),control:CGPoint(x:23,y:48))
            bloom.move(to:CGPoint(x:22,y:52))
            bloom.addQuadCurve(to:CGPoint(x:11,y:42),control:CGPoint(x:11,y:51))
            bloom.addQuadCurve(to:CGPoint(x:22,y:52),control:CGPoint(x:21,y:40))
            bloom.addQuadCurve(to:CGPoint(x:33,y:42),control:CGPoint(x:33,y:50))
            bloom.addQuadCurve(to:CGPoint(x:22,y:52),control:CGPoint(x:25,y:39))
            ctx.stroke(bloom,with:.color(Paper.blue),style:StrokeStyle(lineWidth:1.9,lineCap:.round,lineJoin:.round))
        }.accessibilityHidden(true)
    }
}

struct ParticleStar: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) var reduced
    @Environment(\.scenePhase) var phase
    let cool: Bool
    let onTap: () -> Void
    func makeUIView(context: Context) -> OrbSurface { OrbSurface() }
    func updateUIView(_ view: OrbSurface, context: Context) {
        view.yellow = cool
        view.reduced = reduced
        view.active = phase == .active
        view.onTap = onTap
        view.refreshClock()
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view: OrbSurface, coordinator: ()) { view.stopClock() }
}

final class OrbSurface: UIView {
    struct Dot { let normal: SIMD3<Double>; let phase: Double; let diameter: Double }
    private static let dots: [Dot] = {
        var result = [Dot]()
        for row in 1..<39 {
            let phi = Double(row)*Double.pi/39
            let count = max(6,Int(80*sin(phi)))
            for i in 0..<count {
                let a = 2*Double.pi*(Double(i)+Double(row%2)*0.5)/Double(count)
                let seed = Double((row*751+i*317+row*i*29)%997)/997
                result.append(Dot(normal: SIMD3(sin(phi)*cos(a),cos(phi),sin(phi)*sin(a)),phase:seed*2*Double.pi,diameter:0.9+seed*1.0))
            }
        }
        return result
    }()
    var yellow = false
    var reduced = false
    var active = true
    var onTap: (() -> Void)?
    private var link: CADisplayLink?
    override init(frame: CGRect) {
        super.init(frame:frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Записать идею"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityActivate() -> Bool { onTap?(); return true }
    override func didMoveToWindow() { super.didMoveToWindow(); refreshClock(); setNeedsDisplay() }
    func refreshClock() {
        guard active, window != nil, !reduced || held else { stopClock(); return }
        guard link == nil else { return }
        let timer = CADisplayLink(target:self,selector:#selector(tick(_:)))
        timer.preferredFramesPerSecond = 60
        timer.add(to:.main,forMode:.common)
        link = timer
    }
    func stopClock() { link?.invalidate(); link = nil; lastFrame = nil }
    private var orientation = simd_quatd(angle: 0, axis: SIMD3(0,1,0))
    private var velocity = SIMD2<Double>.zero
    private var pending = SIMD2<Double>.zero
    private var lastFrame: TimeInterval?
    private var previousTouch = CGPoint.zero
    private var origin = CGPoint.zero
    private var lastInput = 0.0
    private var held = false
    private var dragged = false
    private var clock = 0.0
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        previousTouch = touch.location(in:self)
        origin = previousTouch
        held = true; dragged = false; refreshClock()
        lastInput = touch.timestamp
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard held, let touch = touches.first else { return }
        let point = touch.location(in:self)
        if !dragged && hypot(point.x-origin.x,point.y-origin.y) < 5 { return }
        dragged = true
        let sensitivity = 2.5/max(65,min(bounds.width,bounds.height)*0.345)
        let delta = SIMD2(Double(point.x-previousTouch.x),Double(previousTouch.y-point.y))*sensitivity
        let dt = max(1.0/240,min(0.1,touch.timestamp-lastInput))
        pending += delta
        let sample = delta/dt
        let limited = sample * min(1, 11/max(0.001,simd_length(sample)))
        velocity += (limited-velocity)*(1-exp(-dt*19))
        previousTouch = point
        lastInput = touch.timestamp
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard held else { return }
        let idle = max(0,(touches.first?.timestamp ?? lastInput)-lastInput)
        velocity *= exp(-idle*18)
        held = false
        if reduced { applyPending(); refreshClock() }; if !dragged { onTap?() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        held = false; velocity = .zero; if reduced { applyPending(); refreshClock() }
    }
    private func applyPending() {
        let angle = simd_length(pending)
        if angle > 0.000001 {
            orientation = simd_normalize(simd_quatd(angle:angle,axis:SIMD3(-pending.y,pending.x,0)/angle)*orientation)
        }
        pending = .zero
        setNeedsDisplay()
    }
    @objc private func tick(_ link: CADisplayLink) {
        let time = link.timestamp
        let dt = min(0.05,max(0,time-(lastFrame ?? time)))
        lastFrame = time
        var delta = pending*(1-exp(-dt*36))
        pending -= delta
        if !held {
            let decay = exp(-dt*2.8)
            if !reduced { delta += velocity*((1-decay)/2.8); delta.x += dt*0.12 }
            velocity *= decay
        }
        let angle = simd_length(delta)
        if angle > 0.000001 {
            let axis = SIMD3(-delta.y,delta.x,0)/angle
            orientation = simd_normalize(simd_quatd(angle:angle,axis:axis)*orientation)
        }
        if !reduced { clock += dt + angle*0.65 }
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let buckets = (0..<8).map { _ in CGMutablePath() }
        let matrix = simd_double3x3(orientation)
        let radius = min(bounds.width,bounds.height)*0.345
        let front = 1.5*cos(clock*0.83)
        for dot in Self.dots {
            let v = matrix*dot.normal
            let blend = reduced ? 0 : min(1,max(0,(dot.normal.x-front)*1.8))
            let displacement = blend*blend*(3-2*blend)*0.09
            let x = v.x + displacement*cos(dot.phase+clock*1.6)
            let y = v.y + displacement*sin(dot.phase*2+clock*1.3)
            let d = dot.diameter
            buckets[min(7,max(0,Int((v.z+1)*3.99)))].addEllipse(in:CGRect(x:bounds.midX+radius*x-d/2,y:bounds.midY-radius*y-d/2,width:d,height:d))
        }
        let color = yellow ? UIColor(red:0.70,green:0.50,blue:0.06,alpha:1) : UIColor(Paper.blue)
        for (index,path) in buckets.enumerated() {
            ctx.setFillColor(color.withAlphaComponent(0.20+Double(index)*0.095).cgColor)
            ctx.addPath(path); ctx.fillPath()
        }
    }
}
