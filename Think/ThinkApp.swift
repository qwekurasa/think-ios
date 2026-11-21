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
    var flower: Bool? = nil
    var award: Int
}

struct Notebook: Codable {
    var ideas: [Idea] = []
    var balance = 0
    var lunar = false
    var cool = false
}

enum Page { case spark, editor, collection, settings }
struct Studio: View {
    @AppStorage("think.book.v1") private var data = Data()
    @AppStorage("think.draft.text") private var draft = ""
    @AppStorage("think.draft.step") private var draftStep = ""
    @State private var book = Notebook()
    @AppStorage("think.journal.v1") private var coverData = Data()
    @State private var cover: JournalCover?
    @State private var editingCover = false
    @State private var page = Page.spark
    @State private var showRewards = false
    @State private var editing: Idea?
    @State private var text = ""
    @State private var flower = false
    @AppStorage("think.draft.flower") private var draftFlower = false
    @AppStorage("think.dark") private var darkTheme = false
    @State private var listRequest = 0
    @State private var dismissRequest = 0
    @StateObject private var voice = Dictation()
    @State private var editorOrigin = Page.spark
    @State private var search = ""
    @State private var dayFilter: Date?
    @State private var calendarDay = Date()
    @State private var calendarOpen = false
    @State private var detail: Idea?
    @Environment(\.scenePhase) private var scenePhase
    @State private var storageError = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    let accent = Paper.blue
    var body: some View {
        ZStack {
            if cover == nil || editingCover {
                JournalSetup(existing:cover,onCancel:{ editingCover = false }) { newCover in
                    guard let encoded = try? JSONEncoder().encode(newCover) else { return }
                    coverData = encoded
                    cover = newCover
                    editingCover = false
                }.transition(.opacity)
            } else if page == .collection { archive.transition(.opacity) }
            else if page == .editor { editor.transition(.opacity.combined(with: .offset(y: reduced ? 0 : 12))) }
            else if page == .settings { settings.transition(.opacity) }
            else { capture.transition(.opacity) }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.32), value: page)
        .animation(reduced ? nil : .easeInOut(duration:0.35),value:cover != nil && !editingCover)
        .preferredColorScheme(cover == nil || editingCover || page == .spark || darkTheme ? .dark : .light)
        .safeAreaInset(edge:.bottom,spacing:0) {
            if cover != nil && !editingCover && page != .editor { menu }
        }
        .buttonStyle(.plain)
        .tint(Paper.blue)
        .onAppear {
            cover = try? JSONDecoder().decode(JournalCover.self,from:coverData)
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
        let legacy = idea?.step ?? draftStep
        if !legacy.isEmpty { text = [text,legacy].filter { !$0.isEmpty }.joined(separator:"\n\n") }
        if idea == nil { draft = text; draftStep = "" }
        flower = idea?.flower ?? (idea == nil && draftFlower)
        page = .editor
    }
    private func save() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        voice.cancel()
        var next = book
        var idea = editing ?? Idea(id: UUID(), text: words, step: "", created: Date(), award: 0)
        let score = max(idea.award, 1 + (words.count >= 80 ? 1 : 0) + (words.count >= 200 ? 1 : 0))
        next.balance += score - idea.award
        idea.text = words; idea.flower = flower; idea.step = ""; idea.award = score
        if let index = next.ideas.firstIndex(where: { $0.id == idea.id }) { next.ideas[index] = idea }
        else { next.ideas.insert(idea, at: 0) }
        guard persist(next) else { return }
        if editing == nil { draft = ""; draftStep = ""; draftFlower = false }
        dismissRequest += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if editing != nil { detail = idea } else { detail = nil; search = ""; dayFilter = nil }
        page = .collection
    }
    private var capture: some View {
        VStack(spacing:0) {
            HStack(spacing:9) {
                SparkShape().fill(.white).frame(width:17,height:17)
                Text("thinkinbrain").font(.system(size:15,weight:.semibold)).tracking(0.15)
            }.foregroundStyle(.white).frame(height:52)
            Spacer(minLength:4)
            ParticleStar(cool:book.cool) {
                UIImpactFeedbackGenerator(style:.soft).impactOccurred()
                begin()
            }.aspectRatio(1.12,contentMode:.fit)
            Text("запиши идею пока не забыл")
                .font(.subheadline).foregroundStyle(Color(white:0.62)).padding(.horizontal,20)
                .multilineTextAlignment(.center)
            Spacer(minLength:12)
        }.frame(maxWidth:.infinity)
         .background(Color.black.ignoresSafeArea())
    }

    private var menu: some View {
        HStack(spacing:4) {
            tab(.spark, "Главная", "circle.dotted")
            tab(.collection, "Мои идеи", "books.vertical")
            tab(.settings, "Настройки", "slider.horizontal.3")
        }.padding(.horizontal,16).padding(.top,8).padding(.bottom,4)
         .background((page == .spark ? Color.black : Paper.sheet).ignoresSafeArea(edges:.bottom))
         .overlay(alignment:.top) { Rectangle().fill(.primary.opacity(0.09)).frame(height:1) }
    }

    private func tab(_ tab: Page, _ title: String, _ icon: String) -> some View {
        Button {
            if tab != page { detail = nil; page = tab }
        } label: {
            VStack(spacing:4) {
                Image(systemName:icon).font(.system(size:19,weight:page == tab ? .semibold : .regular))
                Text(title).font(.caption2.weight(page == tab ? .semibold : .regular)).lineLimit(1)
            }.foregroundStyle(page == tab ? (page == .spark ? .white : Paper.ink) : .secondary)
             .frame(maxWidth:.infinity,minHeight:49).contentShape(Rectangle())
        }.accessibilityAddTraits(page == tab ? .isSelected : [])
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("Настройки").font(.largeTitle.bold())
                if let cover {
                    Button { editingCover = true } label: {
                        HStack(spacing:16) {
                            NotebookObject(cover:cover).scaleEffect(0.24)
                                .frame(width:58,height:74).allowsHitTesting(false).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:5) {
                                Text(cover.title).font(.headline).lineLimit(2)
                                Text("Название и обложка").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(15).background(Paper.card,in:RoundedRectangle(cornerRadius:20))
                    }
                }
                VStack(spacing:0) {
                    Toggle(isOn:$darkTheme) { Label("Тёмное оформление",systemImage:"moon") }.padding(17)
                    Divider().padding(.horizontal,17)
                    Button { showRewards = true } label: {
                        HStack {
                            Label("Звёзды",systemImage:"sparkle")
                            Spacer()
                            Text("\(book.balance)").monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(17)
                    }
                }.background(Paper.card,in:RoundedRectangle(cornerRadius:20))
            }.padding(22)
        }.foregroundStyle(Paper.ink).background(Paper.sheet.ignoresSafeArea())
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { voice.cancel(); dismissRequest += 1; page = editorOrigin } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Назад")
                Spacer()
                Text(editing == nil ? "Новая мысль" : "Редактирование").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Готово",action:save).font(.subheadline.weight(.semibold)).padding(.vertical,3)
                    .frame(minHeight:44).foregroundStyle(Paper.blue)
                    .disabled(voice.waiting || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if flower { Flower().frame(width:42,height:58).frame(maxWidth:.infinity) }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voice.listening ? "Слушаю…" : "О чём ты думаешь?").foregroundStyle(.secondary).padding(.top,8).padding(.leading,5).allowsHitTesting(false) }
                IdeaTextView(text:$text,listRequest:listRequest,dismissRequest:dismissRequest) { voice.cancel() }
            }.font(.system(.title2))
             .onChange(of:text) { _,value in if editing == nil { draft = value } }
            HStack(spacing:12) {
                Button { voice.cancel(); listRequest += 1 } label: {
                    Image(systemName:"list.number").frame(width:40,height:44)
                }.accessibilityLabel("Нумерованный список")
                Button {
                    flower.toggle()
                    if editing == nil { draftFlower = flower }
                } label: { Flower().frame(width:22,height:32).frame(width:40,height:44).opacity(flower ? 1 : 0.65) }
                .accessibilityLabel(flower ? "Убрать цветок" : "Добавить цветок")
                Spacer()
            GlassMic(active:voice.listening,waiting:voice.waiting) {
                if voice.listening { voice.finish(); return }
                dismissRequest += 1
                let prefix = text
                Task {
                    await voice.start { words in
                        text = prefix.isEmpty || prefix.last?.isWhitespace == true ? prefix + words : prefix + " " + words
                        if editing == nil { draft = text }
                    }
                }
            }
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
            if detail != nil {
                Button { detail = nil } label: {
                    Label("Все идеи",systemImage:"chevron.left").frame(minHeight:44)
                }.foregroundStyle(.secondary)
            }
            if let idea = detail {
                Text("Идея").font(.largeTitle.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if idea.flower == true { Flower().frame(width:42,height:58).frame(maxWidth:.infinity) }
                        Text("Дата создания").font(.caption).foregroundStyle(Paper.blue)
                        Text(idea.created, format: .dateTime.day().month(.wide).year().hour().minute()).font(.subheadline)
                        Divider()
                        Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                            .font(.system(.title3,design:.serif)).textSelection(.enabled)
                        if !idea.step.isEmpty { Text(idea.step) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22)
                     .foregroundStyle(Paper.ink).background(Paper.card,in:RoundedRectangle(cornerRadius:8))
                }
                Button { begin(idea) } label: { Label("Редактировать",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(Paper.blue)
            } else {
                HStack {
                    Text("Мои идеи").font(.largeTitle.bold())
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
                            Text(section.key,format:.dateTime.day().month(.wide).year()).font(.subheadline.weight(.semibold)).padding(.top,8)
                            ForEach(section.value) { idea in
                                Button {
                                    detail = idea
                                } label: {
                                    HStack(spacing:12) {
                                        VStack(alignment:.leading,spacing:8) {
                                            HStack {
                                                if idea.flower == true { Flower().frame(width:13,height:19) }
                                                Image(systemName:idea.audio == nil ? "text.alignleft" : "waveform")
                                                Text(idea.audio == nil ? "Текст" : "Голос")
                                                Text("·")
                                                Text(idea.created,style:.time)
                                            }.font(.caption).foregroundStyle(Paper.ink.opacity(0.7))
                                            Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                                                .font(.system(.title3,design:.serif)).lineLimit(3)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:"chevron.right").foregroundStyle(Paper.blue)
                                    }.multilineTextAlignment(.leading).padding(16).foregroundStyle(Paper.ink)
                                     .background(Paper.card,in:RoundedRectangle(cornerRadius:17))
                                     .overlay { RoundedRectangle(cornerRadius:17).strokeBorder(Paper.ink.opacity(0.06)).allowsHitTesting(false) }
                                }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                Button { begin() } label: { Label("Новая идея",systemImage:"plus").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:48) }
                    .buttonStyle(JournalPrimary())
            }
        }.buttonStyle(.plain).padding(.horizontal,22).padding(.bottom,8)
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
                         .buttonStyle(InkButton())
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
                Text("Одна звезда за мысль, ещё одна за описание от 80 символов и одна за текст от 200 символов. Дополняй запись позже — звёзды сохранятся.").foregroundStyle(.secondary)
                Divider()
                Label("Лунный жёлтый", systemImage: "moon.stars").font(.headline)
                Text("Тёплый жёлтый оттенок для частиц шара.").foregroundStyle(.secondary)
                Button(book.lunar ? (book.cool ? "Вернуть мягкий свет" : "Включить лунный жёлтый") : "Открыть за 5 звёзд") {
                    var next = book
                    if !next.lunar { guard next.balance >= 5 else { return }; next.balance -= 5; next.lunar = true }
                    next.cool.toggle(); _ = persist(next)
                }.buttonStyle(InkButton()).tint(Paper.blue).disabled(!book.lunar && book.balance < 5)
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
    private var phrases = SpeechPhrases()

    func start(update: @escaping (String) -> Void) async {
        cancel()
        phrases = SpeechPhrases()
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
                let segments = result?.bestTranscription.segments ?? []
                let from = segments.first?.timestamp ?? 0
                let until = segments.last.map { $0.timestamp+$0.duration } ?? from
                let final = result?.isFinal == true
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let words, !words.isEmpty {
                        update(self.phrases.receive(words,start:from,end:until,at:ProcessInfo.processInfo.systemUptime))
                    }
                    if final || failure != nil {
                        if self.listening && failure != nil && words == nil { self.error = "Диктовка прервалась. Нажми микрофон, чтобы продолжить." }
                        if final && self.listening && failure == nil {
                            let committed = self.phrases.value
                            await self.start { next in update([committed,next].filter { !$0.isEmpty }.joined(separator:" ")) }
                        } else { self.cancel() }
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
                .foregroundStyle(active ? Paper.blue : Paper.ink)
                .frame(width:60,height:60)
                .overlay { Circle().strokeBorder(active ? Paper.blue : Paper.ink.opacity(0.45),lineWidth:active ? 2 : 1) }
                .contentShape(Circle())
        }.buttonStyle(.plain).disabled(waiting)
         .accessibilityLabel(active ? "Остановить диктовку" : "Начать диктовку")
    }
}


import SwiftUI
import UIKit

struct IdeaTextView: UIViewRepresentable {
    @Binding var text: String
    let listRequest: Int
    let dismissRequest: Int
    let beginTyping: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.backgroundColor = .clear
        v.delegate = context.coordinator
        v.adjustsFontForContentSizeCategory = true
        v.font = UIFontMetrics(forTextStyle:.title2).scaledFont(for:UIFont.systemFont(ofSize:21))
        v.textContainerInset = UIEdgeInsets(top:8,left:0,bottom:8,right:0)
        v.accessibilityLabel = "Текст идеи"
        v.text = text
        return v
    }
    func updateUIView(_ v: UITextView,context:Context) {
        let c = context.coordinator
        c.parent = self
        v.textColor = UIColor(Paper.ink)
        v.tintColor = UIColor(Paper.blue)
        if v.text != text { v.text = text }
        if c.dismissID != dismissRequest {
            c.dismissID = dismissRequest; v.resignFirstResponder()
        }
        if c.listID != listRequest {
            c.listID = listRequest
            DispatchQueue.main.async {
                v.becomeFirstResponder()
                let str = v.text as NSString
                let line = str.lineRange(for:NSRange(location:v.selectedRange.location,length:0))
                let start = NSRange(location:line.location,length:0)
                if str.substring(with:line).range(of:"^[0-9]+\\. ",options:.regularExpression) == nil {
                    let selection = v.selectedRange
                    v.textStorage.replaceCharacters(in:start,with:"1. ")
                    v.selectedRange = NSRange(location:selection.location+3,length:selection.length)
                    c.textViewDidChange(v)
                }
            }
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IdeaTextView
        var listID: Int
        var dismissID: Int
        init(_ p: IdeaTextView) { parent = p; listID = p.listRequest; dismissID = p.dismissRequest }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.beginTyping() }
        func textViewDidChange(_ v: UITextView) { parent.text = v.text }
        func textView(_ v: UITextView,shouldChangeTextIn range:NSRange,replacementText replacement:String) -> Bool {
            guard replacement == "\n" else { return true }
            let str = v.text as NSString
            let line = str.lineRange(for:NSRange(location:range.location,length:0))
            let before = str.substring(with:NSRange(location:line.location,length:range.location-line.location))
            guard let marker = before.range(of:"^[0-9]{1,8}\\. ",options:.regularExpression),
                  let n = Int(before[marker].dropLast(2)) else { return true }
            var target = range
            var next = "\n\(n+1). "
            let rest = str.substring(with:line).dropFirst(before[marker].count)
            if rest.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                target = NSRange(location:line.location,length:NSMaxRange(range)-line.location)
                next = ""
            }
            v.textStorage.replaceCharacters(in:target,with:next)
            v.selectedRange = NSRange(location:target.location+(next as NSString).length,length:0)
            textViewDidChange(v)
            return false
        }
    }
}

