import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

@main
struct ThinkApp: App {
    var body: some Scene { WindowGroup { Studio() } }
}

struct Idea: Codable, Identifiable {
    let id: UUID
    var text: String
    var step: String
    let created: Date
    var audio: String? = nil
    var award: Int
}

struct Notebook: Codable {
    var ideas: [Idea] = []
    var balance = 0
    var lunar = false
    var cool = false
}

enum Page { case spark, editor, collection }
enum Panel: Identifiable {
    case stars, qr(Idea)
    var id: String {
        switch self { case .stars: return "stars"; case .qr(let idea): return idea.id.uuidString }
    }
}

struct Studio: View {
    @AppStorage("think.book.v1") private var data = Data()
    @AppStorage("think.draft.text") private var draft = ""
    @AppStorage("think.draft.step") private var draftStep = ""
    @State private var book = Notebook()
    @State private var page = Page.spark
    @State private var panel: Panel?
    @State private var editing: Idea?
    @State private var text = ""
    @State private var step = ""
    @StateObject private var voice = VoiceMemo()
    @AppStorage("think.draft.audio") private var draftAudio = ""
    @State private var voiceMode = false
    @State private var detail: Idea?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStep = false
    @State private var storageError = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduced
    enum Field { case thought, step }
    let ink = Color(red: 0.058, green: 0.065, blue: 0.082)
    var accent: Color { book.cool ? Color(red: 0.65, green: 0.78, blue: 1) : Color(red: 1, green: 0.85, blue: 0.49) }
    var body: some View {
        ZStack {
            if page == .collection { archive.transition(.opacity) }
            else if page == .editor { editor.transition(.opacity.combined(with: .offset(y: reduced ? 0 : 12))) }
            else { capture.transition(.opacity) }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.32), value: page)
        .preferredColorScheme(page == .collection ? .light : .dark)
        .onAppear {
            guard !data.isEmpty else { return }
            do { book = try JSONDecoder().decode(Notebook.self, from: data) }
            catch { storageError = true }
        }
        .alert("Не удалось прочитать коллекцию", isPresented: $storageError) {
            Button("Закрыть", role: .cancel) {}
        } message: { Text("Исходные записи сохранены на устройстве.") }
        .onChange(of: voice.clip) { _, clip in
            if page == .editor && editing == nil { draftAudio = clip ?? "" }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { voice.stop() } }
        .alert("Голосовая запись", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) {
            Button("Закрыть") { voice.error = nil }
        } message: { Text(voice.error ?? "") }
        .sheet(item: $panel) { item in
            switch item {
            case .qr(let idea): QRSheet(idea: idea).presentationDragIndicator(.visible)
            case .stars: rewards.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
    }
    private func persist(_ next: Notebook) -> Bool {
        if !data.isEmpty, (try? JSONDecoder().decode(Notebook.self, from: data)) == nil { storageError = true; return false }
        guard let saved = try? JSONEncoder().encode(next) else { return false }
        data = saved
        book = next
        return true
    }
    private func begin(_ idea: Idea? = nil) {
        detail = nil
        editing = idea
        let clip = idea == nil ? (draftAudio.isEmpty ? nil : draftAudio) : idea?.audio
        voice.load(clip)
        voiceMode = clip != nil
        text = idea?.text ?? draft
        step = idea?.step ?? draftStep
        showStep = !step.isEmpty
        page = .editor
    }
    private func save() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!words.isEmpty || voice.clip != nil), (words + "\n\n" + action).utf8.count <= 1800 else { return }
        voice.stop()
        var next = book
        var idea = editing ?? Idea(id: UUID(), text: words, step: action, created: Date(), award: 0)
        let score = max(idea.award, 1 + (words.count >= 80 ? 1 : 0) + (action.isEmpty ? 0 : 1))
        next.balance += score - idea.award
        idea.audio = voice.clip; idea.text = words; idea.step = action; idea.award = score
        if let index = next.ideas.firstIndex(where: { $0.id == idea.id }) { next.ideas[index] = idea }
        else { next.ideas.insert(idea, at: 0) }
        guard persist(next) else { return }
        if editing == nil { draft = ""; draftStep = ""; draftAudio = "" }
        focus = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        page = .collection
    }
    private var brand: some View {
        HStack(spacing: 6) {
            SparkShape().frame(width: 22, height: 22)
            Text("think").font(.system(size: 30, weight: .semibold)).tracking(-2)
        }.accessibilityElement(children: .ignore).accessibilityLabel("think")
    }
    private var balance: some View {
        Button { panel = .stars } label: {
            HStack(spacing: 7) {
                SparkShape().frame(width: 13, height: 13)
                Text("\(book.balance)").monospacedDigit()
            }.padding(.horizontal, 14).frame(minHeight: 44)
             .background(.primary.opacity(0.07), in: Capsule())
        }.accessibilityLabel("Мои звёзды, \(book.balance)")
    }
    private var capture: some View {
        VStack(spacing: 0) {
            HStack { brand; Spacer(); balance }.padding(.horizontal, 24)
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                begin()
            } label: {
                VStack(spacing: 12) {
                    ParticleStar(cool: book.cool).aspectRatio(1.12, contentMode: .fit)
                    Text("Поймай мысль.").font(.system(.largeTitle, design: .default, weight: .medium)).tracking(-1.6)
                    Text("Коснись шара, чтобы записать идею.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.accessibilityLabel("Записать идею")
            Spacer(minLength: 20)
            Button { page = .collection } label: {
                Label("Дневник · \(book.ideas.count)", systemImage: "square.stack").font(.callout)
                    .padding(.horizontal, 20).frame(minHeight: 48).background(.white.opacity(0.07), in: Capsule())
            }.padding(.bottom, 12)
        }.buttonStyle(.plain).foregroundStyle(.white)
         .background(RadialGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.13), ink, .black], center: .center, startRadius: 10, endRadius: 550).ignoresSafeArea())
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { voice.stop(); focus = nil; page = editing == nil ? .spark : .collection } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Назад")
                Spacer()
                Text(editing == nil ? "Новая мысль" : "Редактирование").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                SparkShape().fill(accent).frame(width: 16, height: 16).padding(.horizontal, 14)
            }
            Picker("Способ записи", selection: $voiceMode) {
                Text("Текст").tag(false)
                Text("Голос").tag(true)
            }.pickerStyle(.segmented).disabled(voice.recording || voice.waiting)
             .onChange(of: voiceMode) { _, value in
                 if value { focus = nil } else { voice.stop(); focus = .thought }
             }
            if voiceMode { RecorderPanel(voice: voice, tint: accent) }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voiceMode ? "Подпись к записи…" : "О чём ты думаешь?").foregroundStyle(.white.opacity(0.42)).padding(.top, 8).padding(.leading, 5) }
                TextEditor(text: $text).scrollContentBackground(.hidden).focused($focus, equals: .thought)
                    .accessibilityLabel("Текст идеи").onChange(of: text) { _, value in if editing == nil { draft = value } }
            }.font(.system(.title, design: .default, weight: .medium)).tracking(-0.8)
            if showStep {
                TextField("Что можно сделать первым?", text: $step, axis: .vertical)
                    .lineLimit(1...3).focused($focus, equals: .step).padding(12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: step) { _, value in if editing == nil { draftStep = value } }
            }
            if (text + "\n\n" + step).utf8.count > 1800 { Text("Сократи текст, чтобы идея поместилась в QR-код.").font(.footnote).foregroundStyle(accent) }
            HStack {
                if !showStep { Button("＋ Первый шаг") { showStep = true; focus = .step }.font(.subheadline) }
                Spacer()
                Button("Сохранить", action: save).font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 19).frame(minHeight: 46).background(accent, in: Capsule())
                    .disabled(voice.waiting || (voice.clip == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (text + "\n\n" + step).utf8.count > 1800)
            }
        }.padding(.horizontal, 22).padding(.bottom, 8).foregroundStyle(.white)
         .background(ZStack { ink; RoundedRectangle(cornerRadius: 46).stroke(.indigo.opacity(0.55), lineWidth: 9).blur(radius: 14) }.ignoresSafeArea())
         .task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled && !voiceMode { focus = .thought } }
    }
    private var grouped: [Date: [Idea]] { Dictionary(grouping: book.ideas) { Calendar.current.startOfDay(for: $0.created) } }
    private var days: [Date] { grouped.keys.sorted(by: >) }
    private var archive: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Button { voice.stop(); detail = nil; page = .spark } label: { brand }.accessibilityLabel("Главная"); Spacer(); balance }
            if let idea = detail {
                Button { voice.stop(); detail = nil } label: { Label("Все записи", systemImage: "chevron.left") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(idea.created, format: .dateTime.day().month(.wide).year()).foregroundStyle(.secondary)
                        Text(idea.text.isEmpty ? "Голосовая мысль" : idea.text).font(.system(.title, design: .serif)).textSelection(.enabled)
                        if let name = idea.audio {
                            Button { voice.play() } label: { Label(voice.playing ? "Остановить" : "Слушать запись", systemImage: voice.playing ? "stop.circle" : "play.circle") }
                            ShareLink(item: VoiceMemo.url(name)) { Label("Отправить аудио", systemImage: "square.and.arrow.up") }
                        }
                        if !idea.step.isEmpty { Divider(); Text("Первый шаг").font(.caption); Text(idea.step) }
                        Divider()
                        Button("Редактировать") { begin(idea) }
                        if !idea.text.isEmpty || !idea.step.isEmpty { Button("QR-код с текстом") { panel = .qr(idea) } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                     .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
            } else {
                Text("Дневник").font(.system(.largeTitle, design: .serif, weight: .semibold))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if book.ideas.isEmpty { Text("Здесь появится твоя первая запись.").foregroundStyle(.secondary).padding(.vertical, 28) }
                        ForEach(days, id: \.self) { day in
                            HStack { Text(day, format: .dateTime.day().month(.wide).year()).font(.headline); Spacer(); Rectangle().fill(.secondary.opacity(0.25)).frame(height: 1) }
                            ForEach(grouped[day] ?? []) { idea in
                                Button { voice.load(idea.audio); detail = idea } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        VStack { Image(systemName: idea.audio == nil ? "text.alignleft" : "waveform"); Text(idea.created, style: .time).font(.caption2.monospacedDigit()) }.foregroundStyle(.secondary).frame(minWidth: 42)
                                        Text(idea.text.isEmpty ? "Голосовая мысль" : idea.text).font(.system(.title3, design: .serif)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }.multilineTextAlignment(.leading).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                    }
                }
            }
            Button { begin() } label: { Label("Новая идея", systemImage: "plus").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48).background(ink, in: Capsule()) }
        }.buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 8).foregroundStyle(ink)
        .background(Color(white: 0.965).ignoresSafeArea()).environment(\.locale, Locale(identifier: "ru"))
    }
    private var rewards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Мои звёзды").font(.largeTitle.bold())
                HStack { SparkShape().fill(accent).frame(width: 36, height: 36); Text("\(book.balance)").font(.largeTitle.monospacedDigit()) }
                Text("Одна звезда за мысль, ещё одна за описание от 80 символов и одна за первый шаг. Дополняй запись позже — звёзды сохранятся.").foregroundStyle(.secondary)
                Divider()
                Label("Лунный свет", systemImage: "moon.stars").font(.headline)
                Text("Холодное серебряное свечение звезды.").foregroundStyle(.secondary)
                Button(book.lunar ? (book.cool ? "Вернуть янтарный свет" : "Включить лунный свет") : "Открыть за 5 звёзд") {
                    var next = book
                    if !next.lunar { guard next.balance >= 5 else { return }; next.balance -= 5; next.lunar = true }
                    next.cool.toggle(); _ = persist(next)
                }.buttonStyle(.borderedProminent).tint(.indigo).disabled(!book.lunar && book.balance < 5)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }.padding(.top, 15)
    }
}

