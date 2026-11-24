import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import ARKit
import simd

@main
struct ThinkApp: App {
    var body: some Scene { WindowGroup { Studio() } }
}

struct IdeaAddition: Codable, Identifiable {
    let id: UUID
    let created: Date
    let text: String
}

enum EyePupil: String, Codable, CaseIterable, Identifiable {
    case round, vortex, double, star
    var id: Self { self }
    var title: String {
        switch self {
        case .round: "Круглый"
        case .vortex: "Алый вихрь"
        case .double: "Двойной"
        case .star: "Звёздный"
        }
    }
    var price: Int {
        switch self {
        case .round: 0
        case .vortex: 12
        case .double: 16
        case .star: 20
        }
    }
}

enum CoverFinish: String, Codable, CaseIterable, Identifiable {
    case classic, linen, paper, embossed

    var id: Self { self }
    var title: String {
        switch self {
        case .classic: "Классика"
        case .linen: "Лён"
        case .paper: "Матовая бумага"
        case .embossed: "Тиснение"
        }
    }
    var price: Int {
        switch self {
        case .classic: 0
        case .linen: 8
        case .paper: 12
        case .embossed: 18
        }
    }
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
    var additions: [IdeaAddition]? = nil
    var bookmarked: Bool? = nil
    var award: Int
    var completedAt: Date? = nil
    var archivedAt: Date? = nil
    var pinnedUntil: Date? = nil
    var section: IdeaSection {
        if completedAt != nil { return .completed }
        return archivedAt == nil ? .active : .archived
    }
}

struct Notebook: Codable {
    var ideas: [Idea] = []
    var balance = 0
    var lastSeen: Date? = nil

    var ownedFinishes: Set<CoverFinish>? = nil
    var ownedPupils: Set<EyePupil>? = nil

    func owns(_ pupil:EyePupil) -> Bool {
        pupil == .round || ownedPupils?.contains(pupil) == true
    }

    mutating func unlockPupil(_ pupil:EyePupil) -> Bool {
        guard !owns(pupil), balance >= pupil.price else { return false }
        ownedPupils = (ownedPupils ?? []).union([pupil])
        balance -= pupil.price
        return true
    }

    func owns(_ finish:CoverFinish) -> Bool {
        finish == .classic || ownedFinishes?.contains(finish) == true
    }

    mutating func unlock(_ finish:CoverFinish) -> Bool {
        guard !owns(finish), balance >= finish.price else { return false }
        ownedFinishes = (ownedFinishes ?? []).union([finish])
        balance -= finish.price
        return true
    }

    static let pinPrice = 12
    static let completionReward = 5
    static let day: TimeInterval = 86_400

    mutating func resume(at now:Date) {
        if let lastSeen, now.timeIntervalSince(lastSeen) >= 7 * Self.day {
            for index in ideas.indices where ideas[index].section == .active {
                if (ideas[index].pinnedUntil ?? .distantPast) <= now { ideas[index].archivedAt = now }
            }
        }
        lastSeen = now
    }
    mutating func complete(_ id:UUID,at now:Date) -> Idea? {
        guard let i = ideas.firstIndex(where:{ $0.id == id }), ideas[i].section == .active else { return nil }
        ideas[i].completedAt = now
        balance += Self.completionReward
        return ideas[i]
    }
    mutating func pin(_ id:UUID,at now:Date) -> Idea? {
        guard balance >= Self.pinPrice, let i = ideas.firstIndex(where:{ $0.id == id }),
              ideas[i].section == .active, (ideas[i].pinnedUntil ?? .distantPast) <= now else { return nil }
        balance -= Self.pinPrice
        ideas[i].pinnedUntil = now.addingTimeInterval(30 * Self.day)
        return ideas[i]
    }
    mutating func restore(_ id:UUID) -> Idea? {
        guard let i = ideas.firstIndex(where:{ $0.id == id }), ideas[i].section == .archived else { return nil }
        ideas[i].archivedAt = nil
        return ideas[i]
    }
}

enum IdeaSection: String, CaseIterable, Identifiable {
    case active = "Активные"
    case completed = "Выполненные"
    case archived = "Архив"
    var id: Self { self }
}

