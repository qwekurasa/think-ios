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
struct Studio: View {
    @AppStorage("think.book.v1") private var data = Data()
    @AppStorage("think.draft.text") private var draft = ""
    @AppStorage("think.draft.step") private var draftStep = ""
    @State private var book = Notebook()
    @State private var page = Page.spark
    @State private var showRewards = false
    @State private var editing: Idea?
    @State private var text = ""
    @State private var step = ""
    @StateObject private var voice = Dictation()
    @State private var editorOrigin = Page.spark
    @State private var search = ""
    @State private var dayFilter: Date?
    @State private var calendarDay = Date()
    @State private var calendarOpen = false
    @State private var detail: Idea?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStep = false
    @State private var storageError = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduced
    enum Field { case thought, step }
    let accent = Paper.blue
    var body: some View {
        ZStack {
            if page == .collection { archive.transition(.opacity) }
            else if page == .editor { editor.transition(.opacity.combined(with: .offset(y: reduced ? 0 : 12))) }
            else { capture.transition(.opacity) }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.32), value: page)
        .preferredColorScheme(.light)
        .fontDesign(.monospaced)
        .tint(Paper.blue)
        .onAppear {
            guard !data.isEmpty else { return }
            do { book = try JSONDecoder().decode(Notebook.self, from: data) }
            catch { storageError = true }
        }
        .alert("Не удалось прочитать коллекцию", isPresented: $storageError) {
            Button("Закрыть", role: .cancel) {}
        } message: { Text("Исходные записи сохранены на устройстве.") }
        .onChange(of: scenePhase) { _, phase in if phase == .background { voice.cancel() } }
        .alert("Голосовая запись", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) {
            Button("Закрыть") { voice.error = nil }
        } message: { Text(voice.error ?? "") }
        .sheet(isPresented: $showRewards) {
            rewards.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
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
        voice.cancel()
        text = idea?.text ?? draft
        step = idea?.step ?? draftStep
        showStep = !step.isEmpty
        page = .editor
    }
    private func save() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        voice.cancel()
        var next = book
        var idea = editing ?? Idea(id: UUID(), text: words, step: action, created: Date(), award: 0)
        let score = max(idea.award, 1 + (words.count >= 80 ? 1 : 0) + (action.isEmpty ? 0 : 1))
        next.balance += score - idea.award
        idea.text = words; idea.step = action; idea.award = score
        if let index = next.ideas.firstIndex(where: { $0.id == idea.id }) { next.ideas[index] = idea }
        else { next.ideas.insert(idea, at: 0) }
        guard persist(next) else { return }
        if editing == nil { draft = ""; draftStep = "" }
        focus = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if editing != nil { detail = idea } else { detail = nil; search = ""; dayFilter = nil }
        page = .collection
    }
    private var brand: some View {
        HStack(spacing: 6) {
            SparkShape().frame(width: 22, height: 22)
            Text("think").font(.system(size:30,weight:.semibold,design:.default)).fontDesign(.default).tracking(-2)
        }.accessibilityElement(children: .ignore).accessibilityLabel("think")
    }
    private var balance: some View {
        Button { showRewards = true } label: {
            HStack(spacing: 7) {
                SparkShape().frame(width: 13, height: 13)
                Text("\(book.balance)").monospacedDigit()
            }.padding(.horizontal, 14).frame(minHeight: 44)
             .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius:8))
        }.accessibilityLabel("Мои звёзды, \(book.balance)")
    }
    private var capture: some View {
        VStack(spacing: 0) {
            HStack { brand; Spacer(); balance }.padding(.horizontal, 24)
            Spacer(minLength: 8)
            Flower().frame(width:37,height:54)
            VStack(spacing: 12) {
                ParticleStar(cool: book.cool) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    begin()
                }.aspectRatio(1.12, contentMode: .fit)
                Button("Поймай мысль.") { begin() }
                    .font(.system(.title,design:.monospaced)).foregroundStyle(Paper.blue)
                Text("Крути шар пальцем. Коснись, чтобы записать.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
            Spacer(minLength: 20)
            Button { detail = nil; search = ""; dayFilter = nil; page = .collection } label: {
                Label("Идеи · \(book.ideas.count)", systemImage: "square.stack").font(.callout)
                    .padding(.horizontal, 20).frame(minHeight: 48).background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius:8))
            }.padding(.bottom, 12)
        }.buttonStyle(.plain).foregroundStyle(Paper.ink)
         .background(Paper.sheet.ignoresSafeArea())
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { voice.cancel(); focus = nil; page = editorOrigin } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Назад")
                Spacer()
                Text(editing == nil ? "Новая мысль" : "Редактирование").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                SparkShape().fill(accent).frame(width: 16, height: 16).padding(.horizontal, 14)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voice.listening ? "Слушаю…" : "О чём ты думаешь?").foregroundStyle(.secondary).padding(.top,8).padding(.leading,5).allowsHitTesting(false) }
                TextEditor(text:$text).scrollContentBackground(.hidden).focused($focus,equals:.thought)
                    .accessibilityLabel("Текст идеи")
            }.font(.system(.title2,design:.monospaced))
             .onChange(of:text) { _,value in if editing == nil { draft = value } }
             .onChange(of:focus) { _,field in if field != nil { voice.cancel() } }
            GlassMic(active:voice.listening,waiting:voice.waiting) {
                if voice.listening { voice.finish(); return }
                focus = nil
                let prefix = text
                Task {
                    await voice.start { words in
                        text = prefix.isEmpty || prefix.last?.isWhitespace == true ? prefix + words : prefix + " " + words
                        if editing == nil { draft = text }
                    }
                }
            }.frame(maxWidth:.infinity)
            if showStep && !voice.listening {
                TextField("Что можно сделать первым?", text: $step, axis: .vertical)
                    .lineLimit(1...3).focused($focus, equals: .step).padding(12)
                    .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: step) { _, value in if editing == nil { draftStep = value } }
            }
            HStack {
                if !showStep { Button("＋ Первый шаг") { showStep = true; focus = .step }.font(.subheadline) }
                Spacer()
                Button("Сохранить", action: save).font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 19).frame(minHeight: 46).background(accent, in: RoundedRectangle(cornerRadius:8))
                    .disabled(voice.waiting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(.horizontal, 22).padding(.bottom, 8).foregroundStyle(Paper.ink)
         .background(Paper.sheet.ignoresSafeArea())
    }
    private var journalDays: [(key: Date, value: [Idea])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = book.ideas.filter { idea in
            (dayFilter.map { Calendar.current.isDate($0,inSameDayAs:idea.created) } ?? true) && (query.isEmpty || [idea.text, idea.step, idea.audio == nil ? "" : "Голосовая запись"]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        return Dictionary(grouping: matches.sorted { $0.created > $1.created }) {
            Calendar.current.startOfDay(for: $0.created)
        }.sorted { $0.key > $1.key }
    }
    private var archive: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    voice.cancel()
                    if detail == nil { page = .spark } else { detail = nil }
                } label: {
                    Label(detail == nil ? "Главная" : "Все идеи", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                Spacer()
                balance
            }
            if let idea = detail {
                Text("Идея").font(.custom("Menlo-Bold",size:34,relativeTo:.largeTitle))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Дата создания").font(.caption).foregroundStyle(Paper.blue)
                        Text(idea.created, format: .dateTime.day().month(.wide).year().hour().minute()).font(.custom("Menlo-Regular",size:15,relativeTo:.subheadline))
                        Divider()
                        Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                            .font(.custom("Menlo-Regular",size:21,relativeTo:.title3)).textSelection(.enabled)
                        if !idea.step.isEmpty { Text("Первый шаг").font(.custom("Menlo-Regular",size:17,relativeTo:.headline)); Text(idea.step) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22)
                     .foregroundStyle(Paper.ink).background(Paper.card,in:RoundedRectangle(cornerRadius:8))
                }
                Button { begin(idea) } label: { Label("Редактировать",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(.white).background(Paper.blue,in:RoundedRectangle(cornerRadius:8))
            } else {
                HStack {
                    Text("Идеи").font(.custom("Menlo-Bold",size:34,relativeTo:.largeTitle))
                    Spacer()
                    Button {
                        calendarDay = dayFilter ?? Date()
                        calendarOpen = true
                    } label: { Label("Календарь",systemImage:"calendar").font(.footnote).frame(minHeight:44) }
                    .foregroundStyle(Paper.blue)
                }
                if let dayFilter {
                    Button { self.dayFilter = nil } label: {
                        HStack { Text(dayFilter,format:.dateTime.day().month(.wide).year()); Image(systemName:"xmark") }
                    }.foregroundStyle(Paper.blue).accessibilityHint("Показать все даты")
                }
                if !book.ideas.isEmpty {
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск по идеям",text:$search).submitLabel(.search)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Очистить поиск") }
                    }.padding(.horizontal,14).frame(minHeight:44).background(.black.opacity(0.055),in:RoundedRectangle(cornerRadius:8))
                }
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:12) {
                        let sections = journalDays
                        if sections.isEmpty {
                            Text(dayFilter != nil && search.isEmpty ? "В этот день идей пока нет." : book.ideas.isEmpty ? "Здесь появятся твои идеи. Начни с первой записи." : "По этому запросу записей нет.")
                                .foregroundStyle(.secondary).padding(.vertical,24)
                        }
                        ForEach(sections,id:\.key) { section in
                            Text(section.key,format:.dateTime.day().month(.wide).year()).font(.custom("Menlo-Regular",size:17,relativeTo:.headline)).padding(.top,8)
                            ForEach(section.value) { idea in
                                Button {
                                    detail = idea
                                } label: {
                                    HStack(spacing:12) {
                                        VStack(alignment:.leading,spacing:8) {
                                            HStack {
                                                Image(systemName:idea.audio == nil ? "text.alignleft" : "waveform")
                                                Text(idea.audio == nil ? "Текст" : "Голос")
                                                Text("·")
                                                Text(idea.created,style:.time)
                                            }.font(.custom("Menlo-Regular",size:12,relativeTo:.caption)).foregroundStyle(Color(white:0.32))
                                            Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                                                .font(.custom("Menlo-Regular",size:21,relativeTo:.title3)).lineLimit(3)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:"chevron.right").foregroundStyle(Paper.blue)
                                    }.multilineTextAlignment(.leading).padding(16).foregroundStyle(Paper.ink)
                                     .background(Paper.card,in:RoundedRectangle(cornerRadius:8))
                                }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                Button { begin() } label: { Label("Новая идея",systemImage:"plus").font(.custom("Menlo-Regular",size:17,relativeTo:.headline)).frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(.white).background(Paper.blue,in:RoundedRectangle(cornerRadius:8))
            }
        }.font(.custom("Menlo-Regular",size:17,relativeTo:.body)).buttonStyle(.plain).padding(.horizontal,22).padding(.bottom,8)
         .foregroundStyle(Paper.ink).background(Paper.sheet.ignoresSafeArea())
         .environment(\.locale,Locale(identifier:"ru"))
         .sheet(isPresented:$calendarOpen) {
             VStack(spacing:12) {
                 DatePicker("Выбрать дату",selection:$calendarDay,displayedComponents:.date)
                     .datePickerStyle(.graphical)
                 HStack {
                     Button("Все даты") { dayFilter = nil; calendarOpen = false }
                     Spacer()
                     Button("Показать идеи") { dayFilter = calendarDay; calendarOpen = false }
                         .buttonStyle(.borderedProminent)
                 }
             }.padding(20).tint(Paper.blue).fontDesign(.monospaced)
              .environment(\.locale,Locale(identifier:"ru")).presentationBackground(Paper.sheet)
              .presentationDetents([.height(470),.large]).presentationDragIndicator(.visible)
         }
    }
    private var rewards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Мои звёзды").font(.largeTitle.bold())
                HStack { SparkShape().fill(accent).frame(width: 36, height: 36); Text("\(book.balance)").font(.largeTitle.monospacedDigit()) }
                Text("Одна звезда за мысль, ещё одна за описание от 80 символов и одна за первый шаг. Дополняй запись позже — звёзды сохранятся.").foregroundStyle(.secondary)
                Divider()
                Label("Лунный жёлтый", systemImage: "moon.stars").font(.headline)
                Text("Тёплый жёлтый оттенок для частиц шара.").foregroundStyle(.secondary)
                Button(book.lunar ? (book.cool ? "Вернуть мягкий свет" : "Включить лунный жёлтый") : "Открыть за 5 звёзд") {
                    var next = book
                    if !next.lunar { guard next.balance >= 5 else { return }; next.balance -= 5; next.lunar = true }
                    next.cool.toggle(); _ = persist(next)
                }.buttonStyle(.borderedProminent).tint(Paper.blue).disabled(!book.lunar && book.balance < 5)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }.padding(.top, 15).fontDesign(.monospaced).presentationBackground(Paper.sheet)
    }
}

