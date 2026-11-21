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
            if page == .collection { archive.transition(.opacity) }
            else if page == .editor { editor.transition(.opacity.combined(with: .offset(y: reduced ? 0 : 12))) }
            else { capture.transition(.opacity) }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.32), value: page)
        .preferredColorScheme(darkTheme ? .dark : .light)
        .buttonStyle(InkButton())
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
    private var balance: some View {
        Button { showRewards = true } label: {
            HStack(spacing: 7) {
                SparkShape().frame(width: 13, height: 13)
                Text("\(book.balance)").monospacedDigit()
            }.padding(.horizontal, 14).frame(minHeight: 44)
             
        }.accessibilityLabel("Мои звёзды, \(book.balance)")
    }
    private var capture: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button { darkTheme.toggle() } label: {
                        Image(systemName:darkTheme ? "sun.max" : "moon").frame(width:40,height:42)
                    }.accessibilityLabel(darkTheme ? "Светлая тема" : "Тёмная тема")
                    Spacer(); balance
                }
                ThinkLetters().frame(width:102,height:32)
            }.padding(.horizontal,24)
            Spacer(minLength: 8)
            VStack(spacing: 12) {
                ParticleStar(cool: book.cool) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    begin()
                }.aspectRatio(1.12, contentMode: .fit)
                Text("Поймай мысль.")
                    .font(.system(.title,design:.monospaced)).foregroundStyle(Paper.blue)
                Text("Крути шар пальцем. Коснись, чтобы записать.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
            Spacer(minLength: 20)
            Button { detail = nil; search = ""; dayFilter = nil; page = .collection } label: {
                Label("Идеи · \(book.ideas.count)", systemImage: "square.stack").font(.callout)
                    .padding(.horizontal, 20).frame(minHeight: 48)
            }.padding(.bottom, 12)
        }.buttonStyle(InkButton()).foregroundStyle(Paper.ink)
         .background(Paper.sheet.ignoresSafeArea())
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
                Button("Сохранить",action:save).font(.subheadline).padding(.vertical,3)
                    .frame(minHeight:44).foregroundStyle(Paper.blue)
                    .disabled(voice.waiting || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if flower { Flower().frame(width:42,height:58).frame(maxWidth:.infinity) }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voice.listening ? "Слушаю…" : "О чём ты думаешь?").foregroundStyle(.secondary).padding(.top,8).padding(.leading,5).allowsHitTesting(false) }
                IdeaTextView(text:$text,listRequest:listRequest,dismissRequest:dismissRequest) { voice.cancel() }
            }.font(.system(.title2,design:.monospaced))
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
                        if idea.flower == true { Flower().frame(width:42,height:58).frame(maxWidth:.infinity) }
                        Text("Дата создания").font(.caption).foregroundStyle(Paper.blue)
                        Text(idea.created, format: .dateTime.day().month(.wide).year().hour().minute()).font(.custom("Menlo-Regular",size:15,relativeTo:.subheadline))
                        Divider()
                        Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                            .font(.custom("Menlo-Regular",size:21,relativeTo:.title3)).textSelection(.enabled)
                        if !idea.step.isEmpty { Text(idea.step) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22)
                     .foregroundStyle(Paper.ink).background(Paper.card,in:RoundedRectangle(cornerRadius:8))
                }
                Button { begin(idea) } label: { Label("Редактировать",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(Paper.blue)
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
                                                if idea.flower == true { Flower().frame(width:13,height:19) }
                                                Image(systemName:idea.audio == nil ? "text.alignleft" : "waveform")
                                                Text(idea.audio == nil ? "Текст" : "Голос")
                                                Text("·")
                                                Text(idea.created,style:.time)
                                            }.font(.custom("Menlo-Regular",size:12,relativeTo:.caption)).foregroundStyle(Paper.ink.opacity(0.7))
                                            Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                                                .font(.custom("Menlo-Regular",size:21,relativeTo:.title3)).lineLimit(3)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:"chevron.right").foregroundStyle(Paper.blue)
                                    }.multilineTextAlignment(.leading).padding(16).foregroundStyle(Paper.ink)
                                     
                                }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                Button { begin() } label: { Label("Новая идея",systemImage:"plus").font(.custom("Menlo-Regular",size:17,relativeTo:.headline)).frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(Paper.blue)
            }
        }.font(.custom("Menlo-Regular",size:17,relativeTo:.body)).buttonStyle(InkButton()).padding(.horizontal,22).padding(.bottom,8)
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
        v.font = UIFontMetrics(forTextStyle:.title2).scaledFont(for:UIFont.monospacedSystemFont(ofSize:21, weight:.regular))
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

struct ThinkLetters: View {
    var body: some View {
        Canvas { c,size in
            c.scaleBy(x:size.width/115,y:size.height/35)
            var p = Path()
            func line(_ a:CGPoint,_ b:CGPoint) { p.move(to:a); p.addLine(to:b) }
            line(CGPoint(x:7,y:5),CGPoint(x:7,y:24))
            p.addQuadCurve(to:CGPoint(x:18,y:29),control:CGPoint(x:7,y:33))
            line(CGPoint(x:1,y:14),CGPoint(x:18,y:14))
            line(CGPoint(x:24,y:2),CGPoint(x:24,y:32))
            p.move(to:CGPoint(x:24,y:24));p.addQuadCurve(to:CGPoint(x:43,y:22),control:CGPoint(x:42,y:2))
            p.addLine(to:CGPoint(x:43,y:32))
            line(CGPoint(x:53,y:13),CGPoint(x:53,y:32))
            line(CGPoint(x:64,y:13),CGPoint(x:64,y:32))
            p.move(to:CGPoint(x:64,y:24));p.addQuadCurve(to:CGPoint(x:84,y:22),control:CGPoint(x:83,y:2))
            p.addLine(to:CGPoint(x:84,y:32))
            line(CGPoint(x:95,y:2),CGPoint(x:95,y:32))
            line(CGPoint(x:96,y:24),CGPoint(x:112,y:13))
            line(CGPoint(x:102,y:20),CGPoint(x:113,y:32))
            c.stroke(p,with:.color(Paper.ink),style:StrokeStyle(lineWidth:4.6,lineCap:.butt,lineJoin:.round))
            c.fill(Path(ellipseIn:CGRect(x:50.2,y:3.2,width:5.6,height:5.6)),with:.color(Paper.ink))
        }.accessibilityLabel("think")
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
