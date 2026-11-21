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
    var bloom: Bloom? = nil
    var decoration: Bloom? { bloom ?? (flower == true ? .daisy : nil) }
    var award: Int
}

struct Notebook: Codable {
    var ideas: [Idea] = []
    var balance = 0
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
    @State private var bloom: Bloom?
    @State private var showFlowers = false
    @AppStorage("think.draft.bloom") private var draftBloom = ""
    @AppStorage("think.palette") private var paletteName = AppPalette.ice.rawValue
    private var palette: AppPalette { AppPalette(rawValue:paletteName) ?? .ice }
    @AppStorage("think.draft.flower") private var draftFlower = false
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
    var accent: Color { palette.accent }
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
        .preferredColorScheme(.dark)
        .safeAreaInset(edge:.bottom,spacing:0) {
            if cover != nil && !editingCover && page != .editor { menu }
        }
        .buttonStyle(.plain)
        .tint(palette.accent)
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
        .sheet(isPresented:$showFlowers) { flowers }
        .sheet(isPresented: $showRewards) {
            rewards.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
        }
        .foregroundStyle(palette.ink).environment(\.appPalette,palette)
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
        bloom = idea == nil ? (Bloom(rawValue:draftBloom) ?? (draftFlower ? .daisy : nil)) : idea?.decoration
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
        idea.text = words; idea.bloom = bloom; idea.flower = nil; idea.step = ""; idea.award = score
        if let index = next.ideas.firstIndex(where: { $0.id == idea.id }) { next.ideas[index] = idea }
        else { next.ideas.insert(idea, at: 0) }
        guard persist(next) else { return }
        if editing == nil { draft = ""; draftStep = ""; draftFlower = false; draftBloom = "" }
        dismissRequest += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if editing != nil { detail = idea } else { detail = nil; search = ""; dayFilter = nil }
        page = .collection
    }
    private var capture: some View {
        VStack(spacing:0) {
            HStack(spacing:9) {
                SparkShape().fill(palette.ink).frame(width:17,height:17)
                Text("thinkinbrain").font(.system(size:15,weight:.semibold)).tracking(0.15)
            }.foregroundStyle(palette.ink).frame(height:52)
            Spacer(minLength:4)
            ParticleStar {
                UIImpactFeedbackGenerator(style:.soft).impactOccurred()
                begin()
            }.aspectRatio(1.12,contentMode:.fit)
            Text("запиши идею пока не забыл")
                .font(.subheadline).foregroundStyle(palette.muted).padding(.horizontal,20)
                .multilineTextAlignment(.center)
            Spacer(minLength:12)
        }.frame(maxWidth:.infinity)
         .background(palette.sheet.ignoresSafeArea())
    }

    private var menu: some View {
        HStack(spacing:4) {
            tab(.spark, "Главная", "circle.dotted")
            tab(.collection, "Мои идеи", "books.vertical")
            tab(.settings, "Настройки", "slider.horizontal.3")
        }.padding(.horizontal,16).padding(.top,8).padding(.bottom,4)
         .background(palette.sheet.ignoresSafeArea(edges:.bottom))
         .overlay(alignment:.top) { Rectangle().fill(.primary.opacity(0.09)).frame(height:1) }
    }

    private func tab(_ tab: Page, _ title: String, _ icon: String) -> some View {
        Button {
            if tab != page { detail = nil; page = tab }
        } label: {
            VStack(spacing:4) {
                Image(systemName:icon).font(.system(size:19,weight:page == tab ? .semibold : .regular))
                Text(title).font(.caption2.weight(page == tab ? .semibold : .regular)).lineLimit(1)
            }.foregroundStyle(page == tab ? palette.ink : palette.muted)
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
                                Text("Название и обложка").font(.subheadline).foregroundStyle(palette.muted)
                            }
                            Spacer()
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(palette.muted)
                        }.padding(15).background(palette.card,in:RoundedRectangle(cornerRadius:20))
                    }
                }
                paletteSettings
                VStack(spacing:0) {
                    Button { showRewards = true } label: {
                        HStack {
                            Label("Звёзды",systemImage:"sparkle")
                            Spacer()
                            Text("\(book.balance)").monospacedDigit().foregroundStyle(palette.muted)
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(palette.muted)
                        }.padding(17)
                    }
                }.background(palette.card,in:RoundedRectangle(cornerRadius:20))
            }.padding(22)
        }.foregroundStyle(palette.ink).background(palette.sheet.ignoresSafeArea())
    }
    private var paletteSettings: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Цвет приложения").font(.headline)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:66),spacing:10)],spacing:13) {
                ForEach(AppPalette.allCases) { option in
                    let selected = option == palette
                    Button {
                        paletteName = option.rawValue
                    } label: {
                        VStack(spacing:6) {
                            Circle().fill(option.accent).frame(width:29,height:29)
                                .overlay { if selected { Image(systemName:"checkmark").font(.caption.bold()).foregroundStyle(palette.sheet) } }
                            Text(option.name).font(.caption2).lineLimit(1)
                        }.frame(maxWidth:.infinity,minHeight:54)
                    }.accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }.padding(16).background(palette.card,in:RoundedRectangle(cornerRadius:20))
    }

    private var flowers: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Цветок идеи").font(.title2.bold())
                LazyVGrid(columns:[GridItem(.adaptive(minimum:85),spacing:10)],spacing:12) {
                    ForEach(Bloom.allCases) { option in
                        Button { chooseFlower(option) } label: {
                            VStack(spacing:5) {
                                Flower(kind:option).frame(width:36,height:52)
                                Text(option.name).font(.caption).lineLimit(1)
                            }.frame(maxWidth:.infinity,minHeight:84)
                             .background(palette.card,in:RoundedRectangle(cornerRadius:12))
                             .overlay { RoundedRectangle(cornerRadius:12).strokeBorder(bloom == option ? palette.accent : .clear) }
                        }.accessibilityAddTraits(bloom == option ? .isSelected : [])
                    }
                }
                if bloom != nil { Button("Убрать цветок") { chooseFlower(nil) }.frame(minHeight:44) }
            }.padding(22)
        }.presentationBackground(palette.sheet).presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }

    private func chooseFlower(_ choice: Bloom?) {
        bloom = choice
        if editing == nil { draftBloom = choice?.rawValue ?? ""; draftFlower = false }
        showFlowers = false
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { voice.cancel(); dismissRequest += 1; page = editorOrigin } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Назад")
                Spacer()
                Text(editing == nil ? "Новая мысль" : "Редактирование").font(.subheadline).foregroundStyle(palette.muted)
                Spacer()
                Button("Готово",action:save).font(.subheadline.weight(.semibold)).padding(.vertical,3)
                    .frame(minHeight:44).foregroundStyle(palette.accent)
                    .disabled(voice.waiting || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if let bloom { Flower(kind:bloom).frame(width:42,height:58).frame(maxWidth:.infinity) }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voice.listening ? "Слушаю…" : "О чём ты думаешь?").foregroundStyle(palette.muted).padding(.top,8).padding(.leading,5).allowsHitTesting(false) }
                IdeaTextView(text:$text,listRequest:listRequest,dismissRequest:dismissRequest) { voice.cancel() }
            }.font(.system(.title2))
             .onChange(of:text) { _,value in if editing == nil { draft = value } }
            HStack(spacing:12) {
                Button { voice.cancel(); listRequest += 1 } label: {
                    Image(systemName:"list.number").frame(width:40,height:44)
                }.accessibilityLabel("Нумерованный список")
                Button { showFlowers = true } label: {
                    Flower(kind:bloom ?? .daisy).frame(width:22,height:32)
                        .frame(width:40,height:44).opacity(bloom == nil ? 0.65 : 1)
                }.accessibilityLabel("Выбрать цветок")
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
        }.padding(.horizontal, 22).padding(.bottom, 8).foregroundStyle(palette.ink)
         .background(palette.sheet.ignoresSafeArea())
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
                }.foregroundStyle(palette.muted)
            }
            if let idea = detail {
                Text("Идея").font(.largeTitle.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let decoration = idea.decoration { Flower(kind:decoration).frame(width:42,height:58).frame(maxWidth:.infinity) }
                        Text("Дата создания").font(.caption).foregroundStyle(palette.accent)
                        Text(idea.created, format: .dateTime.day().month(.wide).year().hour().minute()).font(.subheadline)
                        Divider()
                        Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                            .font(.system(.title3)).textSelection(.enabled)
                        if !idea.step.isEmpty { Text(idea.step) }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22)
                     .foregroundStyle(palette.ink).background(palette.card,in:RoundedRectangle(cornerRadius:8))
                }
                Button { begin(idea) } label: { Label("Редактировать",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:48) }
                    .foregroundStyle(palette.accent)
            } else {
                HStack {
                    Text("Мои идеи").font(.largeTitle.bold())
                    Spacer()
                    Button {
                        calendarDay = dayFilter ?? Date()
                        calendarOpen = true
                    } label: { Label("Календарь",systemImage:"calendar").font(.footnote).frame(minHeight:44) }
                    .foregroundStyle(palette.accent)
                }
                if let dayFilter {
                    Button { self.dayFilter = nil } label: {
                        HStack { Text(dayFilter,format:.dateTime.day().month(.wide).year()); Image(systemName:"xmark") }
                    }.foregroundStyle(palette.accent).accessibilityHint("Показать все даты")
                }
                if !book.ideas.isEmpty {
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(palette.muted)
                        TextField("Поиск по идеям",text:$search).submitLabel(.search)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Очистить поиск") }
                    }.padding(.horizontal,14).frame(minHeight:44).background(palette.card,in:RoundedRectangle(cornerRadius:12))
                }
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:12) {
                        let sections = journalDays
                        if sections.isEmpty {
                            Text(dayFilter != nil && search.isEmpty ? "В этот день идей пока нет." : book.ideas.isEmpty ? "Здесь появятся твои идеи. Начни с первой записи." : "По этому запросу записей нет.")
                                .foregroundStyle(palette.muted).padding(.vertical,24)
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
                                                if let decoration = idea.decoration { Flower(kind:decoration).frame(width:13,height:19) }
                                                Image(systemName:idea.audio == nil ? "text.alignleft" : "waveform")
                                                Text(idea.audio == nil ? "Текст" : "Голос")
                                                Text("·")
                                                Text(idea.created,style:.time)
                                            }.font(.caption).foregroundStyle(palette.ink.opacity(0.7))
                                            Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                                                .font(.system(.title3)).lineLimit(3)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:"chevron.right").foregroundStyle(palette.accent)
                                    }.multilineTextAlignment(.leading).padding(16).foregroundStyle(palette.ink)
                                     .background(palette.card,in:RoundedRectangle(cornerRadius:17))
                                     .overlay { RoundedRectangle(cornerRadius:17).strokeBorder(palette.ink.opacity(0.06)).allowsHitTesting(false) }
                                }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                Button { begin() } label: { Label("Новая идея",systemImage:"plus").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:48) }
                    .buttonStyle(JournalPrimary())
            }
        }.buttonStyle(.plain).padding(.horizontal,22).padding(.bottom,8)
         .foregroundStyle(palette.ink).background(palette.sheet.ignoresSafeArea())
         .environment(\.locale,Locale(identifier:"ru"))
         .sheet(isPresented:$calendarOpen) {
             IdeaCalendar(selection:$calendarDay,
                          recorded:Set(book.ideas.map { Calendar.current.startOfDay(for:$0.created) }),
                          apply:{ dayFilter = calendarDay; calendarOpen = false },
                          reset:{ dayFilter = nil; calendarOpen = false })
         }
    }
    private var rewards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Мои звёзды").font(.largeTitle.bold())
                HStack { SparkShape().fill(accent).frame(width: 36, height: 36); Text("\(book.balance)").font(.largeTitle.monospacedDigit()) }
                Text("Одна звезда за мысль, ещё одна за описание от 80 символов и одна за текст от 200 символов. Дополняй запись позже — звёзды сохранятся.").foregroundStyle(palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }.padding(.top, 15).presentationBackground(palette.sheet)
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
                        update(self.phrases.receive(words,start:from,end:until,at:ProcessInfo.processInfo.systemUptime,closing:!self.listening))
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
    @Environment(\.appPalette) private var palette
    let active: Bool
    let waiting: Bool
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Image(systemName:"mic.fill")
                .font(.system(size:25,weight:.medium))
                .foregroundStyle(active ? palette.accent : palette.ink)
                .frame(width:60,height:60)
                .overlay { Circle().strokeBorder(active ? palette.accent : palette.ink.opacity(0.45),lineWidth:active ? 2 : 1) }
                .contentShape(Circle())
        }.buttonStyle(.plain).disabled(waiting)
         .accessibilityLabel(active ? "Остановить диктовку" : "Начать диктовку")
    }
}