struct InkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal,5)
            .contentShape(RoundedRectangle(cornerRadius:8))
            .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(Paper.ink.opacity(configuration.isPressed ? 0.8 : 0.30),lineWidth:1).allowsHitTesting(false) }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

// Some recognizers restart their partial transcript after a quiet interval.
struct SpeechPhrases {
    private var frozen = ""
    private var current = ""
    var value: String { [frozen,current].filter { !$0.isEmpty }.joined(separator:" ") }
    private var firstTime: Double?
    private var previousEnd = 0.0
    private var lastEvent: Double?
    mutating func receive(_ words: String, start: Double, end: Double, at now: Double) -> String {
        let previous = current.lowercased().split(separator:" ")
        let incoming = words.lowercased().split(separator:" ")
        let extended = incoming.starts(with:previous)
        let shifted = start >= previousEnd - 0.04 && start > (firstTime ?? start)+0.18
        let clockReset = end + 0.1 < previousEnd
        let quiet = now - (lastEvent ?? now) > 1.0
        let resumed = quiet && (clockReset || incoming.first != previous.first)
        if !current.isEmpty && (shifted || (resumed && !extended)) {
            frozen = [frozen,current].filter { !$0.isEmpty }.joined(separator:" ")
        }
        current = words; firstTime = start; previousEnd = end; lastEvent = now
        return [frozen,current].filter { !$0.isEmpty }.joined(separator:" ")
    }
}