enum NotebookFile {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path:"Thinkinbrain",directoryHint:.isDirectory)
            .appending(path:"ideas.json")
    }

    static func load(legacy:Data, at file:URL = url) throws -> Notebook {
        let bytes: Data
        do { bytes = try Data(contentsOf:file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            guard !legacy.isEmpty else { return Notebook() }
            let recovered = try JSONDecoder().decode(Notebook.self,from:legacy)
            try save(recovered,at:file)
            return recovered
        }
        return try JSONDecoder().decode(Notebook.self,from:bytes)
    }

    static func save(_ notebook:Notebook, at file:URL = url) throws {
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(notebook).write(to:file,options:.atomic)
    }

    static func clear() throws {
        do { try FileManager.default.removeItem(at:url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }
}

enum Page { case spark, editor, collection, settings }
struct Studio: View {
    @AppStorage("think.book.v1") private var legacyBook = Data()
    @AppStorage("think.avatar.v1") private var avatarData = Data()
    @State private var avatarOpen = false
    @AppStorage("think.draft.text") private var draft = ""
    @AppStorage("think.draft.step") private var draftStep = ""
    @State private var book = Notebook()
    @AppStorage("think.journal.v1") private var coverData = Data()
    @State private var cover: JournalCover?
    @State private var preparingNotebook = true
    @State private var editingCover = false
    @State private var page = Page.spark
    @State private var showRewards = false
    private enum RewardsDestination { case avatar, cover, ideas }
    @State private var rewardsDestination: RewardsDestination?
    @State private var confirmReset = false
    @State private var confirmPin = false
    @State private var section: IdeaSection = .active
    @State private var editing: Idea?
    @State private var text = ""
    @State private var bloom: Bloom?
    @State private var showFlowers = false
    @AppStorage("think.draft.bloom") private var draftBloom = ""
    @AppStorage("think.palette") private var paletteName = AppPalette.white.rawValue
    private var palette: AppPalette { AppPalette(rawValue:paletteName) ?? .white }
    @AppStorage("think.draft.flower") private var draftFlower = false
    @State private var listRequest = 0
    @State private var dismissRequest = 0
    @StateObject private var voice = Dictation()
    @State private var editorOrigin = Page.spark
    @State private var search = ""
    @State private var dayFilter: Date?
    @State private var yearFilter: Int?
    @State private var calendarDay = Date()
    @State private var calendarOpen = false
    @State private var detail: Idea?
    @State private var selectingIdeas = false
    @State private var selectedIdeas: Set<UUID> = []
    @State private var pendingDeletion: Set<UUID> = []
    @State private var confirmDeletion = false
    @State private var bookmarksOnly = false
    @State private var pastPage: Idea?
    @State private var lastPastPage: UUID?
    @State private var noPastPages = false
    @State private var pendingPastAddition: Idea?
    @State private var additionTarget: Idea?
    @State private var additionText = ""
    @FocusState private var addingText: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var storageError = false
    @State private var notebookLoaded = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var accent: Color { palette.accent }
    var body: some View {
        ZStack {
            if preparingNotebook {
                NotebookLoader(color:palette.ink).frame(maxWidth:.infinity,maxHeight:.infinity)
                    .background(palette.sheet.ignoresSafeArea())
            } else if cover == nil || editingCover {
                JournalSetup(existing:cover, balance:book.balance, ownedFinishes:book.ownedFinishes ?? [],
                             unlock:unlockFinish,onCancel:{ editingCover = false }) { newCover in
                    guard let encoded = try? JSONEncoder().encode(newCover) else { return }
                    coverData = encoded
                    cover = newCover
                    editingCover = false
                    noteVisit()
                }.environment(\.appPalette, cover == nil ? .white : palette)
                 .tint(cover == nil ? .white : palette.accent)
                 .transition(.opacity)
            } else if page == .collection { archive.transition(.opacity) }
            else if page == .editor { editor.transition(.opacity.combined(with: .offset(y: reduced ? 0 : 12))) }
            else if page == .settings { settings.transition(.opacity) }
            else { capture.transition(.opacity) }
        }
        .animation(reduced ? nil : .easeInOut(duration: 0.32), value: page)
        .animation(reduced ? nil : .easeInOut(duration:0.35),value:cover != nil && !editingCover)
        .edgeBack(enabled:!preparingNotebook && cover != nil && !editingCover && page != .spark,
                  action:stepBack)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge:.bottom,spacing:0) {
            if cover != nil && !editingCover && page != .editor { menu }
        }
        .buttonStyle(.plain)
        .tint(palette.accent)
        .task {
            guard preparingNotebook else { return }
            let notes = legacyBook
            let appearance = coverData
            let result = await Task.detached(priority:.userInitiated) {
                (Result { try NotebookFile.load(legacy:notes) }, JournalCover.decode(appearance))
            }.value
            cover = result.1
            switch result.0 {
            case .success(let loaded):
                book = loaded
                notebookLoaded = true
                if !notes.isEmpty { legacyBook = Data() }
            case .failure:
                storageError = true
            }
            preparingNotebook = false
            noteVisit()
        }
        .sheet(isPresented:$avatarOpen) {
            AvatarEditor(initial:profileAvatar ?? AvatarDesign(form:.eye),balance:book.balance,
                         ownedPupils:book.ownedPupils ?? [],unlock:unlockPupil) { design in
                if let saved = try? JSONEncoder().encode(design) { avatarData = saved }
            }
        }
        .alert("Не удалось открыть или сохранить коллекцию",isPresented:$storageError) {
            Button("Закрыть",role:.cancel) {}
        } message: { Text("Исходные записи сохранены на устройстве.") }
        .onChange(of:scenePhase) { _,phase in
            if phase == .active { noteVisit() }
            if phase == .background {
                voice.cancel()
                if cover != nil && notebookLoaded && !storageError && book.lastSeen != nil {
                    var next = book
                    next.lastSeen = Date()
                    _ = persist(next)
                }
            }
        }
        .alert("Голосовая запись", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) {
            Button("Закрыть") { voice.error = nil }
        } message: { Text(voice.error ?? "") }
        .sheet(isPresented:$showFlowers) { flowers }
        .sheet(item:$pastPage,onDismiss:{
            if let idea = pendingPastAddition {
                pendingPastAddition = nil
                additionText = ""
                additionTarget = idea
            }
        }) { past in previousPageSheet(past).edgeBack { pastPage = nil } }
        .sheet(item:$additionTarget) { idea in
            additionSheet(idea).edgeBack { additionTarget = nil }
        }
        .alert("Из прошлых страниц",isPresented:$noPastPages) {
            Button("Понятно",role:.cancel) {}
        } message: { Text("Здесь будут появляться идеи, записанные в предыдущие дни.") }
        .sheet(isPresented:$showRewards,onDismiss:openRewardsDestination) {
            rewards.edgeBack { showRewards = false }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .font(.body.monospaced())
        .foregroundStyle(palette.ink).environment(\.appPalette,palette)
    }
    private var profileAvatar: AvatarDesign? {
        try? JSONDecoder().decode(AvatarDesign.self,from:avatarData)
    }

    private func stepBack() {
        switch page {
        case .editor:
            voice.cancel()
            dismissRequest += 1
            page = editorOrigin
        case .collection where detail != nil: detail = nil
        case .collection where selectingIdeas: endSelection()
        case .collection,.settings: page = .spark
        case .spark: break
        }
    }

    private func persist(_ next: Notebook) -> Bool {
        guard notebookLoaded else { storageError = true; return false }
        do {
            try NotebookFile.save(next)
            book = next
            return true
        } catch {
            storageError = true
            return false
        }
    }
    private func noteVisit() {
        guard cover != nil, notebookLoaded, !storageError else { return }
        var next = book
        next.resume(at:Date())
        _ = persist(next)
    }

    private func resetApp() {
        voice.cancel()
        do { try NotebookFile.clear() } catch { storageError = true; return }
        legacyBook = Data()
        coverData = Data()
        avatarData = Data()
        notebookLoaded = true
        draft = ""; draftStep = ""; draftBloom = ""; draftFlower = false
        paletteName = AppPalette.white.rawValue
        UserDefaults.standard.removeObject(forKey:"think.draft.audio")
        let voiceDirectory = URL.applicationSupportDirectory.appending(path:"ThinkVoice",directoryHint:.isDirectory)
        try? FileManager.default.removeItem(at:voiceDirectory)
        book = Notebook(); cover = nil; page = .spark; editingCover = false; storageError = false
        editing = nil; detail = nil; text = ""; bloom = nil
        search = ""; dayFilter = nil; yearFilter = nil; section = .active
        bookmarksOnly = false; lastPastPage = nil; additionText = ""
        endSelection(); pendingDeletion.removeAll()
    }

    private func resolveIdea(_ id:UUID,change:(inout Notebook,UUID) -> Idea?) {
        var next = book
        guard let updated = change(&next,id), persist(next) else { return }
        detail = updated
        section = updated.section
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        if editing != nil { detail = idea } else { detail = nil; section = .active; bookmarksOnly = false; search = ""; dayFilter = nil; yearFilter = nil }
        page = .collection
    }
    private var capture: some View {
        VStack(spacing:0) {
            HStack(spacing:9) {
                SparkShape().fill(palette.ink).frame(width:17,height:17)
                Text("thinkinbrain").font(.system(size:15,weight:.semibold)).tracking(0.15)
            }.foregroundStyle(palette.ink).frame(height:52)
            Spacer(minLength:4)
            if let cover {
                JournalModel(cover:cover,onTap:{
                    UIImpactFeedbackGenerator(style:.soft).impactOccurred()
                    begin()
                },onHold:openPastPage,autoRotate:true).frame(maxWidth:330).frame(height:344)
            }
            Button(action:openPastPage) {
                Label("Из прошлых страниц",systemImage:"book")
                    .font(.footnote.monospaced()).frame(minHeight:44)
            }.foregroundStyle(palette.ink.opacity(0.76))
            Spacer(minLength:12)
        }.frame(maxWidth:.infinity)
         .background(palette.sheet.ignoresSafeArea())
    }

    private var menu: some View {
        HStack(spacing:4) {
            menuTab(.spark, title:"Главная") {
                SparkShape().fill(palette.ink)
                    .frame(width:25,height:25)
                    .opacity(page == .spark ? 1 : 0.62)
            }
            menuTab(.collection, title:"Мои идеи") {
                Image(systemName:"books.vertical")
                    .font(.system(size:22,weight:page == .collection ? .semibold : .regular))
                    .foregroundStyle(palette.ink.opacity(page == .collection ? 1 : 0.62))
            }
            Button {
                showRewards = true
            } label: {
                HStack(spacing:4) {
                    Image(systemName:"star.fill").font(.system(size:9,weight:.semibold))
                    Text(book.balance,format:.number).font(.footnote.weight(.semibold).monospaced())
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
                .padding(.horizontal,7).frame(minWidth:34,minHeight:32)
                .foregroundStyle(palette.sheet)
                .background(palette.ink,in:RoundedRectangle(cornerRadius:6))
                .padding(.horizontal,2)
                .frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle())
            }.accessibilityLabel("Звёзды").accessibilityValue(Text(book.balance,format:.number))
            menuTab(.settings, title:"Профиль и настройки") {
                Group {
                    if let design = profileAvatar { ProfileAvatar(design:design,animated:true).padding(2) }
                    else { Text(profileInitial).font(.footnote.weight(.medium).monospaced()) }
                }.lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(palette.ink)
                    .frame(width:34,height:34)
                    .background(palette.card,in:Circle())
                    .overlay {
                        Circle().strokeBorder(palette.ink.opacity(page == .settings ? 0.65 : 0.12))
                    }
            }
        }.padding(.horizontal,18).padding(.vertical,5)
         .background(palette.sheet.ignoresSafeArea(edges:.bottom))
    }

    private var profileInitial: String {
        guard let initial = cover?.title.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(initial).uppercased()
    }

    private func menuTab<Icon: View>(_ tab:Page,title:String,@ViewBuilder icon:() -> Icon) -> some View {
        Button {
            if tab != page { endSelection(); detail = nil; page = tab }
        } label: {
            icon().frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle())
        }.accessibilityLabel(title)
         .accessibilityAddTraits(page == tab ? .isSelected : [])
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("Профиль и настройки").font(.title2.bold().monospaced())
                Button { avatarOpen = true } label: {
                    HStack(spacing:12) {
                        if let design = profileAvatar {
                            ProfileAvatar(design:design).frame(width:52,height:52)
                        } else {
                            Image(systemName:"person.crop.circle").font(.system(size:30))
                                .frame(width:52,height:52)
                        }
                        Text(profileAvatar == nil ? "Создать аватар" : "Изменить аватар")
                        Spacer()
                        Image(systemName:"chevron.right").font(.caption)
                    }.padding(12).background(palette.card,in:RoundedRectangle(cornerRadius:16))
                }
                if let cover {
                    Button { editingCover = true } label: {
                        HStack(spacing:16) {
                            JournalModel(cover:cover).frame(width:60,height:74)
                                .frame(width:58,height:74).allowsHitTesting(false).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:5) {
                                Text(cover.title).font(.headline.monospaced()).lineLimit(2)
                                Text("Название и обложка").font(.subheadline.monospaced()).foregroundStyle(palette.muted)
                            }
                            Spacer()
                            Image(systemName:"chevron.right").font(.caption.monospaced()).foregroundStyle(palette.muted)
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
                            Image(systemName:"chevron.right").font(.caption.monospaced()).foregroundStyle(palette.muted)
                        }.padding(17)
                    }
                }.background(palette.card,in:RoundedRectangle(cornerRadius:20))
                Button(role:.destructive) { confirmReset = true } label: {
                    Label("Сбросить приложение",systemImage:"arrow.counterclockwise")
                        .frame(maxWidth:.infinity,alignment:.leading).padding(17)
                        .foregroundStyle(palette.ink).background(palette.card,in:RoundedRectangle(cornerRadius:20))
                }
            }.padding(22)
        }.foregroundStyle(palette.ink).background(palette.sheet.ignoresSafeArea())
         .confirmationDialog("Сбросить приложение?",isPresented:$confirmReset,titleVisibility:.visible) {
             Button("Удалить данные и начать заново",role:.destructive,action:resetApp)
             Button("Отмена",role:.cancel) {}
         } message: { Text("Дневник, идеи, черновик и звёзды будут удалены с этого устройства.") }
    }
    private var paletteSettings: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Цвет приложения").font(.headline.monospaced())
            LazyVGrid(columns:[GridItem(.adaptive(minimum:66),spacing:10)],spacing:13) {
                ForEach(AppPalette.allCases) { option in
                    let selected = option == palette
                    Button {
                        paletteName = option.rawValue
                    } label: {
                        VStack(spacing:6) {
                            Circle().fill(option.accent).frame(width:29,height:29)
                                .overlay { if selected { Image(systemName:"checkmark").font(.caption.bold().monospaced()).foregroundStyle(palette.sheet) } }
                            Text(option.name).font(.caption2.monospaced()).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth:.infinity,minHeight:54)
                    }.accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }.padding(16).background(palette.card,in:RoundedRectangle(cornerRadius:20))
    }

    private var flowers: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Цветок идеи").font(.title2.bold().monospaced())
                LazyVGrid(columns:[GridItem(.adaptive(minimum:85),spacing:10)],spacing:12) {
                    ForEach(Bloom.allCases) { option in
                        Button { chooseFlower(option) } label: {
                            VStack(spacing:5) {
                                Flower(kind:option).frame(width:36,height:52)
                                Text(option.name).font(.caption.monospaced()).lineLimit(1)
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
                Button(action:stepBack) {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Назад")
                Spacer()
                Text(editing == nil ? "Новая мысль" : "Редактирование").font(.subheadline.monospaced()).foregroundStyle(palette.muted)
                Spacer()
                Button("Готово",action:save).font(.subheadline.weight(.semibold).monospaced()).padding(.vertical,3)
                    .frame(minHeight:44).foregroundStyle(palette.accent)
                    .disabled(voice.waiting || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if let bloom { Flower(kind:bloom).frame(width:42,height:58).frame(maxWidth:.infinity) }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text(voice.listening ? "Слушаю…" : "О чём ты думаешь?").foregroundStyle(palette.muted).padding(.top,8).padding(.leading,5).allowsHitTesting(false) }
                IdeaTextView(text:$text,listRequest:listRequest,dismissRequest:dismissRequest) { voice.cancel() }
            }.font(.system(.title2,design:.monospaced))
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
    private func unlockPupil(_ pupil:EyePupil) -> Bool {
        var next = book
        if next.owns(pupil) { return true }
        return next.unlockPupil(pupil) && persist(next)
    }

    private func unlockFinish(_ finish:CoverFinish) -> Bool {
        var next = book
        if next.owns(finish) { return true }
        return next.unlock(finish) && persist(next)
    }

    private func openPastPage() {
        let today = Calendar.current.startOfDay(for:Date())
        let earlier = book.ideas.filter { $0.created < today }
        guard let idea = (earlier.filter { $0.id != lastPastPage }.randomElement() ?? earlier.first) else {
            noPastPages = true
            return
        }
        lastPastPage = idea.id
        pastPage = idea
    }

    private func previousPageSheet(_ idea:Idea) -> some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("Из прошлых страниц").font(.headline.monospaced())
                Spacer()
                Button { pastPage = nil } label: {
                    Image(systemName:"xmark").frame(width:44,height:44)
                }.accessibilityLabel("Закрыть")
            }
            Text(idea.created,format:.dateTime.day().month(.wide).year())
                .font(.caption.monospaced()).foregroundStyle(palette.muted)
            ScrollView {
                Text(idea.text.isEmpty ? idea.step : idea.text)
                    .font(.title3.monospaced()).frame(maxWidth:.infinity,alignment:.leading)
            }
            Button("Дополнить") {
                detail = idea
                section = idea.section
                page = .collection
                pendingPastAddition = idea
                pastPage = nil
            }.buttonStyle(JournalPrimary())
        }.padding(24).presentationDetents([.medium,.large])
         .presentationBackground(palette.sheet).foregroundStyle(palette.ink)
         .environment(\.locale,Locale(identifier:"ru"))
    }

    private func additionSheet(_ idea:Idea) -> some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Button("Отмена") { additionTarget = nil }.frame(minHeight:44)
                Spacer()
                Button("Сохранить") { saveAddition(for:idea.id) }
                    .frame(minHeight:44)
                    .disabled(additionText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            Text("Дополнение").font(.title2.monospaced())
            Text(Date(),format:.dateTime.day().month(.wide).year())
                .font(.caption.monospaced()).foregroundStyle(palette.muted)
            TextEditor(text:$additionText)
                .font(.body.monospaced()).scrollContentBackground(.hidden).padding(8)
                .background(palette.card,in:RoundedRectangle(cornerRadius:12))
                .focused($addingText).accessibilityLabel("Текст дополнения")
        }.padding(22).foregroundStyle(palette.ink).presentationBackground(palette.sheet)
         .environment(\.locale,Locale(identifier:"ru"))
         .onAppear { addingText = true }
    }

    private func saveAddition(for id:UUID) {
        let words = additionText.trimmingCharacters(in:.whitespacesAndNewlines)
        var next = book
        guard !words.isEmpty, let index = next.ideas.firstIndex(where:{ $0.id == id }) else { return }
        next.ideas[index].additions = (next.ideas[index].additions ?? []) +
            [IdeaAddition(id:UUID(),created:Date(),text:words)]
        guard persist(next) else { return }
        detail = next.ideas[index]
        additionTarget = nil
        additionText = ""
    }

    private func toggleBookmark(_ idea:Idea) {
        var next = book
        guard let index = next.ideas.firstIndex(where:{ $0.id == idea.id }) else { return }
        next.ideas[index].bookmarked = next.ideas[index].bookmarked != true
        if persist(next) { detail = next.ideas[index] }
    }

    private var visibleIdeas: [Idea] {
        book.ideas.filter { bookmarksOnly ? $0.bookmarked == true : $0.section == section }
    }

    private var journalDays: [(key: Date, value: [Idea])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = visibleIdeas.filter { idea in
            let calendar = Calendar.current
            let dayMatches = dayFilter.map { calendar.isDate($0,inSameDayAs:idea.created) } ?? true
            let yearMatches = yearFilter.map { calendar.component(.year,from:idea.created) == $0 } ?? true
            return dayMatches && yearMatches && (query.isEmpty || ([idea.text, idea.step, idea.audio == nil ? "" : "Голосовая запись"] + (idea.additions ?? []).map(\.text))
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        return Dictionary(grouping: matches.sorted { $0.created > $1.created }) {
            Calendar.current.startOfDay(for: $0.created)
        }.sorted { $0.key > $1.key }
    }
    private func endSelection() {
        selectingIdeas = false
        selectedIdeas.removeAll()
    }

    private func requestDeletion(_ ids:Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeletion = ids
        confirmDeletion = true
    }

    private func deleteIdeas() {
        let ids = pendingDeletion
        guard !ids.isEmpty else { return }
        var next = book
        next.ideas.removeAll { ids.contains($0.id) }
        guard persist(next) else { return }
        if let detail, ids.contains(detail.id) { self.detail = nil }
        pendingDeletion.removeAll()
        endSelection()
    }

    private var archive: some View {
        let sections = journalDays
        return VStack(alignment: .leading, spacing: 14) {
            if detail != nil {
                Button { detail = nil } label: {
                    Label("Все идеи",systemImage:"chevron.left").frame(minHeight:44)
                }.foregroundStyle(palette.muted)
            }
            if let idea = detail {
                HStack {
                    Text("Идея").font(.largeTitle.bold().monospaced())
                    Spacer()
                    Button { toggleBookmark(idea) } label: {
                        Image(systemName:idea.bookmarked == true ? "bookmark.fill" : "bookmark")
                            .frame(width:44,height:44)
                    }.accessibilityLabel(idea.bookmarked == true ? "Убрать закладку" : "Добавить закладку")
                    Button(role:.destructive) { requestDeletion([idea.id]) } label: {
                        Image(systemName:"trash").frame(width:44,height:44)
                    }.accessibilityLabel("Удалить идею")
                }
                ScrollView(showsIndicators:false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if let decoration = idea.decoration { Flower(kind:decoration).frame(width:42,height:58).frame(maxWidth:.infinity) }
                        Text("Дата создания").font(.caption.monospaced()).foregroundStyle(palette.accent)
                        Text(idea.created, format: .dateTime.day().month(.wide).year().hour().minute()).font(.subheadline.monospaced())
                        Divider()
                        Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                            .font(.system(.title3,design:.monospaced)).textSelection(.enabled)
                        if !idea.step.isEmpty { Text(idea.step) }
                        ForEach(idea.additions ?? []) { addition in
                            Divider()
                            Text(addition.created,format:.dateTime.day().month(.wide).year().hour().minute())
                                .font(.caption.monospaced()).foregroundStyle(palette.muted)
                            Text(addition.text).font(.title3.monospaced()).textSelection(.enabled)
                        }
                        Button {
                            additionText = ""
                            additionTarget = idea
                        } label: {
                            Label("Дополнить",systemImage:"plus").frame(minHeight:44)
                        }.foregroundStyle(palette.accent)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(22)
                     .foregroundStyle(palette.ink).background(palette.card,in:RoundedRectangle(cornerRadius:8))
                }
                ideaActions(idea)
            } else {
                let canSelect = !sections.isEmpty && !selectingIdeas
                HStack(spacing:8) {
                    Color.clear.frame(width:canSelect ? 96 : 44,height:44)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    Button {
                        calendarDay = dayFilter ?? yearFilter.flatMap { year in
                            Calendar.current.date(from:DateComponents(year:year,month:1,day:1))
                        } ?? Date()
                        calendarOpen = true
                    } label: {
                        Label("Календарь",systemImage:"calendar")
                            .font(.subheadline.weight(.medium).monospaced())
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(minHeight:44)
                    }.foregroundStyle(palette.accent).frame(maxWidth:.infinity)
                    HStack(spacing:8) {
                        Button {
                            bookmarksOnly.toggle()
                            dayFilter = nil
                            yearFilter = nil
                        } label: {
                            Image(systemName:bookmarksOnly ? "bookmark.fill" : "bookmark")
                                .frame(width:44,height:44)
                                .background(palette.card,in:RoundedRectangle(cornerRadius:9))
                        }.accessibilityLabel(bookmarksOnly ? "Показать все идеи" : "Показать закладки")
                         .accessibilityAddTraits(bookmarksOnly ? .isSelected : [])
                        if canSelect {
                            Button { selectingIdeas = true } label: {
                                Image(systemName:"checkmark.circle").frame(width:44,height:44)
                                    .background(palette.card,in:RoundedRectangle(cornerRadius:9))
                            }.accessibilityLabel("Выбрать идеи")
                        }
                    }
                }
                if let dayFilter {
                    Button { self.dayFilter = nil } label: {
                        HStack { Text(dayFilter,format:.dateTime.day().month(.wide).year()); Image(systemName:"xmark") }
                    }.foregroundStyle(palette.accent).accessibilityHint("Показать все даты")
                } else if let yearFilter {
                    Button { self.yearFilter = nil } label: {
                        Label(String(yearFilter),systemImage:"xmark")
                    }.foregroundStyle(palette.accent).accessibilityHint("Показать все даты")
                }
                if !book.ideas.isEmpty {
                    HStack {
                        Image(systemName:"magnifyingglass").foregroundStyle(palette.muted)
                        TextField("Поиск по идеям",text:$search,prompt:Text("Поиск по идеям").foregroundStyle(palette.muted)).font(.subheadline.monospaced()).submitLabel(.search)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Очистить поиск") }
                    }.padding(.horizontal,14).frame(minHeight:44).background(palette.card,in:RoundedRectangle(cornerRadius:12))
                }
                if bookmarksOnly {
                    Text("Закладки").font(.headline.monospaced())
                } else {
                    HStack(spacing:4) {
                        ForEach(IdeaSection.allCases) { option in
                            Button { section = option } label: {
                                Text(option.rawValue)
                                    .font(.footnote.weight(section == option ? .semibold : .regular).monospaced())
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                    .padding(.horizontal,4).frame(maxWidth:.infinity,minHeight:44)
                                    .background(palette.accent.opacity(section == option ? 0.18 : 0),
                                                in:RoundedRectangle(cornerRadius:8))
                                    .contentShape(Rectangle())
                            }.accessibilityAddTraits(section == option ? .isSelected : [])
                        }
                    }.padding(4).background(palette.card,in:RoundedRectangle(cornerRadius:12))
                     .accessibilityElement(children:.contain).accessibilityLabel("Состояние идей")
                }
                ScrollView(showsIndicators:false) {
                    LazyVStack(alignment:.leading,spacing:12) {
                        if sections.isEmpty {
                            Text(emptyIdeasMessage)
                                .foregroundStyle(palette.muted).padding(.vertical,24)
                        }
                        ForEach(sections,id:\.key) { section in
                            Text(section.key,format:.dateTime.day().month(.wide).year()).font(.footnote.weight(.semibold).monospaced()).padding(.top,8)
                            ForEach(section.value) { idea in
                                Button {
                                    if selectingIdeas {
                                        if selectedIdeas.contains(idea.id) { selectedIdeas.remove(idea.id) }
                                        else { selectedIdeas.insert(idea.id) }
                                    } else { detail = idea }
                                } label: {
                                    HStack(spacing:12) {
                                        VStack(alignment:.leading,spacing:8) {
                                            HStack {
                                                if let decoration = idea.decoration { Flower(kind:decoration).frame(width:13,height:19) }
                                                Image(systemName:idea.audio == nil ? "text.alignleft" : "waveform")
                                                Text(idea.audio == nil ? "Текст" : "Голос")
                                                Text("·")
                                                Text(idea.created,style:.time)
                                                if idea.bookmarked == true { Image(systemName:"bookmark.fill").accessibilityLabel("В закладках") }
                                                if idea.section == .active, let date = idea.pinnedUntil, date > Date() {
                                                    Image(systemName:"pin.fill").accessibilityLabel("Закреплена")
                                                }
                                            }.font(.caption.monospaced()).foregroundStyle(palette.ink.opacity(0.7))
                                            Text(idea.text.isEmpty ? "Идея без текста" : idea.text)
                                                .font(.body.monospaced()).lineLimit(3)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:selectingIdeas
                                              ? (selectedIdeas.contains(idea.id) ? "checkmark.circle.fill" : "circle")
                                              : "chevron.right")
                                            .font(.system(size:selectingIdeas ? 22 : 15))
                                            .foregroundStyle(palette.accent)
                                    }.multilineTextAlignment(.leading).padding(16).foregroundStyle(palette.ink)
                                     .background(palette.card,in:RoundedRectangle(cornerRadius:17))
                                     .overlay { RoundedRectangle(cornerRadius:17).strokeBorder(palette.ink.opacity(0.06)).allowsHitTesting(false) }
                                }.accessibilityAddTraits(selectedIdeas.contains(idea.id) ? .isSelected : [])
                                 .contextMenu {
                                     if !selectingIdeas {
                                         Button(role:.destructive) { requestDeletion([idea.id]) } label: {
                                             Label("Удалить",systemImage:"trash")
                                         }
                                     }
                                 }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                if selectingIdeas {
                    HStack {
                        Button("Отмена",action:endSelection).frame(minHeight:44)
                        Spacer()
                        Button(role:.destructive) { requestDeletion(selectedIdeas) } label: {
                            Label("Удалить · \(selectedIdeas.count)",systemImage:"trash").frame(minHeight:44)
                        }.disabled(selectedIdeas.isEmpty)
                    }.font(.subheadline.monospaced())
                }
            }
        }.buttonStyle(.plain).padding(.horizontal,22).padding(.bottom,8)
         .onChange(of:sections.flatMap { $0.value.map(\.id) }) { _,visible in
             selectedIdeas.formIntersection(visible)
         }
         .alert("Удалить идеи?",isPresented:$confirmDeletion) {
             Button("Удалить",role:.destructive,action:deleteIdeas)
             Button("Отмена",role:.cancel) { pendingDeletion.removeAll() }
         } message: {
             Text(pendingDeletion.count == 1 ? "Идея и её дополнения будут удалены." :
                  "Выбрано идей: \(pendingDeletion.count). Они будут удалены вместе с дополнениями.")
         }
         .foregroundStyle(palette.ink).background(palette.sheet.ignoresSafeArea())
         .environment(\.locale,Locale(identifier:"ru"))
         .sheet(isPresented:$calendarOpen) {
             IdeaCalendar(selection:$calendarDay,
                          recorded:Set(visibleIdeas.map { Calendar.current.startOfDay(for:$0.created) }),
                          startsWithYear:yearFilter != nil,
                          applyDay:{ dayFilter = calendarDay; yearFilter = nil; calendarOpen = false },
                          applyYear:{ yearFilter = $0; dayFilter = nil; calendarOpen = false },
                          reset:{ dayFilter = nil; yearFilter = nil; calendarOpen = false })
         }
    }
    private var emptyIdeasMessage: String {
        if !search.isEmpty || dayFilter != nil || yearFilter != nil { return "За выбранный период ничего не найдено." }
        if bookmarksOnly { return "Отмечай идеи ленточкой, чтобы быстро к ним вернуться." }
        switch section {
        case .active: return "Здесь появятся твои идеи. Начни с первой записи."
        case .completed: return "Здесь будут идеи, которые ты выполнил."
        case .archived: return "Архив пуст."
        }
    }

    private func ideaActions(_ idea:Idea) -> some View {
        VStack(spacing:8) {
            if idea.section == .active {
                Button {
                    resolveIdea(idea.id) { $0.complete($1,at:Date()) }
                } label: {
                    Label("Выполнить · +\(Notebook.completionReward) ★",systemImage:"checkmark.circle")
                }.buttonStyle(JournalPrimary())

                if let until = idea.pinnedUntil, until > Date() {
                    Label { Text(until,format:.dateTime.day().month(.wide).year()) } icon: { Image(systemName:"pin.fill") }
                        .font(.subheadline.monospaced()).foregroundStyle(palette.muted)
                        .accessibilityLabel("Закреплена до \(until.formatted(date:.long,time:.omitted))")
                } else {
                    Button { confirmPin = true } label: {
                        Label("Закрепить на 30 дней · \(Notebook.pinPrice) ★",systemImage:"pin")
                            .frame(minHeight:44)
                    }.disabled(book.balance < Notebook.pinPrice)
                     .opacity(book.balance < Notebook.pinPrice ? 0.45 : 1)
                }
            } else if idea.section == .archived {
                Button("Вернуть в активные") { resolveIdea(idea.id) { $0.restore($1) } }
                    .buttonStyle(JournalPrimary())
            } else if let completedAt = idea.completedAt {
                Label { Text(completedAt,format:.dateTime.day().month(.wide).year()) } icon: { Image(systemName:"checkmark.circle") }
                    .foregroundStyle(palette.muted).accessibilityLabel("Выполнено \(completedAt.formatted(date:.long,time:.omitted))")
            }
            Button { begin(idea) } label: {
                Label("Редактировать",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:44)
            }.foregroundStyle(palette.accent)
        }.confirmationDialog("Закрепить идею?",isPresented:$confirmPin,titleVisibility:.visible) {
            Button("Потратить \(Notebook.pinPrice) звёзд") { resolveIdea(idea.id) { $0.pin($1,at:Date()) } }
            Button("Отмена",role:.cancel) {}
        } message: { Text("Идея останется в активных 30 дней, даже если ты не будешь заходить.") }
    }

    private func goFromRewards(to destination:RewardsDestination) {
        rewardsDestination = destination
        showRewards = false
    }

    private func openRewardsDestination() {
        defer { rewardsDestination = nil }
        switch rewardsDestination {
        case .avatar: page = .settings; avatarOpen = true
        case .cover: page = .settings; editingCover = true
        case .ideas: detail = nil; page = .collection
        case nil: break
        }
    }

    private var rewards: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    Text("Звёзды").font(.title2.bold().monospaced())
                    Spacer()
                    Button { showRewards = false } label: {
                        Image(systemName:"xmark").frame(width:44,height:44)
                    }.accessibilityLabel("Закрыть")
                }
                VStack(alignment:.leading,spacing:7) {
                    Text("Твой баланс").font(.subheadline.monospaced()).foregroundStyle(palette.muted)
                    HStack(spacing:13) {
                        SparkShape().fill(accent).frame(width:27,height:27)
                        Text(book.balance,format:.number).font(.system(.largeTitle,design:.monospaced,weight:.semibold))
                    }.accessibilityLabel("\(book.balance) звёзд")
                }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
                 .background(palette.card,in:RoundedRectangle(cornerRadius:14))

                VStack(alignment:.leading,spacing:11) {
                    Text("Как заработать").font(.headline.monospaced())
                    rewardRow("Записать идею","1 ★ за запись, 2 ★ от 80 знаков, 3 ★ от 200.","+1–3 ★")
                    Divider()
                    rewardRow("Выполнить идею","Отметь идею выполненной.","+\(Notebook.completionReward) ★")
                }
                VStack(alignment:.leading,spacing:11) {
                    Text("На что потратить").font(.headline.monospaced())
                    Button { goFromRewards(to:.ideas) } label: {
                        rewardRow("Закрепить идею","На 30 дней. Закрепление включается внутри идеи.","\(Notebook.pinPrice) ★")
                    }
                    Divider()
                    Button { goFromRewards(to:.cover) } label: {
                        rewardRow("Фактуры обложки","Лён 8 ★ · Матовая бумага 12 ★ · Тиснение 18 ★","от 8 ★")
                    }
                    Divider()
                    Button { goFromRewards(to:.avatar) } label: {
                        rewardRow("Зрачки аватара","Алый вихрь 12 ★ · Двойной 16 ★ · Звёздный 20 ★","от 12 ★")
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(24)
        }.buttonStyle(.plain).presentationBackground(palette.sheet)
    }

    private func rewardRow(_ title:String,_ detail:String,_ value:String) -> some View {
        HStack(alignment:.top,spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.subheadline.weight(.medium).monospaced())
                Text(detail).font(.caption.monospaced()).foregroundStyle(palette.ink.opacity(0.68))
            }.frame(maxWidth:.infinity,alignment:.leading)
            Text(value).font(.caption.weight(.semibold).monospaced()).fixedSize()
                .padding(.horizontal,8).padding(.vertical,6)
                .background(palette.card,in:Capsule())
        }.multilineTextAlignment(.leading).padding(.vertical,5).contentShape(Rectangle())
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
                        update(self.phrases.receive(words,start:from,end:until,at:ProcessInfo.processInfo.systemUptime,closing:final || !self.listening))
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
                .background(active ? palette.accent.opacity(0.13) : .clear,in:Circle())
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
        v.font = UIFontMetrics(forTextStyle:.title2).scaledFont(for:UIFont.monospacedSystemFont(ofSize:21,weight:.regular))
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
        let accepted = tokens(value)
        let committed = tokens(frozen)
        let shifted = start >= previousEnd - 0.04 && start > (firstTime ?? start)+0.18
        let clockReset = end + 0.1 < previousEnd
        let quiet = now - (lastEvent ?? now) > 1.0

        // A recognizer can replay an older, shorter hypothesis, even as its final result.
        if !shifted && incoming.count < accepted.count {
            let isStaleSuffix = accepted.suffix(incoming.count).elementsEqual(incoming)
            if incoming != previous && (accepted.starts(with:incoming) || isStaleSuffix) {
                return value
            }
            let replaysFrozen = !committed.isEmpty && incoming.starts(with:committed)
            let revisitsCurrent = abs(start - (firstTime ?? start)) <= 0.18 && end <= previousEnd + 0.04
                && incoming.first == previous.first && incoming.count < previous.count
            if replaysFrozen || revisitsCurrent { return value }
        }

        if !committed.isEmpty && incoming.starts(with:committed) && incoming.count > committed.count {
            frozen = ""
            current = words
            firstTime = start
            previousEnd = end
            lastEvent = now
            return value
        }
        if closing && !shifted && incoming.count < previous.count && end <= previousEnd + 0.04 {
            return value
        }
        let separate = start > previousEnd + 0.08 && shifted
        let extended = !separate && incoming.starts(with:previous)
        let overlap = separate ? 0 : suffixOverlap(previous,incoming)
        let beginsInsideCurrent = start > (firstTime ?? start) + 0.18 && overlap > 0
        if !current.isEmpty && !extended &&
            (shifted || beginsInsideCurrent || quiet && (clockReset || incoming.first != previous.first)) {
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

struct JournalCover: Codable, Equatable {
    static func decode(_ data:Data) -> Self? {
        guard let cover = try? JSONDecoder().decode(Self.self,from:data),
              colors.indices.contains(cover.shade), !cover.title.isEmpty else { return nil }
        return cover
    }

    var title = ""
    var shade = 0
    var photo: Data?
    var finish: CoverFinish? = nil
    var surface: CoverFinish { finish ?? .classic }

    static let colors: [Color] = [
        Color(red:0.28,green:0.28,blue:0.30), Color(red:0.37,green:0.22,blue:0.22),
        Color(red:0.23,green:0.33,blue:0.30), Color(red:0.23,green:0.29,blue:0.42),
        Color(red:0.47,green:0.39,blue:0.28)
    ]
    static let names = ["Графит", "Бордо", "Шалфей", "Индиго", "Песок"]
}

struct NotebookFace: View {
    let cover: JournalCover
    private static let colorContext = CIContext()
    var body: some View {
        let photo = cover.photo.flatMap { UIImage(data:$0) }
        ZStack(alignment:.leading) {
            JournalCover.colors[cover.shade]
            if let photo {
                Image(uiImage:photo).resizable().scaledToFill().frame(width:182,height:258).clipped()
            }
            coverGrain
            if cover.surface == .embossed {
                RoundedRectangle(cornerRadius:8).strokeBorder(.black.opacity(0.38),lineWidth:1.5)
                    .padding(11).offset(y:1)
                RoundedRectangle(cornerRadius:8).strokeBorder(.white.opacity(0.29),lineWidth:1)
                    .padding(11)
                SparkShape().stroke(.white.opacity(0.32),lineWidth:0.7)
                    .frame(width:25,height:25).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
                    .padding(.bottom,24)
            }
            LinearGradient(colors:[.white.opacity(0.09),.clear,.black.opacity(0.13)],
                           startPoint:.topLeading,endPoint:.bottomTrailing)
            if !cover.title.isEmpty {
                Text(cover.title).font(.system(size:21,weight:.medium,design:.monospaced))
                    .lineLimit(3).minimumScaleFactor(0.60).multilineTextAlignment(.center).tracking(0.4).foregroundStyle(printedInk(on:photo))
                    .padding(.horizontal,19).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).padding(.top,40)
            }
        }.frame(width:182,height:258)
         .clipped()
    }

    private func printedInk(on photo:UIImage?) -> Color {
        let lightInk = Color(white:0.94)
        guard let photo, let image = CIImage(image:photo), !image.extent.isEmpty else { return lightInk }
        let bounds = image.extent
        let scale = max(182 / bounds.width,258 / bounds.height)
        // Sample behind the title after the centered, aspect-fill cover crop.
        let sample = CGRect(x:bounds.midX - 66 / scale,y:bounds.midY + 20 / scale,
                            width:132 / scale,height:67 / scale)
        let average = CIFilter.areaAverage()
        average.inputImage = image
        average.extent = sample
        guard let color = average.outputImage,
              let space = CGColorSpace(name:CGColorSpace.sRGB) else { return lightInk }
        var rgba = [UInt8](repeating:0,count:4)
        rgba.withUnsafeMutableBytes { pixels in
            guard let bytes = pixels.baseAddress else { return }
            Self.colorContext.render(color,toBitmap:bytes,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),
                                     format:.RGBA8,colorSpace:space)
        }
        let brightness = 0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])
        return brightness > 145 ? Color(white:0.12) : lightInk
    }

    private var coverGrain: some View {
        Canvas { context,size in
            var texture = Path()
            switch cover.surface {
            case .linen:
                for x in stride(from:0.0,to:size.width,by:2.1) {
                    texture.move(to:CGPoint(x:x,y:0))
                    texture.addLine(to:CGPoint(x:x+0.6,y:size.height))
                }
                for y in stride(from:0.0,to:size.height,by:2.9) {
                    texture.move(to:CGPoint(x:0,y:y))
                    texture.addLine(to:CGPoint(x:size.width,y:y+0.3))
                }
                context.stroke(texture,with:.color(.white.opacity(0.15)),lineWidth:0.55)
                context.translateBy(x:0.7,y:0.7)
                context.stroke(texture,with:.color(.black.opacity(0.20)),lineWidth:0.55)
            case .paper:
                for i in 0..<2100 {
                    let x = Double((i * 83) % 997) / 997 * size.width
                    let y = Double((i * 149) % 991) / 991 * size.height
                    texture.addEllipse(in:CGRect(x:x,y:y,width:0.8,height:0.55))
                }
                context.fill(texture,with:.color(.white.opacity(0.22)))
            case .classic,.embossed: break
            }
        }.accessibilityHidden(true)
    }
}

enum CoverStage { case intro, title, cover }

struct JournalSetup: View {
    @Environment(\.appPalette) private var palette
    let existing: JournalCover?
    let balance: Int
    let ownedFinishes: Set<CoverFinish>
    let unlock: (CoverFinish) -> Bool
    let onCancel: () -> Void
    let onSave: (JournalCover) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var stage: CoverStage
    @State private var cover: JournalCover
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var photoError = false
    @State private var finishesOpen = false
    @State private var previewFinish: CoverFinish = .classic
    @State private var purchaseConfirmation = false
    @State private var unlockedHere: Set<CoverFinish> = []
    @State private var leaving = false
    @State private var promptVisible = false
    @FocusState private var typing: Bool

    init(existing: JournalCover?, balance:Int, ownedFinishes:Set<CoverFinish>, unlock:@escaping (CoverFinish) -> Bool,
         onCancel: @escaping () -> Void, onSave: @escaping (JournalCover) -> Void) {
        self.existing = existing
        self.balance = balance
        self.ownedFinishes = ownedFinishes
        self.unlock = unlock
        self.onCancel = onCancel
        self.onSave = onSave
        _stage = State(initialValue: existing == nil ? .intro : .cover)
        _cover = State(initialValue: existing ?? JournalCover())
    }

    var body: some View {
        content
            .edgeBack(enabled:stage != .intro,action:stepBack)
            .task { await revealPrompt() }
            .task(id:selection) { await readPhoto() }
            .sheet(isPresented:$finishesOpen) { finishPicker }
            .alert("Фото не открылось",isPresented:$photoError) { Button("Закрыть",role:.cancel) {} }
    }

    private var content: some View {
        VStack(spacing:0) {
            if stage != .intro { header }
            Spacer(minLength:4)
            journalPreview
                .scaleEffect(typing ? 0.53 : leaving && !reduced ? 1.19 : 1)
                .frame(height:typing ? 150 : 280)
                .animation(reduced ? nil : .easeInOut(duration:0.24),value:typing)
            Spacer(minLength:4)
            controls
        }.padding(.bottom,16).foregroundStyle(palette.ink)
         .background(palette.sheet.ignoresSafeArea()).opacity(leaving ? 0 : 1)
         .buttonStyle(.plain).preferredColorScheme(.dark)
    }

    private var journalPreview: some View {
        JournalModel(cover:cover,onTap:stage == .intro ? { change(.title) } : nil)
            .frame(width:236,height:280)
    }

    private var header: some View {
        HStack {
            Button(action:stepBack) { Image(systemName:"chevron.left").frame(width:44,height:44) }
            .accessibilityLabel("Назад")
            Spacer()
            Text(stage == .title ? "Название" : "Обложка").font(.subheadline.weight(.medium).monospaced())
            Spacer()
            Color.clear.frame(width:44,height:44).accessibilityHidden(true)
        }.padding(.horizontal,20)
    }

    private func stepBack() {
        typing = false
        if stage == .cover && existing == nil { change(.title) }
        else if existing == nil { change(.intro) }
        else if stage == .title { change(.cover) }
        else { onCancel() }
    }

    @ViewBuilder private var controls: some View {
        switch stage {
        case .intro:
            Button { change(.title) } label: {
                Text("создай свой дневник идей").font(.callout.monospaced())
                    .padding(.horizontal,19).frame(minHeight:50)
                    .background(palette.card,in:Capsule())
            }.opacity(promptVisible ? 1 : 0)
             .offset(y:promptVisible || reduced ? 0 : 16).accessibilityHidden(!promptVisible)
        case .title:
            VStack(spacing:12) {
                TextField("Название дневника",text:$cover.title,prompt:Text("Название дневника").foregroundStyle(palette.ink))
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
                HStack(spacing:12) {
                    PhotosPicker(selection:$selection,matching:.images) {
                        Label(loading ? "Загрузка…" : (cover.photo == nil ? "Добавить фото" : "Заменить фото"),
                              systemImage:"photo").frame(minHeight:44)
                    }
                    if cover.photo != nil {
                        Button(role:.destructive) {
                            selection = nil
                            cover.photo = nil
                        } label: {
                            Image(systemName:"trash").frame(width:44,height:44)
                                .background(palette.card,in:RoundedRectangle(cornerRadius:9))
                        }.accessibilityLabel("Убрать фото с обложки")
                    }
                }
                if existing != nil {
                    Button("Изменить название") { change(.title); typing = true }
                        .font(.subheadline.monospaced()).frame(minHeight:32)
                    Button {
                        previewFinish = cover.surface
                        finishesOpen = true
                    } label: {
                        Label("Фактура · \(cover.surface.title)",systemImage:"square.grid.3x3")
                            .font(.subheadline.monospaced()).frame(minHeight:44)
                    }
                }
                Button(existing == nil ? "Создать дневник" : "Сохранить обложку",action:complete)
                    .buttonStyle(JournalPrimary()).disabled(loading || leaving)
            }.padding(.horizontal,26)
        }
    }

    private var finishPicker: some View {
        var preview = cover
        preview.finish = previewFinish
        let owned = previewFinish == .classic || ownedFinishes.contains(previewFinish) || unlockedHere.contains(previewFinish)
        return ScrollView {
            VStack(spacing:12) {
                HStack {
                    Text("Фактура обложки").font(.headline.monospaced())
                    Spacer()
                    Text("\(balance) ★").monospacedDigit()
                }
                JournalModel(cover:preview).frame(width:190,height:205)
                ForEach(CoverFinish.allCases) { finish in
                    Button {
                        previewFinish = finish
                    } label: {
                        HStack {
                            Text(finish.title)
                            Spacer()
                            if finish != .classic && !ownedFinishes.contains(finish) && !unlockedHere.contains(finish) {
                                Text("\(finish.price) ★").monospacedDigit()
                            } else if finish == cover.surface {
                                Image(systemName:"checkmark")
                            }
                        }.padding(.horizontal,12).frame(minHeight:44)
                         .background(previewFinish == finish ? palette.card : .clear,in:RoundedRectangle(cornerRadius:8))
                    }.accessibilityAddTraits(previewFinish == finish ? .isSelected : [])
                }
                Button(owned ? "Выбрать" : "Открыть за \(previewFinish.price) ★") {
                    if owned { applyFinish() } else { purchaseConfirmation = true }
                }.buttonStyle(JournalPrimary()).disabled(!owned && balance < previewFinish.price)
                if !owned && balance < previewFinish.price {
                    Text("Не хватает \(previewFinish.price - balance) ★").font(.caption.monospaced())
                }
            }.padding(22)
        }.presentationBackground(palette.sheet).foregroundStyle(palette.ink)
         .confirmationDialog("Открыть фактуру?",isPresented:$purchaseConfirmation,titleVisibility:.visible) {
             Button("Потратить \(previewFinish.price) ★") {
                 guard unlock(previewFinish) else { return }
                 unlockedHere.insert(previewFinish)
                 applyFinish()
             }
             Button("Отмена",role:.cancel) {}
         }
    }

    private func applyFinish() {
        cover.finish = previewFinish
        finishesOpen = false
    }

    private func swatch(_ index: Int) -> some View {
        let selected = cover.shade == index
        return Button {
            cover.shade = index
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
        configuration.label.font(.body.weight(.semibold).monospaced()).frame(maxWidth:.infinity,minHeight:49)
            .foregroundStyle(palette.ink).background(palette.card,in:RoundedRectangle(cornerRadius:16))
            .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(palette.accent.opacity(0.28)).allowsHitTesting(false) }
            .opacity(!enabled ? 0.38 : configuration.isPressed ? 0.72 : 1)
    }
}


struct IdeaCalendar: View {
    @Binding var selection: Date
    let recorded: Set<Date>
    let applyDay: () -> Void
    let applyYear: (Int) -> Void
    let reset: () -> Void
    @Environment(\.appPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduced
    private enum Mode { case week, month, year }
    @State private var mode: Mode
    @State private var wheelPosition: CGFloat = 0
    @GestureState private var draggingWeek = false
    @State private var dragOrigin: CGFloat?
    @State private var wheelAnchor: Date
    @State private var year: Int
    @State private var displayedMonth: Date

    private var cal: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier:"ru")
        calendar.firstWeekday = 2
        return calendar
    }
    private let range: ClosedRange<Int>
    init(selection: Binding<Date>, recorded: Set<Date>, startsWithYear:Bool,
         applyDay:@escaping () -> Void, applyYear:@escaping (Int) -> Void, reset:@escaping () -> Void) {
        _selection = selection
        _displayedMonth = State(initialValue:selection.wrappedValue)
        _mode = State(initialValue:startsWithYear ? .year : .week)
        let calendar = Calendar.current
        _wheelAnchor = State(initialValue:calendar.startOfDay(for:selection.wrappedValue))
        _year = State(initialValue:calendar.component(.year,from:selection.wrappedValue))
        self.recorded = recorded
        self.applyDay = applyDay
        self.applyYear = applyYear
        self.reset = reset
        let todayYear = calendar.component(.year,from:Date())
        let recordedYears = recorded.map { calendar.component(.year,from:$0) }
        range = min(todayYear-8, recordedYears.min() ?? todayYear)...max(todayYear+1,recordedYears.max() ?? todayYear)
    }
    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(alignment:.leading,spacing:14) {
                HStack(spacing:8) {
                    HStack(spacing:4) {
                        modeButton("Неделя",.week)
                        modeButton("Месяц",.month)
                    }.padding(4).background(palette.sheet.opacity(0.52),in:RoundedRectangle(cornerRadius:12))
                    Button { changeMode(.year) } label: {
                        Image(systemName:"calendar.badge.clock").font(.system(size:17,weight:.medium))
                            .frame(width:44,height:44)
                            .background(mode == .year ? palette.accent.opacity(0.26) : palette.sheet.opacity(0.52),in:Circle())
                    }.accessibilityLabel("Выбрать год").accessibilityAddTraits(mode == .year ? .isSelected : [])
                }
                dateHeading
                switch mode {
                case .week: weekWheel
                case .month: monthGrid
                case .year: yearGrid
                }
                HStack {
                    Button("Все даты",action:reset).frame(minHeight:44)
                    Spacer()
                    Button("Показать идеи") {
                        if mode == .year { applyYear(year) } else { applyDay() }
                    }.font(.subheadline.weight(.semibold).monospaced()).padding(.horizontal,12)
                     .frame(minHeight:38).background(palette.accent.opacity(0.16),in:Capsule())
                }.font(.subheadline.monospaced())
            }.padding(17)
             .background(palette.card,in:RoundedRectangle(cornerRadius:24))
             .overlay { RoundedRectangle(cornerRadius:24).strokeBorder(palette.accent.opacity(0.18)).allowsHitTesting(false) }
             .padding(.horizontal,14).padding(.vertical,16)
        }.foregroundStyle(palette.ink).tint(palette.accent)
         .environment(\.locale,Locale(identifier:"ru"))
         .presentationBackground(palette.sheet)
         .presentationDetents(mode == .week ? [.height(405),.large] : [.height(520),.large])
         .presentationDragIndicator(.visible)
    }

    private var dateHeading: some View {
        let highlighted = mode == .week ? wheelDate(Int(wheelPosition.rounded())) ?? selection : selection
        let shown = mode == .month ? displayedMonth : highlighted
        return HStack(alignment:.lastTextBaseline,spacing:8) {
            if mode == .year {
                Text(String(year)).font(.system(size:45,weight:.light,design:.monospaced)).monospacedDigit()
            } else {
                VStack(alignment:.leading,spacing:3) {
                    Text(shown.formatted(.dateTime.month(.wide).locale(Locale(identifier:"ru"))).capitalized)
                        .font(.system(size:36,weight:.medium,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.65)
                    Text(String(cal.component(.year,from:shown))).font(.caption.monospaced()).foregroundStyle(palette.muted)
                }
                Spacer()
                Text(String(cal.component(.day,from:highlighted)))
                    .font(.system(size:57,weight:.light,design:.monospaced)).monospacedDigit()
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private func modeButton(_ label:String,_ next:Mode) -> some View {
        Button { changeMode(next) } label: {
            Text(label).font(.subheadline.weight(.medium).monospaced()).frame(maxWidth:.infinity,minHeight:36)
                .foregroundStyle(palette.ink)
                .background(palette.accent.opacity(mode == next ? 0.24 : 0),in:RoundedRectangle(cornerRadius:9))
        }.accessibilityAddTraits(mode == next ? .isSelected : [])
    }

    private func changeMode(_ next:Mode) {
        guard mode != next else { return }
        if next == .week { wheelPosition = CGFloat(wheelIndex(for:selection)) }
        if next == .month { displayedMonth = selection }
        if next == .year { year = cal.component(.year,from:selection) }
        withAnimation(reduced ? nil : .easeInOut(duration:0.2)) { mode = next }
    }

    private var yearGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators:false) {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:8) {
                    ForEach(range.reversed(),id:\.self) { candidate in
                        Button {
                            chooseYear(candidate)
                        } label: {
                            Text(String(candidate)).monospacedDigit()
                                .frame(maxWidth:.infinity,minHeight:44)
                                .foregroundStyle(palette.ink)
                                .background(year == candidate ? palette.accent.opacity(0.24) : palette.card,
                                            in:RoundedRectangle(cornerRadius:10))
                        }.id(candidate).accessibilityAddTraits(year == candidate ? .isSelected : [])
                    }
                }
            }.frame(height:242)
             .onAppear { proxy.scrollTo(year,anchor:.center) }
        }
    }

    private func chooseYear(_ candidate:Int) {
        year = candidate
        let month = cal.component(.month,from:selection)
        let matching = recorded.filter { cal.component(.year,from:$0) == candidate }
        selection = matching.max() ?? cal.date(from:DateComponents(year:candidate,month:month,day:1)) ?? selection
        displayedMonth = selection
    }
    private var weekWheel: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let stride = max(1,width / 7)
            let centerY: CGFloat = 66
            let selectedIndex = Int(wheelPosition.rounded())
            let cells = (selectedIndex-5)...(selectedIndex+5)
            ZStack {
                weekTrack(centerY:centerY)
                Circle().fill(palette.accent.opacity(0.23))
                    .overlay { Circle().strokeBorder(palette.accent.opacity(0.32)) }
                    .frame(width:38,height:38)
                    .position(x:width/2,y:centerY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                ForEach(cells,id:\.self) { index in
                    if let date = wheelDate(index) {
                        let relative = (CGFloat(index) - wheelPosition) * stride
                        let distance = min(1.4,abs(relative)/max(1,width/2))
                        let curve = distance * distance * 14
                        Button { settleWeek(at:index) } label: {
                            let selected = index == selectedIndex
                            ZStack {
                                Text(date,format:.dateTime.weekday(.abbreviated))
                                    .font(.caption.monospaced()).foregroundStyle(palette.muted)
                                    .offset(y:-33)
                                Text(date,format:.dateTime.day())
                                    .font(.body.weight(selected ? .semibold : .regular).monospaced())
                                if recorded.contains(cal.startOfDay(for:date)) {
                                    Circle().fill(palette.ink).frame(width:3,height:3).offset(y:14)
                                }
                            }.frame(width:stride,height:110).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                         .position(x:width/2+relative,y:centerY+curve)
                         .accessibilityLabel(date.formatted(date:.complete,time:.omitted))
                         .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                         .accessibilityHidden(abs(relative) > width/2)
                    }
                }
            }
            .frame(width:width,height:132)
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance:8)
                .updating($draggingWeek) { _,active,_ in active = true }
                .onChanged { value in
                    guard dragOrigin != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                    let origin = dragOrigin ?? wheelPosition
                    dragOrigin = origin
                    wheelPosition = boundedWeekPosition(origin - value.translation.width / stride)
                }
                .onEnded { value in
                    guard dragOrigin != nil else { return }
                    dragOrigin = nil
                    let projected = (value.predictedEndTranslation.width - value.translation.width) / stride
                    let target = boundedWeekPosition(wheelPosition - min(2,max(-2,projected * 0.3)))
                    settleWeek(at:Int(target.rounded()))
                })
            .onChange(of:draggingWeek) { _,active in
                // A system gesture can cancel the drag without sending an end event.
                if !active && dragOrigin != nil {
                    Task { @MainActor in
                        guard !draggingWeek, dragOrigin != nil else { return }
                        dragOrigin = nil
                        settleWeek(at:Int(wheelPosition.rounded()))
                    }
                }
            }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: settleWeek(at:selectedIndex+1)
                case .decrement: settleWeek(at:selectedIndex-1)
                @unknown default: break
                }
            }
        }.frame(height:132)
    }

    private func weekTrack(centerY:CGFloat) -> some View {
        Canvas { context,size in
            let w = size.width
            let halfHeight: CGFloat = 19
            let rise: CGFloat = 14
            let top = centerY - halfHeight
            let bottom = centerY + halfHeight
            var track = Path()
            track.move(to:CGPoint(x:0,y:top+rise))
            track.addQuadCurve(to:CGPoint(x:w,y:top+rise),control:CGPoint(x:w/2,y:top-rise))
            track.addLine(to:CGPoint(x:w,y:bottom+rise))
            track.addQuadCurve(to:CGPoint(x:0,y:bottom+rise),control:CGPoint(x:w/2,y:bottom-rise))
            track.closeSubpath()
            context.fill(track,with:.color(palette.accent.opacity(0.06)))
            context.stroke(track,with:.color(palette.accent.opacity(0.12)),lineWidth:0.7)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private func wheelIndex(for date:Date) -> Int {
        cal.dateComponents([.day],from:wheelAnchor,to:cal.startOfDay(for:date)).day ?? 0
    }

    private func wheelDate(_ index:Int) -> Date? {
        guard let day = cal.date(byAdding:.day,value:index,to:wheelAnchor),
              range.contains(cal.component(.year,from:day)) else { return nil }
        return cal.startOfDay(for:day)
    }

    private func boundedWeekPosition(_ position:CGFloat) -> CGFloat {
        let first = cal.date(from:DateComponents(year:range.lowerBound,month:1,day:1)) ?? wheelAnchor
        let last = cal.date(from:DateComponents(year:range.upperBound,month:12,day:31)) ?? wheelAnchor
        return min(CGFloat(wheelIndex(for:last)),max(CGFloat(wheelIndex(for:first)),position))
    }

    private func settleWeek(at index:Int) {
        let target = boundedWeekPosition(CGFloat(index))
        guard let day = wheelDate(Int(target)) else { return }
        selection = day
        withAnimation(reduced ? nil : .spring(response:0.30,dampingFraction:0.86)) {
            wheelPosition = target
        }
    }

    private var monthGrid: some View {
        let monthStart = cal.dateInterval(of:.month,for:displayedMonth)?.start ?? displayedMonth
        let blanks = (cal.component(.weekday,from:monthStart)-cal.firstWeekday+7)%7
        let count = cal.range(of:.day,in:.month,for:monthStart)?.count ?? 31
        let weekdays = Array(cal.shortStandaloneWeekdaySymbols.dropFirst()) + Array(cal.shortStandaloneWeekdaySymbols.prefix(1))
        return VStack(spacing:8) {
            HStack {
                monthButton(-1, icon:"chevron.left")
                Spacer()
                Text(displayedMonth,format:.dateTime.month(.wide).year()).font(.callout.weight(.semibold).monospaced())
                Spacer()
                monthButton(1, icon:"chevron.right")
            }
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:5) {
                ForEach(weekdays,id:\.self) { Text($0).font(.caption.monospaced()).foregroundStyle(palette.muted) }
                ForEach(0..<(blanks+count),id:\.self) { index in
                    if index < blanks {
                        Color.clear.frame(height:39)
                    } else if let day = cal.date(byAdding:.day,value:index-blanks,to:monthStart) {
                        monthDay(day)
                    }
                }
            }
        }.padding(8).background(palette.card,in:RoundedRectangle(cornerRadius:15))
    }
    private func monthButton(_ offset:Int, icon:String) -> some View {
        let next = cal.date(byAdding:.month,value:offset,to:displayedMonth) ?? displayedMonth
        let available = range.contains(cal.component(.year,from:next))
        return Button {
            displayedMonth = next
            selection = next
        } label: { Image(systemName:icon).frame(width:44,height:44) }
            .disabled(!available).opacity(available ? 1 : 0.35)
            .accessibilityLabel(offset < 0 ? "Предыдущий месяц" : "Следующий месяц")
    }
    private func monthDay(_ day:Date) -> some View {
        let selected = cal.isDate(day,inSameDayAs:selection)
        return Button { selection = day } label: {
            VStack(spacing:2) {
                Text(day,format:.dateTime.day()).font(.subheadline.monospaced())
                Circle().fill(palette.accent)
                    .frame(width:3,height:3).opacity(recorded.contains(day) ? 1 : 0)
            }.foregroundStyle(palette.ink)
             .frame(maxWidth:.infinity,minHeight:39)
             .background(palette.accent.opacity(selected ? 0.24 : 0),in:RoundedRectangle(cornerRadius:8))
        }.accessibilityLabel(day.formatted(date:.complete,time:.omitted))
         .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

import SceneKit

struct JournalModel: UIViewRepresentable {
    let cover: JournalCover
    var onTap: (() -> Void)? = nil
    var onHold: (() -> Void)? = nil
    var autoRotate = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduced

    func makeCoordinator() -> Interaction { Interaction() }

    func makeUIView(context: Context) -> SCNView {
        let view = AccessibleBookView()
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.73
        camera.position = SCNVector3(0,0,7)
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        scene.rootNode.addChildNode(context.coordinator.book)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        scene.rootNode.addChildNode(ambient)
        let softbox = SCNNode()
        softbox.light = SCNLight()
        softbox.light?.type = .directional
        softbox.light?.intensity = 780
        softbox.eulerAngles = SCNVector3(-0.43,-0.48,0)
        scene.rootNode.addChildNode(softbox)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 470
        rim.eulerAngles = SCNVector3(0.35,2.40,0)
        scene.rootNode.addChildNode(rim)
        view.isAccessibilityElement = true
        view.accessibilityTraits = [.button]
        view.accessibilityLabel = "Дневник"
        let pan = UIPanGestureRecognizer(target:context.coordinator,action:#selector(Interaction.rotate(_:)))
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target:context.coordinator,action:#selector(Interaction.open))
        tap.require(toFail:pan)
        let hold = UILongPressGestureRecognizer(target:context.coordinator,action:#selector(Interaction.hold(_:)))
        hold.minimumPressDuration = 0.55
        hold.allowableMovement = 12
        tap.require(toFail:hold)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view:SCNView,context:Context) {
        let controller = context.coordinator
        controller.openIdea = onTap
        controller.openPast = onHold
        view.accessibilityTraits = onTap == nil ? [] : [.button]
        view.accessibilityLabel = onTap == nil ? "Предпросмотр дневника" : "Дневник, записать идею"
        controller.reduced = reduced
        let moving = autoRotate && !reduced && scenePhase == .active
        controller.setAutoRotate(moving)
        view.rendersContinuously = moving
        if autoRotate { view.isPlaying = moving }
        (view as? AccessibleBookView)?.openIdea = onTap
        view.accessibilityCustomActions = onHold.map { action in
            [UIAccessibilityCustomAction(name:"Из прошлых страниц",actionHandler:{ _ in action(); return true })]
        }
        guard controller.artwork != cover || controller.colors != palette else { return }
        controller.artwork = cover
        controller.colors = palette
        let cloth = UIColor(JournalCover.colors[cover.shade])
        let renderer = ImageRenderer(content:NotebookFace(cover:cover))
        renderer.isOpaque = true
        renderer.scale = 2.5
        controller.rebuild(front:renderer.uiImage,cloth:cloth,hasPhoto:cover.photo != nil,finish:cover.surface)
    }

    static func dismantleUIView(_ view:SCNView,coordinator:Interaction) {
        coordinator.setAutoRotate(false)
        view.rendersContinuously = false
        view.isPlaying = false
    }

    final class AccessibleBookView: SCNView {
        var openIdea: (() -> Void)?
        override func accessibilityActivate() -> Bool { openIdea?(); return true }
    }

    final class Interaction: NSObject {
        let book = SCNNode()
        private let tilt = SCNNode()
        private var start = CGPoint.zero
        private var autoRotate = false
        private var dragging = false
        private var yaw: Float = -0.43
        private var pitch: Float = 0.13
        var artwork: JournalCover?
        var colors: AppPalette?
        var reduced = false
        var openIdea: (() -> Void)?
        var openPast: (() -> Void)?

        override init() {
            super.init()
            book.eulerAngles.y = yaw
            tilt.eulerAngles.x = pitch
            book.addChildNode(tilt)
        }

        func rebuild(front:UIImage?, cloth:UIColor, hasPhoto:Bool, finish:CoverFinish) {
            tilt.childNodes.forEach { $0.removeFromParentNode() }
            if !JournalMesh.parts.isEmpty {
                let colors: [UIColor] = [cloth,cloth,UIColor(white:0.57,alpha:1),
                                        UIColor(white:0.79,alpha:1),UIColor(white:0.16,alpha:1)]
                for part in JournalMesh.parts {
                    let material = SCNMaterial()
                    material.lightingModel = .physicallyBased
                    if part.kind == 0, let front { material.diffuse.contents = front }
                    else { material.diffuse.contents = colors[part.kind] }
                    let coverRoughness: Double = finish == .embossed ? 0.57 : finish == .paper ? 0.96 : 0.76
                    material.roughness.contents = part.kind <= 1 ? coverRoughness : 0.89
                    if part.kind <= 1 {
                        material.normal.contents = UIImage(named:"JournalGrain")
                        let strength: CGFloat = finish == .linen ? 0.17 : finish == .paper ? 0.04 : 0.08
                        material.normal.intensity = part.kind == 0 && hasPhoto ? strength * 0.45 : strength
                    }
                    let geometry = part.makeGeometry()
                    geometry.materials = [material]
                    tilt.addChildNode(SCNNode(geometry:geometry))
                }
                return
            }
            let paper = pages()
            let exterior = SCNMaterial()
            exterior.diffuse.contents = cloth
            exterior.lightingModel = .constant
            let block = SCNBox(width:1.75,height:2.49,length:0.23,chamferRadius:0.018)
            block.materials = [paper,paper,paper,exterior,paper,paper]
            tilt.addChildNode(SCNNode(geometry:block))
            addCover(at:0.132,cloth:exterior,artwork:front)
            addCover(at:-0.132,cloth:exterior)
        }

        private func addCover(at z:Float,cloth:SCNMaterial,artwork:UIImage? = nil) {
            let box = SCNBox(width:1.82,height:2.58,length:0.044,chamferRadius:0.014)
            if let artwork {
                let image = SCNMaterial()
                image.diffuse.contents = artwork
                image.lightingModel = .constant
                // SCNBox orders its faces front, right, back, left, top and bottom.
                box.materials = [image,cloth,cloth,cloth,cloth,cloth]
            } else { box.materials = [cloth] }
            let node = SCNNode(geometry:box)
            node.position.z = z
            tilt.addChildNode(node)
        }

        private func pages() -> SCNMaterial {
            let image = UIGraphicsImageRenderer(size:CGSize(width:128,height:128)).image { context in
                UIColor(white:0.67,alpha:1).setFill()
                context.fill(CGRect(x:0,y:0,width:128,height:128))
                for index in 0..<27 {
                    let bright = index.isMultiple(of:4)
                    UIColor(white:bright ? 0.82 : 0.54,alpha:1).setFill()
                    context.fill(CGRect(x:Double(index)*4.75,y:0,width:bright ? 1.4 : 0.55,height:128))
                }
            }
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.lightingModel = .constant
            return material
        }

        func setAutoRotate(_ enabled:Bool) {
            guard enabled != autoRotate else { return }
            autoRotate = enabled
            if enabled { resumeRotation() }
            else if !dragging { stopRotationAtCurrentAngle() }
        }

        private func stopRotationAtCurrentAngle() {
            let transform = book.presentation.transform
            yaw = atan2f(-transform.m13,transform.m11)
            book.removeAction(forKey:"rotation")
            book.eulerAngles.y = yaw
        }

        private func resumeRotation(after spin:SCNAction? = nil) {
            guard !dragging else { return }
            let turn = SCNAction.rotateBy(x:0,y:.pi*2,z:0,duration:28)
            let idle = SCNAction.repeatForever(turn)
            if autoRotate {
                let wait = SCNAction.wait(duration:0.65)
                book.runAction(.sequence((spin.map { [$0] } ?? []) + [wait,idle]),forKey:"rotation")
            } else if let spin {
                book.runAction(spin,forKey:"rotation")
            }
        }

        @objc func open() { openIdea?() }

        @objc func hold(_ gesture:UILongPressGestureRecognizer) {
            if gesture.state == .began { openPast?() }
        }

        @objc func rotate(_ gesture:UIPanGestureRecognizer) {
            let delta = gesture.translation(in:gesture.view)
            switch gesture.state {
            case .began:
                dragging = true
                stopRotationAtCurrentAngle()
                start = CGPoint(x:CGFloat(yaw),y:CGFloat(tilt.eulerAngles.x))
            case .changed,.ended:
                yaw = Float(start.x + delta.x*0.012)
                pitch = min(0.78,max(-0.78,Float(start.y)+Float(delta.y)*0.007))
                book.eulerAngles.y = yaw
                tilt.eulerAngles.x = pitch
                if gesture.state == .ended {
                    dragging = false
                    if !reduced {
                        let velocity = gesture.velocity(in:gesture.view).x
                        let spin = min(1.5,max(-1.5,velocity*0.0017))
                        let action = SCNAction.rotateBy(x:0,y:spin,z:0,duration:0.54)
                        action.timingMode = .easeOut
                        resumeRotation(after:action)
                    }
                }
            case .failed,.cancelled:
                dragging = false
                resumeRotation()
            default: break
            }
        }
    }
}



// Mesh adapted from Pocket Journal by Innerscene, dedicated to the public domain under CC0.
private struct JournalMesh {
    var kind: Int
    var vertexCount: Int
    var indexCount: Int
    var vertices: Data
    var indices: Data

    static let parts: [Self] = {
        guard let data = NSDataAsset(name:"JournalMesh")?.data,
              data.prefix(4) == Data("NB21".utf8) else { return [] }
        var cursor = 4
        func read() -> Int? {
            guard cursor+4 <= data.count else { return nil }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:cursor,as:UInt32.self) }
            cursor += 4
            return Int(UInt32(littleEndian:value))
        }
        guard let materialCount = read(), materialCount == 5 else { return [] }
        var result = [Self]()
        for _ in 0..<materialCount {
            guard let kind = read(), (0..<materialCount).contains(kind),
                  let count = read(), let indices = read(), count > 0, indices > 0,
                  indices.isMultiple(of:3) else { return [] }
            let boundary = cursor+count*32
            let end = boundary+indices*2
            guard end <= data.count else { return [] }
            result.append(Self(kind:kind,vertexCount:count,indexCount:indices,
                               vertices:data.subdata(in:cursor..<boundary),indices:data.subdata(in:boundary..<end)))
            cursor = end
        }
        return result
    }()

    func makeGeometry() -> SCNGeometry {
        func source(_ semantic:SCNGeometrySource.Semantic,_ components:Int,_ offset:Int) -> SCNGeometrySource {
            SCNGeometrySource(data:vertices,semantic:semantic,vectorCount:vertexCount,usesFloatComponents:true,
                              componentsPerVector:components,bytesPerComponent:4,dataOffset:offset,dataStride:32)
        }
        let faces = SCNGeometryElement(data:indices,primitiveType:.triangles,primitiveCount:indexCount/3,bytesPerIndex:2)
        return SCNGeometry(sources:[source(.vertex,3,0),source(.normal,3,12),source(.texcoord,2,24)],elements:[faces])
    }
}


private extension View {
    func edgeBack(enabled:Bool = true, action:@escaping () -> Void) -> some View {
        overlay(alignment:.leading) {
            if enabled {
                GeometryReader { metrics in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:14)
                            .onEnded { swipe in
                                let width = metrics.size.width
                                // The strip accepts only a deliberate horizontal motion.
                                let reach = swipe.translation.width
                                if reach >= max(width * 3,72), reach > abs(swipe.translation.height) * 1.6 {
                                    action()
                                }
                            })
                }.frame(width:18)
                 .padding(.vertical,50)
                 .accessibilityHidden(true)
            }
        }
    }
}