import AVFoundation

@MainActor
final class VoiceMemo: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var recording = false
    @Published var playing = false
    @Published var waiting = false
    @Published var clip: String?
    @Published var seconds = 0.0
    @Published var levels = Array(repeating: 0.02, count: 42)
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var request = UUID()
    static func url(_ name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "ThinkVoice", directoryHint: .isDirectory).appendingPathComponent(name)
    }
    func load(_ name: String?) {
        stop()
        clip = name
        seconds = name.flatMap { try? AVAudioPlayer(contentsOf: Self.url($0)).duration } ?? 0
    }
    func record() async {
        guard !waiting, !recording, clip == nil else { return }
        stop()
        waiting = true
        let token = request
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard token == request else { return }
        waiting = false
        guard allowed else { error = "Разреши доступ к микрофону в настройках iPhone. Текст по-прежнему можно набрать."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let name = UUID().uuidString + ".m4a"
            let file = Self.url(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let new = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            new.delegate = self
            new.isMeteringEnabled = true
            guard new.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = new
            clip = name
            seconds = 0
            levels = Array(repeating: 0.02, count: 42)
            recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.meter() }
            }
        } catch { stop(); self.error = "Не удалось начать запись. Проверь микрофон и попробуй ещё раз." }
    }
    private func meter() {
        guard let recorder else { return }
        recorder.updateMeters()
        seconds = recorder.currentTime
        levels.removeFirst()
        levels.append(max(0.02, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 32))))
    }
    func stop() {
        request = UUID(); waiting = false
        timer?.invalidate(); timer = nil
        if let recorder { seconds = recorder.currentTime; recorder.delegate = nil; recorder.stop() }
        recorder = nil; recording = false
        player?.delegate = nil; player?.stop(); player = nil; playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func play() {
        if playing { stop(); return }
        guard let clip, !recording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            let new = try AVAudioPlayer(contentsOf: Self.url(clip))
            new.delegate = self
            guard new.play() else { throw CocoaError(.fileReadUnknown) }
            player = new; playing = true
        } catch { stop(); self.error = "Не удалось воспроизвести аудио." }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.stop() } }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.stop()
            if !flag { self.error = "Запись была прервана. Проверь её перед сохранением." }
        }
    }
}