import PhotosUI
import ImageIO

struct JournalCover: Codable {
    var title = ""
    var shade = 0
    var photo: Data?

    static let colors: [Color] = [
        Color(red:0.28,green:0.28,blue:0.30), Color(red:0.37,green:0.22,blue:0.22),
        Color(red:0.23,green:0.33,blue:0.30), Color(red:0.23,green:0.29,blue:0.42),
        Color(red:0.47,green:0.39,blue:0.28)
    ]
    static let names = ["Графит", "Бордо", "Шалфей", "Индиго", "Песок"]
}

struct NotebookObject: View {
    let cover: JournalCover
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var angle = -20.0
    @State private var pitch = 9.0
    @State private var pan: CGSize = .zero
    private var yaw: Double { angle + Double(pan.width) * 0.64 }
    private var tilt: Double { min(42,max(-42,pitch - Double(pan.height)*0.2)) }
    private var back: Bool { cos(yaw * .pi / 180) < 0 }

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white:0.15)).frame(width:182,height:258).offset(x:10,y:5)
            RoundedRectangle(cornerRadius:4).fill(Color(white:0.78)).frame(width:180,height:251).offset(x:9,y:4)
                .overlay {
                    Canvas { context, size in
                        var lines = Path()
                        for n in 0..<39 {
                            let y = 8 + Double(n)*6.4
                            lines.move(to:CGPoint(x:size.width-8,y:y))
                            lines.addLine(to:CGPoint(x:size.width+9,y:y))
                        }
                        context.stroke(lines,with:.color(.black.opacity(0.25)),lineWidth:0.5)
                    }.frame(width:182,height:258).allowsHitTesting(false)
                }
            face
                .rotation3DEffect(.degrees(back ? 180 : 0),axis:(x:0,y:1,z:0))
        }
        .rotation3DEffect(.degrees(tilt),axis:(x:1,y:0,z:0),perspective:0)
        .rotation3DEffect(.degrees(yaw),axis:(x:0,y:1,z:0),perspective:0.58)
        .scaleEffect(1 + 0.025 * abs(sin(yaw * .pi/180)))
        .frame(width:236,height:280)
        .contentShape(Rectangle())
        .gesture(DragGesture().onChanged { pan = $0.translation }.onEnded { value in
            angle = yaw.truncatingRemainder(dividingBy:360)
            pitch = tilt
            pan = .zero
            if !reduced {
                withAnimation(.spring(response:0.54,dampingFraction:0.82)) {
                    let momentum = value.predictedEndTranslation.width-value.translation.width
                    angle += min(95,max(-95,Double(momentum)*0.3))
                    pitch *= 0.7
                }
            }
        })
        .accessibilityLabel(cover.title.isEmpty ? "Обложка дневника" : cover.title)
        .accessibilityAction(named:Text("Повернуть блокнот")) { angle += 45 }
    }

    private var face: some View {
        ZStack(alignment:.leading) {
            JournalCover.colors[cover.shade]
            if let data = cover.photo, let photo = UIImage(data:data) {
                Image(uiImage:photo).resizable().scaledToFill().frame(width:182,height:258).clipped()
            }
            LinearGradient(colors:[.white.opacity(0.24),.clear,.black.opacity(0.28)],startPoint:.topLeading,endPoint:.bottomTrailing)
            Canvas { context, size in
                var light = Path(), dark = Path()
                for index in 0..<2300 {
                    let x = Double((index*151 + index*index*11)%4093)/4093*size.width
                    let y = Double((index*379 + index*index*7)%4099)/4099*size.height
                    let bounds = CGRect(x:x,y:y,width:1.2+Double(index%3)*0.45,height:0.48)
                    if index.isMultiple(of:2) { light.addRect(bounds) } else { dark.addRect(bounds) }
                }
                context.fill(light,with:.color(.white.opacity(0.20)))
                context.fill(dark,with:.color(.black.opacity(0.31)))
            }
            Rectangle().fill(.linearGradient(colors:[.black.opacity(0.42),.white.opacity(0.15),.black.opacity(0.24),.clear],startPoint:.leading,endPoint:.trailing)).frame(width:17)
            if !back && !cover.title.isEmpty {
                Text(cover.title).font(.system(size:23,weight:.semibold,design:.serif))
                    .lineLimit(3).minimumScaleFactor(0.60).multilineTextAlignment(.center).foregroundStyle(.white)
                    .shadow(color:.black.opacity(0.78),radius:3,y:1)
                    .padding(.horizontal,19).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).padding(.top,40)
            }
        }.frame(width:182,height:258)
         .clipShape(RoundedRectangle(cornerRadius:5)).overlay { RoundedRectangle(cornerRadius:5).strokeBorder(.white.opacity(0.16)) }
    }
}