private struct NotebookLoader: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        TimelineView(.animation(paused:reduced)) { moment in
            let turn = moment.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:1.25)
            SparkShape().fill(color).frame(width:35,height:35)
                .rotationEffect(.degrees(reduced ? 0 : turn * 288))
        }.accessibilityLabel("Загрузка дневника")
    }
}

private struct AvatarDesign: Codable {
    enum Form: String, CaseIterable, Codable, Identifiable {
        case moon, cat, bear, eye
        var id: Self { self }
        var title: String {
            switch self {
            case .moon: "Луна"
            case .cat: "Кот"
            case .bear: "Медведь"
            case .eye: "Глаз"
            }
        }
    }

    enum Tone: String, CaseIterable, Codable, Identifiable {
        case pearl, peach, mint, lilac, blue
        var id: Self { self }
        var title: String {
            switch self {
            case .pearl: "Жемчуг"
            case .peach: "Персик"
            case .mint: "Мята"
            case .lilac: "Сирень"
            case .blue: "Синий"
            }
        }
        var color: Color {
            switch self {
            case .pearl: Color(red:0.85,green:0.84,blue:0.79)
            case .peach: Color(red:0.88,green:0.55,blue:0.43)
            case .mint: Color(red:0.55,green:0.75,blue:0.64)
            case .lilac: Color(red:0.70,green:0.59,blue:0.82)
            case .blue: Color(red:0.48,green:0.64,blue:0.81)
            }
        }
    }