import SwiftUI
import UIKit

struct IdeaTextView: UIViewRepresentable {
    @Environment(\.appPalette) private var palette
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
        v.textColor = UIColor(palette.ink)
        v.tintColor = UIColor(palette.accent)
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
    @Environment(\.appPalette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal,5)
            .contentShape(RoundedRectangle(cornerRadius:8))
            .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(palette.ink.opacity(configuration.isPressed ? 0.8 : 0.30),lineWidth:1).allowsHitTesting(false) }
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
    mutating func receive(_ words: String, start: Double, end: Double, at now: Double, closing: Bool = false) -> String {
        let previous = tokens(current)
        let incoming = tokens(words)
        guard !incoming.isEmpty else { return value }
        let committed = tokens(frozen)
        if !committed.isEmpty && incoming.starts(with:committed) && incoming.count > committed.count {
            frozen = ""
            current = words
            firstTime = start
            previousEnd = end
            lastEvent = now
            return value
        }
        let extended = incoming.starts(with:previous)
        let shifted = start >= previousEnd - 0.04 && start > (firstTime ?? start)+0.18
        let clockReset = end + 0.1 < previousEnd
        let quiet = now - (lastEvent ?? now) > 1.0

        if closing && !extended {
            let accepted = tokens(value)
            if accepted.suffix(incoming.count).elementsEqual(incoming) || accepted.starts(with: incoming) { return value }
            if shifted || clockReset {
                let overlap = suffixOverlap(accepted,incoming)
                let tail = words.split(whereSeparator: \.isWhitespace).dropFirst(overlap).joined(separator:" ")
                if !tail.isEmpty { frozen = value; current = tail }
                return value
            }
        }
        if !current.isEmpty && !extended && (shifted || quiet && (clockReset || incoming.first != previous.first)) {
            let overlap = suffixOverlap(previous,incoming)
            if overlap == incoming.count {
                return value
            }
            // Keep the overlapping words inside the new fragment so the next partial can revise it.
            let prefix = current.split(whereSeparator: \.isWhitespace).dropLast(overlap).joined(separator:" ")
            frozen = [frozen,prefix].filter { !$0.isEmpty }.joined(separator:" ")
        }
        current = words
        firstTime = start
        previousEnd = end
        lastEvent = now
        return value
    }
    private func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map {
            $0.trimmingCharacters(in:.punctuationCharacters)
        }
    }
    private func suffixOverlap(_ previous: [String],_ next: [String]) -> Int {
        let limit = min(previous.count,next.count)
        guard limit > 0 else { return 0 }
        return stride(from:limit,through:1,by:-1).first { previous.suffix($0).elementsEqual(next.prefix($0)) } ?? 0
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
    @Environment(\.appPalette) private var palette
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
                Text(cover.title).font(.system(size:23,weight:.semibold))
                    .lineLimit(3).minimumScaleFactor(0.60).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                    .shadow(color:.black.opacity(0.78),radius:3,y:1)
                    .padding(.horizontal,19).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).padding(.top,40)
            }
        }.frame(width:182,height:258)
         .clipShape(RoundedRectangle(cornerRadius:5)).overlay { RoundedRectangle(cornerRadius:5).strokeBorder(.white.opacity(0.16)) }
    }
}

