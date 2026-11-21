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
    @State private var editorOrigin = Page.spark
    @State private var search = ""
    @State private var transcriptPrefix = ""
    @State private var detail: Idea?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStep = false
    @State private var storageError = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduced
    enum Field { case thought, step }
    let accent = Color.white
    var body: some View {
        ZStack {
            if page == .collection { archive.transition(.opacity) }
            else if page == .editor { editor.transition(.opacity.combined(with: .offset(y: reduced ? 0 : 12))) }
            else { capture.transition(.opacity) }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.32), value: page)
        .preferredColorScheme(.dark)
        .tint(.white)
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
        editorOrigin = page
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
        guard !words.isEmpty || voice.clip != nil else { return }
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
        if editing != nil { detail = idea } else { detail = nil; search = "" }
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
            VStack(spacing: 12) {
                ParticleStar(cool: book.cool) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    begin()
                }.aspectRatio(1.12, contentMode: .fit)
                Button("Поймай мысль.") { begin() }
                    .font(.system(.largeTitle, design: .default, weight: .medium)).tracking(-1.6)
                Text("Крути шар пальцем. Коснись, чтобы записать.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
            Spacer(minLength: 20)
            Button { detail = nil; search = ""; page = .collection } label: {
                Label("Дневник · \(book.ideas.count)", systemImage: "square.stack").font(.callout)
                    .padding(.horizontal, 20).frame(minHeight: 48).background(.white.opacity(0.07), in: Capsule())
            }.padding(.bottom, 12)
        }.buttonStyle(.plain).foregroundStyle(.white)
         .background(Color.black.ignoresSafeArea())
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { voice.stop(); focus = nil; if let idea = detail { voice.load(idea.audio) }; page = editorOrigin } label: {
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
            if voiceMode && voice.recording {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text.isEmpty ? "Слушаю…" : text).font(.system(.largeTitle, weight: .medium)).tracking(-1.2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("end")
                        }
                    }.mask(LinearGradient(stops: [.init(color: .white.opacity(0.4), location: 0), .init(color: .white, location: 0.19), .init(color: .white, location: 0.97), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                     .onChange(of: text) { _, _ in withAnimation(reduced ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo("end",anchor: .bottom) } }
                }
            } else {
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voiceMode ? "Подпись к записи…" : "О чём ты думаешь?").foregroundStyle(.white.opacity(0.42)).padding(.top, 8).padding(.leading, 5) }
                TextEditor(text: $text).scrollContentBackground(.hidden).focused($focus, equals: .thought)
                    .accessibilityLabel("Текст идеи").onChange(of: text) { _, value in if editing == nil { draft = value } }
            }.font(.system(.title, design: .default, weight: .medium)).tracking(-0.8)
            }
            if voiceMode {
                RecorderPanel(voice: voice)
                    .onChange(of: voice.recording) { _, active in if active { transcriptPrefix = text } }
                    .onChange(of: voice.transcript) { _, words in
                        guard voice.recording, !words.isEmpty else { return }
                        text = [transcriptPrefix, words].filter { !$0.isEmpty }.joined(separator: " ")
                        if editing == nil { draft = text }
                    }
            }
            if showStep && !voice.recording {
                TextField("Что можно сделать первым?", text: $step, axis: .vertical)
                    .lineLimit(1...3).focused($focus, equals: .step).padding(12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: step) { _, value in if editing == nil { draftStep = value } }
            }
            if (text + "\n\n" + step).utf8.count > 1800 { Text("Эту запись можно отправить обычным текстом.").font(.footnote).foregroundStyle(accent) }
            HStack {
                if !showStep { Button("＋ Первый шаг") { showStep = true; focus = .step }.font(.subheadline) }
                Spacer()
                Button("Сохранить", action: save).font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 19).frame(minHeight: 46).background(accent, in: Capsule())
                    .disabled(voice.waiting || (voice.clip == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(.horizontal, 22).padding(.bottom, 8).foregroundStyle(.white)
         .background(Color(white: 0.045).ignoresSafeArea())
         .task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled && !voiceMode { focus = .thought } }
    }
    private var journalDays: [(key: Date, value: [Idea])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = book.ideas.filter { idea in
            query.isEmpty || [idea.text, idea.step, idea.audio == nil ? "" : "Голосовая запись"]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return Dictionary(grouping: matches.sorted { $0.created > $1.created }) {
            Calendar.current.startOfDay(for: $0.created)
        }.sorted { $0.key > $1.key }
    }
    private var archive: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    voice.stop()
                    if detail == nil { page = .spark } else { detail = nil }
                } label: {
                    Label(detail == nil ? "Главная" : "Все записи", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                Spacer()
                balance
            }
            if let idea = detail {
                Text("Запись").font(.system(.largeTitle, design: .serif))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(idea.created, format: .dateTime.day().month(.wide).year().hour().minute()).font(.subheadline)
                        Divider()
                        Text(idea.text.isEmpty ? "Голосовая мысль" : idea.text)
                            .font(.system(.title2, design: .serif)).textSelection(.enabled)
                        if !idea.step.isEmpty { Text("Первый шаг").font(.headline); Text(idea.step) }
                        if let clip = idea.audio {
                            Button { voice.play() } label: { Label(voice.playing ? "Остановить" : "Слушать запись", systemImage: voice.playing ? "stop.circle" : "play.circle") }
                            ShareLink(item: VoiceMemo.url(clip)) { Label("Отправить аудио", systemImage: "square.and.arrow.up") }
                        }
                        let payload = [idea.text,idea.step].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        if !payload.isEmpty {
                            ShareLink(item: payload) { Label("Поделиться текстом", systemImage: "square.and.arrow.up") }
                            if payload.utf8.count <= 1800 { Button { panel = .qr(idea) } label: { Label("Показать QR-код",systemImage:"qrcode") } }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22)
                     .foregroundStyle(.black).background(Color(white:0.95),in:RoundedRectangle(cornerRadius:18))
                }
                Button { begin(idea) } label: { Label("Редактировать",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(.black).background(.white,in:Capsule())
            } else {
                Text("Дневник").font(.system(.largeTitle, design:.serif))
                if !book.ideas.isEmpty {
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск по идеям",text:$search).submitLabel(.search)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Очистить поиск") }
                    }.padding(.horizontal,14).frame(minHeight:44).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:14))
                }
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:12) {
                        let sections = journalDays
                        if sections.isEmpty {
                            Text(book.ideas.isEmpty ? "Здесь появятся твои идеи. Начни с первой записи." : "По этому запросу записей нет.")
                                .foregroundStyle(.secondary).padding(.vertical,24)
                        }
                        ForEach(sections,id:\.key) { section in
                            Text(section.key,format:.dateTime.day().month(.wide).year()).font(.headline).padding(.top,8)
                            ForEach(section.value) { idea in
                                Button {
                                    voice.load(idea.audio); detail = idea
                                } label: {
                                    HStack(spacing:12) {
                                        VStack(alignment:.leading,spacing:8) {
                                            HStack {
                                                Image(systemName:idea.audio == nil ? "text.alignleft" : "waveform")
                                                Text(idea.audio == nil ? "Текст" : "Голос")
                                                Text("·")
                                                Text(idea.created,style:.time)
                                            }.font(.caption).foregroundStyle(Color(white:0.34))
                                            Text(idea.text.isEmpty ? "Голосовая мысль" : idea.text)
                                                .font(.system(.title3,design:.serif)).lineLimit(3)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:"chevron.right").foregroundStyle(Color(white:0.4))
                                    }.multilineTextAlignment(.leading).padding(16).foregroundStyle(.black)
                                     .background(Color(white:0.95),in:RoundedRectangle(cornerRadius:16))
                                }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                Button { begin() } label: { Label("Новая идея",systemImage:"plus").font(.headline).frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(.black).background(.white,in:Capsule())
            }
        }.buttonStyle(.plain).padding(.horizontal,22).padding(.bottom,8)
         .foregroundStyle(.white).background(Color.black.ignoresSafeArea())
         .environment(\.locale,Locale(identifier:"ru"))
    }
    private var rewards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Мои звёзды").font(.largeTitle.bold())
                HStack { SparkShape().fill(accent).frame(width: 36, height: 36); Text("\(book.balance)").font(.largeTitle.monospacedDigit()) }
                Text("Одна звезда за мысль, ещё одна за описание от 80 символов и одна за первый шаг. Дополняй запись позже — звёзды сохранятся.").foregroundStyle(.secondary)
                Divider()
                Label("Лунный свет", systemImage: "moon.stars").font(.headline)
                Text("Более яркие серебристые частицы шара.").foregroundStyle(.secondary)
                Button(book.lunar ? (book.cool ? "Вернуть мягкий свет" : "Включить лунный свет") : "Открыть за 5 звёзд") {
                    var next = book
                    if !next.lunar { guard next.balance >= 5 else { return }; next.balance -= 5; next.lunar = true }
                    next.cool.toggle(); _ = persist(next)
                }.buttonStyle(.borderedProminent).tint(Color(white:0.27)).disabled(!book.lunar && book.balance < 5)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }.padding(.top, 15)
    }
}