    var form: Form = .moon
    var tone: Tone = .pearl
    var freckles = false
    var pupil: EyePupil? = nil
    var eyeTexture: EyeTexture? = nil
}

private struct AvatarExpression {
    var blinkLeft: CGFloat = 0
    var blinkRight: CGFloat = 0
    var brow: CGFloat = 0
    var jaw: CGFloat = 0
    var smile: CGFloat = 0
    var roll: Double = 0
    var yaw: Double = 0
    var pitch: Double = 0
}

private struct AvatarFace: UIViewRepresentable {
    let design: AvatarDesign
    var expression = AvatarExpression()

    func makeCoordinator() -> Model { Model() }

    func makeUIView(context:Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view:SCNView,context:Context) {
        context.coordinator.render(design,expression:expression)
        view.setNeedsDisplay()
    }

    final class Model {
        let scene = SCNScene()
        let camera = SCNNode()
        private let head = SCNNode()
        private let skin = SCNMaterial()
        private var eyes: [SCNNode] = []
        private var brows: [SCNNode] = []
        private var cheeks: [SCNNode] = []
        private var freckles: [SCNNode] = []
        private var catEars: [SCNNode] = []
        private var bearEars: [SCNNode] = []
        private let closedMouth = SCNNode()
        private let openMouth = SCNNode()
        private let tongue = SCNNode()
        private var previousTone: AvatarDesign.Tone?