enum CoverStage { case intro, title, cover }

struct JournalSetup: View {
    @Environment(\.appPalette) private var palette
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
        }.padding(.bottom,16).foregroundStyle(palette.ink)
         .background(palette.sheet.ignoresSafeArea()).opacity(leaving ? 0 : 1)
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
                    .background(palette.card,in:Capsule())
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
                    .background(palette.card,in:RoundedRectangle(cornerRadius:12))
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
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).frame(maxWidth:.infinity,minHeight:49)
            .foregroundStyle(palette.ink).background(palette.card,in:RoundedRectangle(cornerRadius:16))
            .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(palette.accent.opacity(0.28)).allowsHitTesting(false) }
            .opacity(!enabled ? 0.38 : configuration.isPressed ? 0.72 : 1)
    }
}


struct IdeaCalendar: View {
    @Binding var selection: Date
    let recorded: Set<Date>
    let apply: () -> Void
    let reset: () -> Void
    @Environment(\.appPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var monthMode = false

    private let cal = Calendar.current
    private let width: CGFloat = 44
    private let dates: [Date]
    init(selection: Binding<Date>, recorded: Set<Date>, apply: @escaping () -> Void, reset: @escaping () -> Void) {
        _selection = selection
        self.recorded = recorded
        self.apply = apply
        self.reset = reset
        let c = Calendar.current
        let today = c.startOfDay(for: Date())
        let anchor = min(today,recorded.min() ?? today)
        let first = c.date(byAdding:.year,value:-1,to:anchor) ?? anchor
        let last = c.date(byAdding:.year,value:1,to:today) ?? today
        let days = c.dateComponents([.day],from:first,to:last).day ?? 0
        dates = (0...max(0,days)).compactMap { c.date(byAdding:.day,value:$0,to:first).map { c.startOfDay(for:$0) } }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:5) {
                mode("Лента", monthly:false)
                mode("Месяц", monthly:true)
            }.padding(4).background(palette.card,in:RoundedRectangle(cornerRadius:14))
            HStack(alignment:.firstTextBaseline) {
                Text(selection,format:.dateTime.month(.wide).year()).font(.title2.weight(.medium))
                Spacer()
                Text(selection,format:.dateTime.day()).font(.system(size:48,weight:.light)).monospacedDigit()
            }
            if monthMode {
                DatePicker("Дата",selection:$selection,in:(dates.first ?? .distantPast)...(dates.last ?? .distantFuture),displayedComponents:.date)
                    .datePickerStyle(.graphical).labelsHidden()
            } else { strip }
            HStack {
                Button("Все даты",action:reset).frame(minHeight:44)
                Spacer()
                Button("Показать идеи",action:apply).frame(minHeight:44)
                    .font(.body.weight(.semibold))
            }
        }.padding(20).foregroundStyle(palette.ink).tint(palette.accent)
         .environment(\.locale,Locale(identifier:"ru"))
         .presentationBackground(palette.sheet).presentationDetents(monthMode ? [.large] : [.height(330),.large])
         .presentationDragIndicator(.visible)
    }
    private func mode(_ label:String,monthly:Bool) -> some View {
        Button { withAnimation(reduced ? nil : .easeInOut(duration:0.2)) { monthMode = monthly } } label: {
            Text(label).font(.subheadline.weight(.medium)).frame(maxWidth:.infinity,minHeight:38)
                .foregroundStyle(monthMode == monthly ? palette.sheet : palette.ink)
                .background(monthMode == monthly ? palette.accent : Color.clear,in:RoundedRectangle(cornerRadius:10))
        }.accessibilityAddTraits(monthMode == monthly ? .isSelected : [])
    }
    private var center: Binding<Date?> {
        Binding(get:{ cal.startOfDay(for:selection) },set:{ if let value = $0 { selection = value } })
    }
    private var strip: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing:4) {
                    ForEach(dates,id:\.self) { day in
                        dateCell(day).id(day)
                    }
                }.scrollTargetLayout()
            }.contentMargins(.horizontal,max(0,(geo.size.width-width)/2),for:.scrollContent)
             .scrollTargetBehavior(.viewAligned(limitBehavior:.always))
             .scrollPosition(id:center,anchor:.center)
             .scrollIndicators(.hidden)
             .mask { LinearGradient(stops:[.init(color:.clear,location:0),.init(color:.black,location:0.09),.init(color:.black,location:0.91),.init(color:.clear,location:1)],startPoint:.leading,endPoint:.trailing) }
        }.frame(height:86).background(palette.card,in:RoundedRectangle(cornerRadius:15))
    }
    private func dateCell(_ day:Date) -> some View {
        let selected = cal.isDate(day,inSameDayAs:selection)
        return Button {
            withAnimation(reduced ? nil : .easeOut(duration:0.25)) { selection = day }
        } label: {
            VStack(spacing:4) {
                Text(day,format:.dateTime.weekday(.abbreviated)).font(.caption).foregroundStyle(palette.muted)
                Text(day,format:.dateTime.day()).font(.subheadline.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? palette.sheet : palette.ink).frame(width:36,height:36)
                    .background(selected ? palette.accent : Color.clear,in:Circle())
                Circle().fill(palette.accent.opacity(recorded.contains(day) ? 1 : 0)).frame(width:4,height:4)
            }.frame(width:width,height:78)
        }.accessibilityLabel(day.formatted(date:.complete,time:.omitted))
         .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