import AVFoundation
import Speech

@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var waiting = false
    @Published var error: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()

    func start(update: @escaping (String) -> Void) async {
        cancel()
        let token = generation
        waiting = true
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard token == generation else { return }
        guard microphone else { waiting = false; error = "Разреши доступ к микрофону в настройках iPhone."; return }
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard token == generation else { return }
        waiting = false
        guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier:"ru-RU")), recognizer.isAvailable else {
            error = "Диктовка недоступна. Проверь разрешение на распознавание речи или введи текст с клавиатуры."; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode:.measurement)
            try session.setActive(true)
            let input = AVAudioEngine()
            let format = input.inputNode.outputFormat(forBus:0)
            guard format.channelCount > 0, format.sampleRate > 0 else { throw CocoaError(.featureUnsupported) }
            let buffer = SFSpeechAudioBufferRecognitionRequest()
            buffer.shouldReportPartialResults = true
            buffer.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            input.inputNode.installTap(onBus:0,bufferSize:1024,format:format) { data,_ in buffer.append(data) }
            engine = input
            request = buffer
            try input.start()
            listening = true
            task = recognizer.recognitionTask(with:buffer) { [weak self] result, failure in
                let words = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let words, !words.isEmpty { update(words) }
                    if final || failure != nil {
                        if self.listening && failure != nil && words == nil { self.error = "Диктовка прервалась. Нажми микрофон, чтобы продолжить." }
                        self.cancel()
                    }
                }
            }
        } catch { cancel(); self.error = "Не удалось начать диктовку. Попробуй ещё раз." }
    }
    func finish() {
        guard listening else { return }
        listening = false
        closeInput()
        request?.endAudio()
    }
    private func closeInput() {
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus:0)
        self.engine = nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func cancel() {
        generation = UUID()
        waiting = false; listening = false
        closeInput()
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
    }
}

struct GlassMic: View {
    let active: Bool
    let waiting: Bool
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Image(systemName:"mic.fill")
                .font(.system(size:25,weight:.medium))
                .foregroundStyle(active ? Color.white : Paper.blue)
                .frame(width:66,height:66)
                .background {
                    Circle().fill(active ? Paper.blue : Paper.card)
                        .overlay { Circle().fill(.linearGradient(colors:[.white.opacity(0.35),.clear,.black.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing)) }
                        .overlay { Circle().strokeBorder(.linearGradient(colors:[.white,Paper.blue.opacity(0.32)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.2) }
                        .shadow(color:Paper.blue.opacity(active ? 0.28 : 0.12),radius:active ? 9 : 4,y:2)
                }.contentShape(Circle())
        }.buttonStyle(.plain).disabled(waiting)
         .accessibilityLabel(active ? "Остановить диктовку" : "Начать диктовку")
    }
}