        init() {
            scene.background.contents = UIColor.clear
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 1.36
            camera.position = SCNVector3(0,0.15,5)
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(head)

            light(.ambient,800,at:SCNVector3Zero,color:UIColor(white:0.92,alpha:1))
            light(.directional,1500,at:SCNVector3(-3,4,5),color:UIColor(red:1,green:0.91,blue:0.80,alpha:1))
            light(.directional,800,at:SCNVector3(3,2,-3),color:UIColor(red:0.69,green:0.79,blue:1,alpha:1))

            skin.lightingModel = .physicallyBased
            skin.roughness.contents = 0.48
            let cream = material(UIColor(red:1,green:0.98,blue:0.92,alpha:1),roughness:0.32)
            let iris = material(UIColor(red:0.25,green:0.17,blue:0.22,alpha:1),roughness:0.34)
            let black = material(UIColor(white:0.045,alpha:1),roughness:0.24)
            let nose = material(UIColor(red:0.30,green:0.17,blue:0.20,alpha:1),roughness:0.55)
            let pink = material(UIColor(red:0.86,green:0.42,blue:0.42,alpha:1),roughness:0.66)

            oval(in:head,at:SCNVector3Zero,size:SCNVector3(0.97,0.88,0.58),material:skin)
            for side:Float in [-1,1] {
                let x = side * 0.35
                let eye = SCNNode()
                eye.position = SCNVector3(x,0.11,0.50)
                head.addChildNode(eye)
                eyes.append(eye)
                oval(in:eye,at:SCNVector3Zero,size:SCNVector3(0.23,0.27,0.09),material:cream)
                oval(in:eye,at:SCNVector3(side * -0.025,0.005,0.076),
                     size:SCNVector3(0.129,0.154,0.035),material:iris)
                oval(in:eye,at:SCNVector3(side * -0.025,0.005,0.10),
                     size:SCNVector3(0.085,0.110,0.028),material:black)
                oval(in:eye,at:SCNVector3(-0.06,0.069,0.122),
                     size:SCNVector3(0.027,0.028,0.010),material:cream)

                let brow = oval(in:head,at:SCNVector3(x,0.46,0.465),
                                size:SCNVector3(0.132,0.029,0.025),material:nose)
                brow.eulerAngles.z = side * -0.15
                brows.append(brow)
                cheeks.append(oval(in:head,at:SCNVector3(side * 0.55,-0.27,0.416),
                                   size:SCNVector3(0.142,0.074,0.038),material:pink))
                for index in 0..<3 {
                    let spotX = 0.48 + Float(index) * 0.09
                    let spotZ = 0.49 - Float(index) * 0.047
                    freckles.append(oval(in:head,at:SCNVector3(side * spotX,-0.23 + Float(index%2)*0.04,spotZ),
                                          size:SCNVector3(0.017,0.021,0.014),material:nose))
                }

                let round = SCNNode()
                round.position = SCNVector3(side*0.65,0.68,0.04)
                head.addChildNode(round)
                bearEars.append(round)
                oval(in:round,at:SCNVector3Zero,size:SCNVector3(0.27,0.28,0.19),material:skin)
                oval(in:round,at:SCNVector3(0,0,0.156),size:SCNVector3(0.157,0.17,0.052),material:pink)

                let pointed = SCNNode()
                pointed.position = SCNVector3(side*0.63,0.68,0.03)
                pointed.eulerAngles.z = side * -0.26
                head.addChildNode(pointed)
                catEars.append(pointed)
                addEar(to:pointed,scale:1,z:0,material:skin)
                addEar(to:pointed,scale:0.55,z:0.11,material:pink)
            }
            oval(in:head,at:SCNVector3(0,-0.19,0.571),size:SCNVector3(0.082,0.055,0.048),material:nose)
            closedMouth.position = SCNVector3(0,-0.35,0.54)
            head.addChildNode(closedMouth)
            let smilePath = UIBezierPath()
            smilePath.move(to:CGPoint(x:-0.18,y:0.045))
            smilePath.addQuadCurve(to:CGPoint(x:0.18,y:0.045),controlPoint:CGPoint(x:0,y:-0.12))
            smilePath.addQuadCurve(to:CGPoint(x:-0.18,y:0.045),controlPoint:CGPoint(x:0,y:-0.19))
            smilePath.close()
            let smile = SCNShape(path:smilePath,extrusionDepth:0.020)
            smile.chamferRadius = 0.006
            smile.firstMaterial = black
            closedMouth.geometry = smile

            openMouth.position = SCNVector3(0,-0.36,0.525)
            head.addChildNode(openMouth)
            oval(in:openMouth,at:SCNVector3Zero,size:SCNVector3(0.19,0.17,0.05),material:black)
            tongue.position = SCNVector3(0,-0.084,0.04)
            openMouth.addChildNode(tongue)
            oval(in:tongue,at:SCNVector3Zero,size:SCNVector3(0.094,0.047,0.014),material:pink)
        }