enum CoverStage { case intro, title, cover }

struct JournalSetup: View {
    let existing: JournalCover?
    let onCancel: () -> Void
    let onSave: (JournalCover) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var stage: CoverStage
    @State private var cover: JournalCover
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var photoError = false
    @State private var leaving = false
    @State private var promptVisible = false
    @FocusState private var typing: Bool

    init(existing: JournalCover?, onCancel: @escaping () -> Void, onSave: @escaping (JournalCover) -> Void) {
        self.existing = existing
        self.onCancel = onCancel
        self.onSave = onSave
        _stage = State(initialValue: existing == nil ? .intro : .title)
        _cover = State(initialValue: existing ?? JournalCover())
    }

    var body: some View {
        content
            .task { await revealPrompt() }
            .task(id:selection) { await readPhoto() }
            .alert("Фото не открылось",isPresented:$photoError) { Button("Закрыть",role:.cancel) {} }
    }

    private var content: some View {
        VStack(spacing:0) {
            if stage != .intro { header }
            Spacer(minLength:4)
            NotebookObject(cover:cover)
                .scaleEffect(typing ? 0.53 : leaving && !reduced ? 1.19 : 1)
                .frame(height:typing ? 150 : 280)
                .animation(reduced ? nil : .easeInOut(duration:0.24),value:typing)
                .simultaneousGesture(TapGesture().onEnded { if stage == .intro { change(.title) } })
            Spacer(minLength:4)
            controls
        }.padding(.bottom,16).foregroundStyle(.white)
         .background(.black.ignoresSafeArea()).opacity(leaving ? 0 : 1)
         .buttonStyle(.plain).preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button {
                typing = false
                if stage == .cover { change(.title) }
                else if existing == nil { change(.intro) } else { onCancel() }
            } label: { Image(systemName:"chevron.left").frame(width:44,height:44) }
            .accessibilityLabel("Назад")
            Spacer()
            Text(stage == .title ? "Название" : "Обложка").font(.subheadline.weight(.medium))
            Spacer()
            Color.clear.frame(width:44,height:44).accessibilityHidden(true)
        }.padding(.horizontal,20)
    }

    @ViewBuilder private var controls: some View {
        switch stage {
        case .intro:
            Button { change(.title) } label: {
                Text("создай свой дневник идей").font(.callout)
                    .padding(.horizontal,19).frame(minHeight:50)
                    .background(.white.opacity(0.10),in:Capsule())
            }.opacity(promptVisible ? 1 : 0)
             .offset(y:promptVisible || reduced ? 0 : 16).accessibilityHidden(!promptVisible)
        case .title:
            VStack(spacing:12) {
                TextField("Название дневника",text:$cover.title)
                    .focused($typing).submitLabel(.next).onSubmit(next)
                    .onChange(of:cover.title) { _, title in
                        if title.count > 55 { cover.title = String(title.prefix(55)) }
                    }
                    .textFieldStyle(.plain).padding(14)
                    .background(.white.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
                Button("Далее",action:next).buttonStyle(JournalPrimary()).disabled(cleanTitle.isEmpty)
            }.padding(.horizontal,26)
        case .cover:
            VStack(spacing:14) {
                HStack(spacing:14) {
                    ForEach(JournalCover.colors.indices,id:\.self) { index in swatch(index) }
                }
                PhotosPicker(selection:$selection,matching:.images) {
                    Label(loading ? "Загрузка…" : "Фото из галереи",systemImage:"photo").frame(minHeight:44)
                }
                Button(existing == nil ? "Создать дневник" : "Сохранить обложку",action:complete)
                    .buttonStyle(JournalPrimary()).disabled(loading || leaving)
            }.padding(.horizontal,26)
        }
    }

    private func swatch(_ index: Int) -> some View {
        let selected = cover.photo == nil && cover.shade == index
        return Button {
            selection = nil
            cover.shade = index
            cover.photo = nil
        } label: {
            Circle().fill(JournalCover.colors[index]).frame(width:35,height:35)
                .padding(4).overlay { Circle().strokeBorder(selected ? Color.white : Color.clear,lineWidth:1) }
        }.accessibilityLabel(JournalCover.names[index]).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func revealPrompt() async {
        if !reduced { try? await Task.sleep(for:.milliseconds(200)) }
        guard !Task.isCancelled else { return }
        withAnimation(reduced ? nil : .easeOut(duration:0.3)) { promptVisible = true }
    }

    private func readPhoto() async {
        guard let item = selection else { loading = false; return }
        loading = true
        do {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:1200
            ]
            guard let data = try await item.loadTransferable(type:Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData,nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary),
                  let jpeg = UIImage(cgImage:image).jpegData(compressionQuality:0.82) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard !Task.isCancelled, selection == item else { return }
            cover.photo = jpeg
        } catch {
            if !Task.isCancelled { photoError = true }
        }
        if selection == item { loading = false }
    }

    private var cleanTitle: String { cover.title.trimmingCharacters(in:.whitespacesAndNewlines) }
    private func change(_ next: CoverStage) { withAnimation(reduced ? nil : .easeInOut(duration:0.28)) { stage = next } }
    private func next() {
        guard !cleanTitle.isEmpty else { return }
        cover.title = cleanTitle
        typing = false
        change(.cover)
    }
    private func complete() {
        if reduced { onSave(cover); return }
        withAnimation(.easeIn(duration:0.28)) { leaving = true }
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(290))
            onSave(cover)
        }
    }
}

struct JournalPrimary: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).frame(maxWidth:.infinity,minHeight:49)
            .foregroundStyle(Paper.sheet).background(Paper.ink,in:RoundedRectangle(cornerRadius:16))
            .opacity(!enabled ? 0.38 : configuration.isPressed ? 0.72 : 1)
    }
}