struct RecorderPanel: View {
    @ObservedObject var voice: VoiceMemo
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(spacing: 12) {
            Text(voice.recording ? "Идёт запись" : voice.playing ? "Воспроизведение" : voice.clip == nil ? "Голосовая мысль" : "Голосовая запись")
                .font(.headline)
            if voice.recording && !reduced {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(voice.levels.indices, id: \.self) { n in
                            Capsule().fill(tint.opacity(0.45 + 0.55 * Double(n) / 42))
                                .frame(width: max(1,(geo.size.width-82)/42), height: 3 + 42 * voice.levels[n])
                        }
                    }.frame(height: geo.size.height)
                }.frame(height: 46).accessibilityHidden(true)
            }
            Button {
                if voice.recording { voice.stop() }
                else if voice.clip != nil { voice.play() }
                else { Task { await voice.record() } }
            } label: {
                Image(systemName: voice.recording || voice.playing ? "stop.fill" : voice.clip == nil ? "mic.fill" : "play.fill")
                    .font(.title2).foregroundStyle(.black).frame(width: 64,height: 64)
                    .background(tint, in: Circle())
                    .shadow(color: tint.opacity(voice.recording ? 0.42 : 0.10), radius: voice.recording && !reduced ? 8 + 28 * (voice.levels.last ?? 0) : 6)
            }.disabled(voice.waiting)
             .accessibilityLabel(voice.recording || voice.playing ? "Остановить" : voice.clip == nil ? "Начать запись" : "Прослушать")
            Text(voice.waiting ? "Ожидание доступа…" : voice.clip == nil ? "Нажми, чтобы записать" : String(format: "%d:%02d", Int(voice.seconds)/60, Int(voice.seconds)%60))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
    }
}