        func render(_ design:AvatarDesign,expression:AvatarExpression) {
            if previousTone != design.tone {
                skin.diffuse.contents = UIColor(design.tone.color)
                previousTone = design.tone
            }
            catEars.forEach { $0.isHidden = design.form != .cat }
            bearEars.forEach { $0.isHidden = design.form != .bear }
            freckles.forEach { $0.isHidden = !design.freckles }
            head.eulerAngles = SCNVector3(Float(expression.pitch),Float(expression.yaw),Float(-expression.roll))
            eyes[0].scale.y = max(0.05,1 - Float(expression.blinkLeft) * 0.95)
            eyes[1].scale.y = max(0.05,1 - Float(expression.blinkRight) * 0.95)
            for brow in brows { brow.position.y = 0.46 + 0.14 * Float(expression.brow) }
            let grin = Float(expression.smile)
            for cheek in cheeks { cheek.opacity = CGFloat(0.63 + grin * 0.33) }
            let jaw = Float(expression.jaw)
            openMouth.isHidden = jaw < 0.12
            closedMouth.isHidden = !openMouth.isHidden
            openMouth.scale = SCNVector3(0.72 + grin * 0.44,0.38 + jaw * 0.65,1)
            closedMouth.scale = SCNVector3(0.72 + grin * 0.65,0.65 + grin * 0.72,1)
        }