import AVFoundation
import Speech

@MainActor
final class VoiceMemo: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var recording = false
    @Published var playing = false
    @Published var waiting = false
    @Published var clip: String?
    @Published var seconds = 0.0
    @Published var levels = Array(repeating: 0.02, count: 42)
    @Published var error: String?
    @Published var transcript = ""
    private var engine: AVAudioEngine?
    private var speech: SFSpeechRecognitionTask?
    private var bufferRequest: SFSpeechAudioBufferRecognitionRequest?
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
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        var mayTranscribe = false
        if allowed, recognizer?.supportsOnDeviceRecognition == true {
            let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            mayTranscribe = status == .authorized
        }
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
            transcript = ""
            recording = true
            if mayTranscribe, let recognizer, recognizer.isAvailable {
                let input = AVAudioEngine()
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.requiresOnDeviceRecognition = true
                let format = input.inputNode.outputFormat(forBus: 0)
                if format.channelCount > 0 && format.sampleRate > 0 {
                    input.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
                    do {
                        try input.start()
                        engine = input; bufferRequest = request
                        speech = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                            guard let words = result?.bestTranscription.formattedString else { return }
                            Task { @MainActor in
                                guard let self, self.request == token, self.recording else { return }
                                self.transcript = words
                            }
                        }
                    } catch { input.inputNode.removeTap(onBus: 0) }
                }
            }
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
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil; bufferRequest?.endAudio(); bufferRequest = nil; speech?.cancel(); speech = nil
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
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(spacing: 12) {
            Text(voice.recording ? "Идёт запись" : voice.playing ? "Воспроизведение" : voice.clip == nil ? "Голосовая мысль" : "Голосовая запись")
                .font(.headline)
            Button {
                if voice.recording { voice.stop() }
                else if voice.clip != nil { voice.play() }
                else { Task { await voice.record() } }
            } label: {
                let strength = reduced ? 0.0 : (voice.recording ? min(1.0,(voice.levels.last ?? 0)*1.8) : 0.0)
                ZStack {
                    Circle().fill(RadialGradient(colors:[.white.opacity(0.6),.white.opacity(0.18),.clear],center:.center,startRadius:25,endRadius:58))
                        .scaleEffect(1 + 0.22*strength)
                    Circle().fill(.linearGradient(colors:[Color(white:0.18),Color(white:0.04)],startPoint:.topLeading,endPoint:.bottomTrailing))
                        .frame(width:68,height:68)
                        .overlay { Circle().stroke(.linearGradient(colors:[.white,.white.opacity(0.22),.white.opacity(0.8)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.5) }
                        .shadow(color:.white.opacity(0.42 + 0.3*strength),radius:5 + 9*strength)
                    Image(systemName: voice.recording || voice.playing ? "stop.fill" : voice.clip == nil ? "mic.fill" : "play.fill")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                }.frame(width:118,height:118).contentShape(Circle())
                 .animation(reduced ? nil : .easeOut(duration:0.12),value:strength)
            }.disabled(voice.waiting)
             .accessibilityLabel(voice.recording || voice.playing ? "Остановить" : voice.clip == nil ? "Начать запись" : "Прослушать")
            Text(voice.waiting ? "Ожидание доступа…" : voice.clip == nil ? "Нажми, чтобы записать" : String(format: "%d:%02d", Int(voice.seconds)/60, Int(voice.seconds)%60))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}
