import SwiftUI
import Speech
import AVFoundation
import Combine

@MainActor
final class ThinkSpeechService: ObservableObject {
    @Published var transcript = ""
    @Published var level: CGFloat = 0
    @Published var listening = false
    @Published var message: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru_RU"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() async {
        guard !listening else { return }
        message = nil
        let auth = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
        guard auth == .authorized else {
            message = "Разреши распознавание речи в Настройках iPhone."
            return
        }
        let microphone = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard microphone else {
            message = "Разреши доступ к микрофону в Настройках iPhone."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            message = "Распознавание речи сейчас недоступно. Можно записать идею текстом."
            return
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                message = "Не удалось получить звук с микрофона."
                return
            }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                if let samples = buffer.floatChannelData?[0] {
                    let count = Int(buffer.frameLength)
                    if count > 0 {
                        var energy: Float = 0
                        let step = max(1, count / 96)
                        var used = 0
                        for i in stride(from: 0, to: count, by: step) {
                            energy += samples[i] * samples[i]
                            used += 1
                        }
                        let rms = sqrt(energy / Float(max(1, used)))
                        let amplitude = CGFloat(min(1, rms * 17))
                        Task { @MainActor [weak self] in
                            self?.level = amplitude
                        }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            listening = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if let error, self.listening {
                        self.message = error.localizedDescription
                        self.stop()
                    }
                }
            }
        } catch {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            message = "Не удалось запустить микрофон: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard listening else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.finish()
        request = nil
        listening = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct ThinkWaveform: View {
    var level: CGFloat
    var active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let count = 37
                let step = size.width / CGFloat(count)
                for index in 0..<count {
                    let n = Double(index)
                    let wave = abs(sin(n * 0.71) * cos(n * 0.17 + time * (active ? 4.8 : 0.35)))
                    let height = CGFloat(4 + 22 * wave * Double(active ? max(level, 0.18) : 0.10))
                    let x = CGFloat(index) * step + step * 0.5
                    var stroke = Path()
                    stroke.move(to: CGPoint(x: x + CGFloat(0.4 * sin(time + n)), y: size.height * 0.5 - height * 0.5))
                    stroke.addLine(to: CGPoint(x: x, y: size.height * 0.5 + height * 0.5))
                    context.stroke(stroke, with: .color(Theme.ink.opacity(0.74)),
                                   style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    context.stroke(stroke, with: .color(Theme.muted.opacity(0.25)),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
        }
        .frame(height: 41)
        .accessibilityHidden(true)
    }
}

struct ThinkMicrophone: View {
    var level: CGFloat
    var listening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false) { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let diameter = min(size.width, size.height)
                let radius = diameter * 0.386
                let breathe = listening ? CGFloat(1 + sin(time * 1.7) * 0.017 + Double(level) * 0.026) : 1

                // A single, deliberately broken, hand-inked button contour.
                var border = Path()
                let count = 108
                for i in 0...count {
                    let angle = -2.55 + Double(i) / Double(count) * (2 * Double.pi - 0.22)
                    let uneven = 1 + 0.012 * sin(angle * 5 + 0.7)
                                   + 0.007 * sin(angle * 13 + time * 0.18)
                    let r = Double(radius * breathe) * uneven
                    let p = CGPoint(x: center.x + CGFloat(cos(angle) * r),
                                    y: center.y + CGFloat(sin(angle) * r))
                    if i == 0 { border.move(to: p) } else { border.addLine(to: p) }
                }
                context.stroke(border, with: .color(Theme.ink.opacity(listening ? 0.79 : 0.43)),
                               style: StrokeStyle(lineWidth: 1.35, lineCap: .round))

                // Microphone capsule, stem and U-shaped suspension in one ink line.
                let unit = radius
                var mic = Path()
                mic.move(to: CGPoint(x: center.x - unit * 0.15, y: center.y - unit * 0.43))
                mic.addQuadCurve(to: CGPoint(x: center.x + unit * 0.15, y: center.y - unit * 0.43),
                                 control: CGPoint(x: center.x, y: center.y - unit * 0.60))
                mic.addLine(to: CGPoint(x: center.x + unit * 0.15, y: center.y + unit * 0.06))
                mic.addQuadCurve(to: CGPoint(x: center.x - unit * 0.15, y: center.y + unit * 0.06),
                                 control: CGPoint(x: center.x, y: center.y + unit * 0.22))
                mic.closeSubpath()
                mic.move(to: CGPoint(x: center.x - unit * 0.30, y: center.y - unit * 0.03))
                mic.addCurve(to: CGPoint(x: center.x + unit * 0.30, y: center.y - unit * 0.02),
                             control1: CGPoint(x: center.x - unit * 0.32, y: center.y + unit * 0.53),
                             control2: CGPoint(x: center.x + unit * 0.34, y: center.y + unit * 0.49))
                mic.move(to: CGPoint(x: center.x + unit * 0.01, y: center.y + unit * 0.39))
                mic.addLine(to: CGPoint(x: center.x, y: center.y + unit * 0.59))
                mic.move(to: CGPoint(x: center.x - unit * 0.17, y: center.y + unit * 0.60))
                mic.addQuadCurve(to: CGPoint(x: center.x + unit * 0.19, y: center.y + unit * 0.60),
                                 control: CGPoint(x: center.x, y: center.y + unit * 0.57))
                context.stroke(mic, with: .color(Theme.ink),
                               style: StrokeStyle(lineWidth: 2.05, lineCap: .round, lineJoin: .round))

                if listening {
                    // Small reactive ink lines, not an animated rectangular frame.
                    for side in [-1.0, 1.0] {
                        let x = center.x + CGFloat(side) * unit * 0.54
                        let swing = CGFloat(0.02 + Double(level) * 0.06 + 0.012 * sin(time * 2.5))
                        var wave = Path()
                        wave.move(to: CGPoint(x: x, y: center.y - unit * (0.13 + swing)))
                        wave.addQuadCurve(to: CGPoint(x: x, y: center.y + unit * (0.15 + swing)),
                                          control: CGPoint(x: x + CGFloat(side) * unit * 0.11,
                                                           y: center.y))
                        context.stroke(wave, with: .color(Theme.muted.opacity(0.66)),
                                       style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
                    }
                } else {
                    // Clearly struck-through mic while paused or permission is off.
                    let from = CGPoint(x: center.x - unit * 0.43, y: center.y - unit * 0.54)
                    let to = CGPoint(x: center.x + unit * 0.47, y: center.y + unit * 0.55)
                    var slash = Path()
                    slash.move(to: from)
                    slash.addQuadCurve(to: to, control: CGPoint(x: center.x + unit * 0.06,
                                                                 y: center.y - unit * 0.02))
                    context.stroke(slash, with: .color(.white),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    context.stroke(slash, with: .color(Theme.ink),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
        }
        .frame(width: 174, height: 174)
        .accessibilityLabel(listening ? "Приостановить запись" : "Продолжить запись")
    }
}

struct ThinkOrb: View {
    var active = true
    var body: some View {
        ThinkLivingOrb()
            .scaleEffect(active ? 1 : 0.98)
    }
}

struct ReactiveEdgeGlow: View {
    let level: CGFloat
    let listening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let breath = (sin(time * 1.6) + 1) * 0.5
            GeometryReader { geometry in
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 7, dy: 8)
                    for pass in 0..<3 {
                        let path = handFrame(in: rect, time: time, seed: Double(pass) * 2.4)
                        let alpha = listening ? 0.25 + breath * 0.24 + Double(level) * 0.16 : 0.09
                        context.stroke(path, with: .color(Theme.ink.opacity(alpha / Double(pass + 1))),
                                       style: StrokeStyle(lineWidth: pass == 0 ? 1.4 : 0.75,
                                                          lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func handFrame(in rect: CGRect, time: Double, seed: Double) -> Path {
        var path = Path()
        let pointsPerEdge = 28
        for edge in 0..<4 {
            for step in 0...pointsPerEdge {
                let u = CGFloat(step) / CGFloat(pointsPerEdge)
                var point: CGPoint
                switch edge {
                case 0: point = CGPoint(x: rect.minX + rect.width * u, y: rect.minY)
                case 1: point = CGPoint(x: rect.maxX, y: rect.minY + rect.height * u)
                case 2: point = CGPoint(x: rect.maxX - rect.width * u, y: rect.maxY)
                default: point = CGPoint(x: rect.minX, y: rect.maxY - rect.height * u)
                }
                let wobble = CGFloat(1.15 * sin(Double(step) * 1.3 + seed + time * 0.22))
                if edge.isMultiple(of: 2) { point.y += wobble } else { point.x += wobble }
                if edge == 0 && step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }
}

struct PremiumVoiceScreen: View {
    @EnvironmentObject private var store: IdeaStore
    @StateObject private var speech = ThinkSpeechService()
    let initialText: String
    let onSwitchToText: (String) -> Void
    let onFinished: () -> Void
    let onCancel: () -> Void
    @State private var committed = false

    private var fullText: String {
        let typed = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return [typed, spoken].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { speech.stop(); onCancel() } label: {
                        SketchGlyph(name: "xmark", size: 19)
                            .font(.custom("Noteworthy-Light", size: 17))
                            .frame(width: 42, height: 42)
                    }
                    Spacer()
                    Text("ГОЛОСОВАЯ ИДЕЯ")
                        .font(.custom("Noteworthy-Bold", size: 10))
                        .tracking(2.1)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Color.clear.frame(width: 42, height: 42)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 19)
                .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(fullText.isEmpty
                             ? "Расскажи идею.\nЯ сохраню\nкаждую мысль."
                             : fullText)
                            .font(.custom("Noteworthy-Light", size: 31))
                            .tracking(-0.8)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.24), value: fullText)
                            .padding(.top, 58)
                        if let message = speech.message {
                            Text(message)
                                .font(.custom("Noteworthy-Light", size: 14))
                                .foregroundStyle(Theme.purple)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 29)
                }.scrollIndicators(.hidden)

                Text(speech.listening ? "СЛУШАЮ..." : "ЗАПИСЬ НА ПАУЗЕ")
                    .tracking(2.5)
                    .font(.custom("Noteworthy-Light", size: 10))
                    .foregroundStyle(Theme.muted)
                Button {
                    if speech.listening {
                        speech.stop()
                    } else {
                        Task { await speech.start() }
                    }
                } label: {
                    ThinkMicrophone(level: speech.level, listening: speech.listening)
                }.buttonStyle(.plain).frame(height: 173)

                if !fullText.isEmpty {
                    Button {
                        guard !committed else { return }
                        committed = true
                        speech.stop()
                        store.save(fullText, existing: nil)
                        onFinished()
                    } label: {
                        Text("Сохранить мысль")
                            .font(.custom("Noteworthy-Light", size: 15))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 11, seed: 5))
                    }
                    .disabled(committed)
                    .padding(.horizontal, 29)
                }

                Button {
                    speech.stop()
                    onSwitchToText(fullText)
                } label: {
                    SketchLabel("Перейти к тексту", symbol: "keyboard")
                        .font(.custom("Noteworthy-Light", size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 16)
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear { Task { await speech.start() } }
        .onChange(of: speech.transcript) { _, _ in
            if !committed {
                UserDefaults.standard.set(fullText, forKey: "think-active-draft-v2")
            }
        }
        .onDisappear { speech.stop() }
    }
}