        private func material(_ color:UIColor,roughness:Double) -> SCNMaterial {
            let result = SCNMaterial()
            result.lightingModel = .physicallyBased
            result.diffuse.contents = color
            result.roughness.contents = roughness
            return result
        }

        @discardableResult private func oval(in parent:SCNNode,at position:SCNVector3,
                                              size:SCNVector3,material:SCNMaterial) -> SCNNode {
            let shape = SCNSphere(radius:1)
            shape.segmentCount = 32
            shape.firstMaterial = material
            let node = SCNNode(geometry:shape)
            node.position = position
            node.scale = size
            parent.addChildNode(node)
            return node
        }

        private func addEar(to parent:SCNNode,scale:Float,z:Float,material:SCNMaterial) {
            let path = UIBezierPath()
            path.move(to:CGPoint(x:-0.23,y:-0.13))
            path.addQuadCurve(to:CGPoint(x:0.03,y:0.42),controlPoint:CGPoint(x:-0.14,y:0.44))
            path.addQuadCurve(to:CGPoint(x:0.26,y:-0.13),controlPoint:CGPoint(x:0.18,y:0.43))
            path.close()
            let geometry = SCNShape(path:path,extrusionDepth:0.17)
            geometry.chamferRadius = 0.07
            geometry.firstMaterial = material
            let piece = SCNNode(geometry:geometry)
            piece.position.z = z
            piece.scale = SCNVector3(scale,scale,scale)
            parent.addChildNode(piece)
        }

        private func light(_ type:SCNLight.LightType,_ strength:CGFloat,at position:SCNVector3,color:UIColor) {
            let node = SCNNode()
            let light = SCNLight()
            light.type = type
            light.intensity = strength
            light.color = color
            node.light = light
            node.position = position
            if type == .directional { node.look(at:SCNVector3Zero) }
            scene.rootNode.addChildNode(node)
        }
    }
}

private struct AvatarEditor: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tracker = AvatarTracker()
    @State private var cameraRequested = false
    @State private var design: AvatarDesign
    @State private var confirmPupil = false
    @State private var unlockedHere: Set<EyePupil> = []
    let balance: Int
    let ownedPupils: Set<EyePupil>
    let unlock: (EyePupil) -> Bool
    let onSave: (AvatarDesign) -> Void

    private var chosenPupil: EyePupil { design.pupil ?? .round }
    private var canSave: Bool { design.form != .eye || owns(chosenPupil) }

    private func owns(_ pupil:EyePupil) -> Bool {
        pupil == .round || ownedPupils.contains(pupil) || unlockedHere.contains(pupil)
    }

    init(initial:AvatarDesign,balance:Int,ownedPupils:Set<EyePupil>,unlock:@escaping (EyePupil) -> Bool,
         onSave:@escaping (AvatarDesign) -> Void) {
        self.balance = balance
        self.ownedPupils = ownedPupils
        self.unlock = unlock
        _design = State(initialValue:initial)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing:0) {
            HStack {
                Button("Отмена") { dismiss() }.frame(minHeight:44)
                Spacer()
                Button("Готово") { onSave(design); dismiss() }
                    .fontWeight(.semibold).frame(minHeight:44).disabled(!canSave)
            }.padding(.horizontal,22).padding(.top,12)
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("Твой аватар").font(.title2.bold().monospaced())
                    ProfileAvatar(design:design,expression:tracker.expression,animated:!cameraRequested)
                        .frame(width:design.form == .eye ? 236 : 160,height:design.form == .eye ? 236 : 160)
                        .frame(maxWidth:.infinity)
                    Text("Форма").font(.footnote.monospaced()).foregroundStyle(palette.muted)
                    HStack(spacing:8) {
                        ForEach(AvatarDesign.Form.allCases) { form in
                            Button {
                                design.form = form
                                if form == .eye { cameraRequested = false }
                            } label: {
                                VStack(spacing:3) {
                                    ProfileAvatar(design:AvatarDesign(form:form,tone:design.tone,freckles:design.freckles))
                                        .frame(width:44,height:44)
                                    Text(form.title).font(.caption.monospaced()).lineLimit(1).minimumScaleFactor(0.75)
                                }.frame(maxWidth:.infinity).padding(.vertical,8)
                                 .background(palette.accent.opacity(design.form == form ? 0.21 : 0.06),
                                             in:RoundedRectangle(cornerRadius:12))
                            }.accessibilityAddTraits(design.form == form ? .isSelected : [])
                        }
                    }
                    Text(design.form == .eye ? "Цвет радужки" : "Цвет").font(.footnote.monospaced()).foregroundStyle(palette.muted)
                    HStack {
                        ForEach(AvatarDesign.Tone.allCases) { tone in
                            Button { design.tone = tone } label: {
                                Circle().fill(tone.color).frame(width:29,height:29)
                                    .overlay { if design.tone == tone {
                                        Image(systemName:"checkmark").font(.caption.bold()).foregroundStyle(.black)
                                    } }
                                    .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                            }.accessibilityLabel(tone.title)
                             .accessibilityAddTraits(design.tone == tone ? .isSelected : [])
                        }
                    }
                    if design.form == .eye {
                        eyeOptions
                    } else {
                        Toggle("Веснушки",isOn:$design.freckles)
                    }
                    if design.form != .eye && ARFaceTrackingConfiguration.isSupported {
                        Button {
                            cameraRequested.toggle()
                        } label: {
                            Label(cameraRequested ? "Выключить камеру" : "Оживить мимикой",
                                  systemImage:cameraRequested ? "video.slash" : "faceid")
                        }.buttonStyle(JournalPrimary())
                        Text(tracker.message ?? (cameraRequested
                             ? (tracker.hasFace ? "Моргни, улыбнись или поверни голову." : "Посмотри в переднюю камеру.")
                             : "Камера нужна только для живого предпросмотра. Запись не ведётся."))
                            .font(.footnote.monospaced()).foregroundStyle(palette.muted)
                    } else if design.form != .eye {
                        Text("Отслеживание мимики недоступно на этом устройстве.")
                            .font(.footnote.monospaced()).foregroundStyle(palette.muted)
                    }
                }.padding(22)
            }.scrollBounceBehavior(.basedOnSize)
        }.font(.body.monospaced()).foregroundStyle(palette.ink)
         .background(palette.sheet.ignoresSafeArea()).presentationBackground(palette.sheet)
         .buttonStyle(.plain).edgeBack { dismiss() }
         .confirmationDialog("Открыть зрачок?",isPresented:$confirmPupil,titleVisibility:.visible) {
             Button("Потратить \(chosenPupil.price) ★") {
                 if unlock(chosenPupil) { unlockedHere.insert(chosenPupil) }
             }
             Button("Отмена",role:.cancel) {}
         }
         .task(id:cameraRequested) {
             guard cameraRequested else { tracker.stop(); return }
             let permitted = await AVCaptureDevice.requestAccess(for:.video)
             guard !Task.isCancelled, cameraRequested, scenePhase != .background else { return }
             if permitted { tracker.start() }
             else {
                 tracker.message = "Разреши доступ к камере в настройках iPhone."
                 cameraRequested = false
             }
         }
         .onChange(of:scenePhase) { _,phase in
             // The permission prompt can make the scene inactive temporarily.
             if phase == .background { tracker.stop(); cameraRequested = false }
         }
         .onChange(of:tracker.failure) { _,failed in if failed { cameraRequested = false } }
         .onDisappear { tracker.stop() }
    }

    private var eyeOptions: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Фактура").font(.footnote.monospaced()).foregroundStyle(palette.muted)
            HStack(spacing:8) {
                ForEach(EyeTexture.allCases) { texture in
                    Button { design.eyeTexture = texture } label: {
                        Text(texture.title).font(.caption.monospaced()).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth:.infinity,minHeight:44)
                            .background(palette.accent.opacity((design.eyeTexture ?? .fibers) == texture ? 0.19 : 0.06),
                                        in:RoundedRectangle(cornerRadius:9))
                    }.accessibilityAddTraits((design.eyeTexture ?? .fibers) == texture ? .isSelected : [])
                }
            }
            HStack {
                Text("Зрачок")
                Spacer()
                Text("\(balance) ★")
            }.font(.footnote.monospaced()).foregroundStyle(palette.muted)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(EyePupil.allCases) { pupil in
                    Button { design.pupil = pupil } label: {
                        VStack(alignment:.leading,spacing:5) {
                            Text(pupil.title).font(.subheadline.monospaced())
                            Text(owns(pupil) ? (pupil == .round ? "Бесплатно" : "Открыт") : "\(pupil.price) ★")
                                .font(.caption.monospaced()).foregroundStyle(palette.muted)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
                         .background(palette.accent.opacity(chosenPupil == pupil ? 0.19 : 0.06),
                                     in:RoundedRectangle(cornerRadius:9))
                    }.accessibilityAddTraits(chosenPupil == pupil ? .isSelected : [])
                }
            }
            if !owns(chosenPupil) {
                Button("Открыть за \(chosenPupil.price) ★") { confirmPupil = true }
                    .buttonStyle(JournalPrimary()).disabled(balance < chosenPupil.price)
                if balance < chosenPupil.price {
                    Text("Не хватает \(chosenPupil.price - balance) ★")
                        .font(.caption.monospaced()).foregroundStyle(palette.muted)
                }
            }
        }
    }
}

private final class AvatarTracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var expression = AvatarExpression()
    @Published private(set) var hasFace = false
    @Published private(set) var failure = false
    @Published var message: String?
    private var activeSession: ARSession?
    private var reference: simd_float4x4?

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        stop()
        failure = false
        message = nil
        let session = ARSession()
        session.delegate = self
        session.delegateQueue = .main
        activeSession = session
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        session.run(configuration,options:[.resetTracking,.removeExistingAnchors])
    }

    func stop() {
        activeSession?.pause()
        activeSession?.delegate = nil
        activeSession = nil
        forgetFace()
    }

    func session(_ session:ARSession,didUpdate anchors:[ARAnchor]) {
        guard activeSession === session, let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        guard face.isTracked else { forgetFace(); return }
        let shapes = face.blendShapes
        func amount(_ key:ARFaceAnchor.BlendShapeLocation) -> CGFloat {
            CGFloat(min(1,max(0,shapes[key]?.doubleValue ?? 0)))
        }
        if reference == nil { reference = face.transform }
        let movement = simd_inverse(reference ?? face.transform) * face.transform
        let angles = simd_quatf(movement).act(SIMD3<Float>(0,0,1))
        let side = movement.columns.0
        var next = AvatarExpression()
        next.blinkLeft = amount(.eyeBlinkRight)
        next.blinkRight = amount(.eyeBlinkLeft)
        next.brow = amount(.browInnerUp)
        next.jaw = amount(.jawOpen)
        next.smile = (amount(.mouthSmileLeft) + amount(.mouthSmileRight)) / 2
        next.roll = min(0.4,max(-0.4,Double(atan2(side.y,side.x))))
        next.yaw = min(0.65,max(-0.65,-Double(angles.x)))
        next.pitch = min(0.48,max(-0.48,Double(angles.y)))
        expression = next
        if !hasFace { hasFace = true }
    }

    func session(_ session:ARSession,didRemove anchors:[ARAnchor]) {
        if activeSession === session && anchors.contains(where:{ $0 is ARFaceAnchor }) { forgetFace() }
    }

    func sessionWasInterrupted(_ session:ARSession) {
        if activeSession === session { forgetFace() }
    }

    func session(_ session:ARSession,didFailWithError error:Error) {
        guard activeSession === session else { return }
        stop()
        message = "Камера недоступна. Попробуй включить её ещё раз."
        failure = true
    }

    private func forgetFace() {
        reference = nil
        if hasFace {
            hasFace = false
            expression = AvatarExpression()
        }
    }
}


