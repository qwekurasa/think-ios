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

import SwiftUI
import SpriteKit
import simd

struct ParticleStar: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    let cool: Bool
    let onTap: () -> Void
    @State private var scene = OrbScene(size: CGSize(width: 320, height: 320))

    var body: some View {
        SpriteView(scene: scene, isPaused: phase != .active, preferredFramesPerSecond: 60)
            .onAppear {
                scene.scaleMode = .resizeFill
                scene.configure(yellow: cool, reduced: reduced)
                scene.onTap = onTap
            }
            .onChange(of: cool) { _, value in scene.configure(yellow: value, reduced: reduced) }
            .onChange(of: reduced) { _, value in scene.configure(yellow: cool, reduced: value) }
            .accessibilityElement(children: .ignore).accessibilityLabel("Записать идею")
            .accessibilityAddTraits(.isButton).accessibilityAction { onTap() }
    }
}

final class OrbScene: SKScene {
    private struct Dot {
        let normal: SIMD3<Double>
        let phase: Double
        let sprite: SKSpriteNode
    }
    var onTap: (() -> Void)?
    private var dots: [Dot] = []
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
    private var reduced = false
    private var yellow = false

    override func didMove(to view: SKView) {
        backgroundColor = .black
        isUserInteractionEnabled = true
        guard dots.isEmpty else { return }
        let texture = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width:8,height:8)).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x:1,y:1,width:6,height:6))
        })
        for row in 1..<48 {
            let phi = Double(row) * .pi / 48
            let count = max(6, Int(96*sin(phi)))
            for column in 0..<count {
                let theta = 2*Double.pi*(Double(column)+Double(row%2)*0.5)/Double(count)
                let seed = Double((row*751 + column*317 + row*column*29)%997)/997
                let normal = SIMD3(sin(phi)*cos(theta),cos(phi),sin(phi)*sin(theta))
                let sprite = SKSpriteNode(texture:texture)
                sprite.colorBlendFactor = 1
                sprite.size = CGSize(width:1.1+seed,height:1.1+seed)
                addChild(sprite)
                dots.append(Dot(normal:normal,phase:seed*2*Double.pi,sprite:sprite))
            }
        }
        configure(yellow:yellow,reduced:reduced)
    }
    func configure(yellow: Bool, reduced: Bool) {
        self.yellow = yellow
        self.reduced = reduced
        let color = yellow ? UIColor(red:1,green:0.86,blue:0.48,alpha:1) : UIColor(white:0.93,alpha:1)
        for dot in dots { dot.sprite.color = color }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        previousTouch = touch.location(in:self)
        origin = previousTouch
        held = true; dragged = false
        lastInput = touch.timestamp
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard held, let touch = touches.first else { return }
        let point = touch.location(in:self)
        if !dragged && hypot(point.x-origin.x,point.y-origin.y) < 5 { return }
        dragged = true
        let sensitivity = 2.5/max(65,min(size.width,size.height)*0.345)
        let delta = SIMD2(Double(point.x-previousTouch.x),Double(point.y-previousTouch.y))*sensitivity
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
        if !dragged { onTap?() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        held = false; velocity = .zero
    }
    override func update(_ time: TimeInterval) {
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
        let matrix = simd_double3x3(orientation)
        let radius = min(size.width,size.height)*0.345
        let front = 1.5*cos(clock*0.83)
        for dot in dots {
            let v = matrix*dot.normal
            let blend = reduced ? 0 : min(1,max(0,(dot.normal.x-front)*1.8))
            let displacement = blend*blend*(3-2*blend)*0.09
            let x = v.x + displacement*cos(dot.phase+clock*1.6)
            let y = v.y + displacement*sin(dot.phase*2+clock*1.3)
            dot.sprite.position = CGPoint(x:size.width/2+radius*x,y:size.height/2+radius*y)
            dot.sprite.alpha = 0.22+0.68*(v.z+1)/2
        }
    }
}