private enum EyeTexture: String, Codable, CaseIterable, Identifiable {
    case fibers, ripples, shards
    var id: Self { self }
    var title: String {
        switch self {
        case .fibers: "Волокна"
        case .ripples: "Кольца"
        case .shards: "Кристалл"
        }
    }
}

private struct ProfileAvatar: View {
    let design: AvatarDesign
    var expression = AvatarExpression()
    var animated = false

    var body: some View {
        if design.form == .eye {
            EyeAvatar(tone:design.tone,texture:design.eyeTexture ?? .fibers,
                      pupil:design.pupil ?? .round,animated:animated)
        } else {
            AvatarFace(design:design,expression:expression)
        }
    }
}

private struct EyeAvatar: UIViewRepresentable {
    let tone: AvatarDesign.Tone
    let texture: EyeTexture
    let pupil: EyePupil
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Model { Model() }

    func makeUIView(context:Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateUIView(_ view:SCNView,context:Context) {
        context.coordinator.apply(tone,texture,pupil)
        let moving = animated && !reduceMotion && scenePhase == .active
        context.coordinator.setMoving(moving)
        view.isPlaying = moving
        view.rendersContinuously = moving
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view:SCNView,coordinator:Model) {
        coordinator.setMoving(false)
        view.isPlaying = false
    }

    final class Model {
        let scene = SCNScene()
        let camera = SCNNode()
        private let globe = SCNNode()
        private let iris = SCNMaterial()
        private var currentKey: String?
        private static let cache = NSCache<NSString,UIImage>()

        init() {
            scene.background.contents = UIColor.clear
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 1.08
            camera.position = SCNVector3(0,0,4)
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(globe)

            let sphere = SCNSphere(radius:1)
            sphere.segmentCount = 144
            let shell = SCNMaterial()
            shell.lightingModel = .physicallyBased
            shell.diffuse.contents = Self.shellColor
            shell.roughness.contents = 0.94
            shell.metalness.contents = 0.0
            shell.shaderModifiers = [.fragment:Self.scleraShading]
            sphere.firstMaterial = shell
            globe.addChildNode(SCNNode(geometry:sphere))

            iris.lightingModel = .physicallyBased
            iris.roughness.contents = 0.89
            iris.specular.contents = UIColor(white:0.10,alpha:1)
            iris.diffuse.mipFilter = .linear
            iris.diffuse.minificationFilter = .linear
            let cap = Self.irisGeometry()
            cap.materials = [iris]
            globe.addChildNode(SCNNode(geometry:cap))

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 510
            scene.rootNode.addChildNode(ambient)
            addLight(at:SCNVector3(-2,4,5),intensity:570,color:UIColor(white:0.92,alpha:1))
            addLight(at:SCNVector3(4,-2,4),intensity:190,color:UIColor(white:0.77,alpha:1))
        }

        private static let shellColor = UIColor(red:0.113,green:0.115,blue:0.119,alpha:1)

        // Broad cloudy detail, very fine grain and light scattering at grazing angles.
        private static let scleraShading = """
        #pragma body
        float3 n = normalize(_surface.normal);
        float grazing = pow(1.0 - clamp(abs(n.z), 0.0, 1.0), 3.9);
        float grain = fract(sin(dot(_surface.position.xy, float2(784.2, 398.6))) * 18471.39);
        float cloud = sin(12.1 * n.x + 8.7 * n.y + sin(9.1 * n.y))
                    * sin(11.7 * n.y - 17.7 * n.x + 2.0 * n.z);
        float strand = pow(0.5 + 0.5 * sin(33.0 * n.x + 22.0 * n.y + 3.1 * sin(8.0 * n.y)), 22.0);
        _output.color.rgb = max(float3(0.0), _output.color.rgb
            + float3(0.0019 * cloud + 0.0040 * (grain - 0.5) - 0.0016 * strand
                       + grazing * (0.19 + 0.075 * grain)));
        """

        private func addLight(at position:SCNVector3,intensity:CGFloat,color:UIColor) {
            let node = SCNNode()
            let light = SCNLight()
            light.type = .directional
            light.intensity = intensity
            light.color = color
            node.position = position
            node.look(at:SCNVector3Zero)
            node.light = light
            scene.rootNode.addChildNode(node)
        }

        func apply(_ tone:AvatarDesign.Tone,_ texture:EyeTexture,_ pupil:EyePupil) {
            let key = "\(tone.rawValue)-\(texture.rawValue)-\(pupil.rawValue)"
            guard key != currentKey else { return }
            currentKey = key
            let cacheKey = key as NSString
            if let image = Self.cache.object(forKey:cacheKey) { iris.diffuse.contents = image; return }
            let image = Self.paintIris(tone:tone,texture:texture,pupil:pupil)
            Self.cache.totalCostLimit = 15_000_000
            Self.cache.setObject(image,forKey:cacheKey,cost:1024 * 1024 * 4)
            iris.diffuse.contents = image
        }

        func setMoving(_ moving:Bool) {
            if !moving {
                globe.removeAction(forKey:"gaze")
                globe.eulerAngles = SCNVector3Zero
                return
            }
            guard globe.action(forKey:"gaze") == nil else { return }
            let looks: [(CGFloat,CGFloat,TimeInterval,TimeInterval)] = [
                (0.11,-0.58,0.43,0.42), (-0.24,0.39,0.52,0.48), (0.42,0.55,0.40,0.31),
                (-0.40,-0.39,0.49,0.56), (0.03,0.05,0.59,0.88)
            ]
            let moves = looks.flatMap { pitch,yaw,duration,hold -> [SCNAction] in
                let move = SCNAction.rotateTo(x:pitch,y:yaw,z:0,duration:duration,usesShortestUnitArc:true)
                move.timingMode = .easeInEaseOut
                return [move,.wait(duration:hold)]
            }
            globe.runAction(.repeatForever(.sequence([.wait(duration:0.55)] + moves)),forKey:"gaze")
        }

        private static func irisGeometry() -> SCNGeometry {
            let rings = 28
            let slices = 96
            let radius = Float(0.555)
            var positions: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var uv: [CGPoint] = []
            var triangles: [UInt16] = []
            for ring in 0...rings {
                let r = radius * Float(ring) / Float(rings)
                for slice in 0..<slices {
                    let angle = Float(slice) * 2 * .pi / Float(slices)
                    let x = r * cos(angle), y = r * sin(angle)
                    let normalZ = sqrt(1 - r*r)
                    positions.append(SCNVector3(x,y,normalZ+0.0025))
                    normals.append(SCNVector3(x,y,normalZ))
                    uv.append(CGPoint(x:Double(0.5+x/(2*radius)),y:Double(0.5-y/(2*radius))))
                    guard ring > 0 else { continue }
                    let inner = UInt16((ring-1)*slices+slice)
                    let innerNext = UInt16((ring-1)*slices+(slice+1)%slices)
                    let outer = UInt16(ring*slices+slice)
                    let outerNext = UInt16(ring*slices+(slice+1)%slices)
                    triangles.append(contentsOf:[inner,outer,outerNext,inner,outerNext,innerNext])
                }
            }
            let data = triangles.withUnsafeBufferPointer { Data(buffer:$0) }
            return SCNGeometry(sources:[SCNGeometrySource(vertices:positions),
                                        SCNGeometrySource(normals:normals),
                                        SCNGeometrySource(textureCoordinates:uv)],
                               elements:[SCNGeometryElement(data:data,primitiveType:.triangles,
                                   primitiveCount:triangles.count/3,bytesPerIndex:MemoryLayout<UInt16>.size)])
        }

        private static func paintIris(tone:AvatarDesign.Tone,texture:EyeTexture,pupil:EyePupil) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let edge: CGFloat = 1024
            return UIGraphicsImageRenderer(size:CGSize(width:edge,height:edge),format:format).image { renderer in
                let ctx = renderer.cgContext
                let center = CGPoint(x:edge/2,y:edge/2)
                let radius = edge/2
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                UIColor(tone.color).getRed(&red,green:&green,blue:&blue,alpha:&alpha)
                if pupil == .vortex {
                    red = 0.57 + red*0.26
                    green *= 0.24
                    blue *= 0.30
                }
                func tint(_ gain:CGFloat,_ opacity:CGFloat = 1) -> CGColor {
                    UIColor(red:min(1,red*gain),green:min(1,green*gain),blue:min(1,blue*gain),alpha:opacity).cgColor
                }
                let shell = shellColor.cgColor
                ctx.setFillColor(shell)
                ctx.fill(CGRect(x:0,y:0,width:edge,height:edge))
                if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),
                                             colors:[tint(0.10),tint(0.24),tint(0.20),tint(0.28),tint(0.105),shell] as CFArray,
                                             locations:[0,0.32,0.48,0.69,0.91,1]) {
                    ctx.drawRadialGradient(gradient,startCenter:center,startRadius:0,endCenter:center,endRadius:radius,
                                           options:[.drawsAfterEndLocation])
                }
                func point(_ angle:CGFloat,_ distance:CGFloat) -> CGPoint {
                    CGPoint(x:center.x+cos(angle)*distance*radius,y:center.y+sin(angle)*distance*radius)
                }
                var seed: UInt32 = 683115
                func noise() -> CGFloat {
                    seed = 1664525 &* seed &+ 1013904223
                    return CGFloat(seed >> 8) / 16777216
                }
                for i in 0..<3400 {
                    let angle = CGFloat(i) * 2 * .pi / 3400 + noise()*0.018
                    let bundle = 0.5 + 0.5 * sin(41*angle + 1.9*sin(13*angle))
                    let r0 = 0.22 + noise()*0.59
                    let r1 = min(0.94,r0+0.065+noise()*0.34)
                    let bend = (noise()-0.5) * (texture == .shards ? 0.22 : 0.11)
                    ctx.setStrokeColor(i.isMultiple(of:4) ? UIColor.black.withAlphaComponent(0.12+noise()*0.20).cgColor
                                                          : tint(0.34+noise()*0.33,0.08+bundle*0.13))
                    ctx.setLineWidth(0.40+noise()*(texture == .shards ? 2.4 : 1.6))
                    ctx.move(to:point(angle,r0))
                    if texture == .shards { ctx.addLine(to:point(angle+bend,r1)) }
                    else { ctx.addQuadCurve(to:point(angle+bend,r1),control:point(angle-bend,r0+(r1-r0)*0.54)) }
                    ctx.strokePath()
                }
                for index in 0..<170 {
                    let angle = CGFloat(index) * 2 * .pi / 170 + noise()*0.07
                    let collar = 0.43 + 0.035*sin(angle*9) + 0.025*sin(angle*21)
                    let spot = point(angle,collar + (noise()-0.5)*0.09)
                    let length = 1.5 + noise()*12
                    ctx.saveGState()
                    ctx.translateBy(x:spot.x,y:spot.y)
                    ctx.rotate(by:angle + (noise()-0.5)*0.75)
                    ctx.setFillColor(UIColor.black.withAlphaComponent(0.07+noise()*0.19).cgColor)
                    ctx.fillEllipse(in:CGRect(x:-length/2,y:-1,width:length,height:2+noise()*3))
                    ctx.restoreGState()
                }
                for ring in 0..<(texture == .ripples ? 12 : 3) {
                    let r = radius*(texture == .ripples ? 0.40+CGFloat(ring)*0.041 : 0.48+CGFloat(ring)*0.18)
                    ctx.setLineWidth(ring.isMultiple(of:2) ? 1.9 : 0.7)
                    ctx.setStrokeColor(tint(0.47,texture == .ripples ? 0.21 : 0.08))
                    ctx.strokeEllipse(in:CGRect(x:center.x-r,y:center.y-r,width:2*r,height:2*r))
                }
                ctx.setFillColor(UIColor(white:0.007,alpha:1).cgColor)
                func pupilOval(x:CGFloat,y:CGFloat,rx:CGFloat,ry:CGFloat) {
                    ctx.fillEllipse(in:CGRect(x:center.x+(x-rx)*radius,y:center.y+(y-ry)*radius,
                                             width:2*rx*radius,height:2*ry*radius))
                }
                switch pupil {
                case .round: pupilOval(x:0,y:0,rx:0.30,ry:0.30)
                case .double:
                    pupilOval(x:-0.24,y:0,rx:0.18,ry:0.25)
                    pupilOval(x:0.24,y:0,rx:0.18,ry:0.25)
                case .star:
                    let path = CGMutablePath()
                    for n in 0..<8 {
                        let a = CGFloat(n) * .pi/4 - .pi/2
                        let p = point(a,n.isMultiple(of:2) ? 0.51 : 0.16)
                        if n == 0 { path.move(to:p) } else { path.addLine(to:p) }
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.fillPath()
                case .vortex:
                    pupilOval(x:0,y:0,rx:0.25,ry:0.25)
                    for lane in 0..<3 {
                        let a = CGFloat(lane) * 2 * .pi/3
                        let path = CGMutablePath()
                        path.move(to:point(a-0.76,0.79))
                        path.addQuadCurve(to:point(a+0.39,0.49),control:point(a+0.39,0.95))
                        path.addQuadCurve(to:point(a-0.76,0.79),control:point(a+0.11,0.69))
                        path.closeSubpath()
                        ctx.addPath(path)
                        ctx.fillPath()
                    }
                }
            }
        }
    }
}
