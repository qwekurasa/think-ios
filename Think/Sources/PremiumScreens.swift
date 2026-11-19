import SwiftUI

struct ThinkActionStyle: ButtonStyle {
    var filled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SketchFont.regular(16))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.paper, in: SketchRoundedRectangle(cornerRadius: 12, seed: 3))
            .overlay(SketchRoundedRectangle(cornerRadius: 12, seed: 7)
                .stroke(Theme.ink.opacity(filled ? 0.82 : 0.62), lineWidth: 1.15))
            .overlay(SketchRoundedRectangle(cornerRadius: 12, wobble: 1.25, seed: 12)
                .stroke(Theme.muted.opacity(0.36), lineWidth: 0.65).padding(1.4))
            .opacity(configuration.isPressed ? 0.66 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftPurpleAtmosphere: View {
    var bottom = true
    var body: some View {
        Color.white.ignoresSafeArea().allowsHitTesting(false)
    }
}

enum ThinkEntry: String, Identifiable {
    case voice, text
    var id: String { rawValue }
}

struct PremiumRootScreen: View {
    @EnvironmentObject private var store: IdeaStore
    @State private var activeTab = 0
    @State private var entry: ThinkEntry?
    @State private var chosenIdea: Idea?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                if activeTab == 0 {
                    PremiumHomeScreen(
                        voice: { entry = .voice }
                    )
                } else if activeTab == 1 {
                    PremiumIdeasScreen(
                        onCreate: { entry = .text },
                        onSelect: { chosenIdea = $0 }
                    )
                } else {
                    PremiumStarsScreen()
                }
                HStack {
                    tab("house", "Главная", 0)
                    Spacer()
                    tab("square.stack", "Идеи", 1)
                    Spacer()
                    tab("sparkle", "Звёзды", 2)
                }
                .padding(.horizontal, 50)
                .padding(.top, 10)
                .padding(.bottom, 11)
                .background(Theme.paper.opacity(0.86))
                .overlay(alignment: .top) {
                    Theme.line.frame(height: 0.5).opacity(0.65)
                }
            }
        }
        .fullScreenCover(item: $entry) { choice in
            ThinkCaptureFlow(start: choice) {
                // A single completed capture always returns to the ideas list.
                entry = nil
                activeTab = 1
                store.returnToAllIdeas()
            }
            .environmentObject(store)
        }
        .fullScreenCover(item: $chosenIdea) { idea in
            PremiumIdeaDetail(idea: idea)
                .environmentObject(store)
        }
        .onAppear {
            store.refreshLifecycle()
            if activeTab == 1 { store.returnToAllIdeas() }
        }
        .onChange(of: activeTab) { _, selected in
            if selected == 1 { store.returnToAllIdeas() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            store.refreshLifecycle()
            if activeTab == 1 { store.returnToAllIdeas() }
        }
    }

    private func tab(_ symbol: String, _ caption: String, _ index: Int) -> some View {
        Button {
            if index == 1 && activeTab == 1 { store.returnToAllIdeas() }
            withAnimation(.easeInOut(duration: 0.18)) { activeTab = index }
        } label: {
            VStack(spacing: 4) {
                SketchGlyph(name: symbol, size: 22, lineWidth: 1.55,
                            color: activeTab == index ? Theme.ink : Theme.muted)
                Text(caption).font(SketchFont.regular(11))
            }
            .frame(width: 62, height: 48)
            .foregroundStyle(activeTab == index ? Theme.ink : Theme.muted)
        }.buttonStyle(.plain)
    }
}

struct ThinkCaptureFlow: View {
    @Environment(\.dismiss) private var dismiss
    let onCompleted: () -> Void
    @State private var mode: ThinkEntry
    @State private var draft: String = ""
    @State private var completed = false

    init(start: ThinkEntry, onCompleted: @escaping () -> Void) {
        self.onCompleted = onCompleted
        _mode = State(initialValue: start)
    }

    var body: some View {
        Group {
            if mode == .voice {
                PremiumVoiceScreen(
                    initialText: draft,
                    onSwitchToText: { text in
                        draft = text
                        mode = .text
                    },
                    onFinished: finish,
                    onCancel: { dismiss() }
                )
            } else {
                PremiumTextEditor(
                    initialText: draft,
                    existing: nil,
                    onFinished: finish,
                    onCancel: { dismiss() },
                    onSwitchToVoice: { text in
                        draft = text
                        mode = .voice
                    }
                )
            }
        }
        .id(mode)
        .background(Theme.paper.ignoresSafeArea())
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        onCompleted()
        dismiss()
    }
}

struct PremiumHomeScreen: View {
    let voice: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let orbSide = min(min(geometry.size.width * 0.88, geometry.size.height * 0.62), 340)
            ZStack {
                Color.white
                Button(action: voice) {
                    ThinkLivingOrb()
                        .frame(width: orbSide, height: orbSide)
                        .contentShape(SketchOval(wobble: 2.0, seed: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Нажми на нарисованный шар, чтобы записать идею")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

struct PremiumTextEditor: View {
    @EnvironmentObject private var store: IdeaStore
    @Environment(\.dismiss) private var dismiss
    let existing: Idea?
    @State private var value: String
    let onFinished: (() -> Void)?
    let onCancel: (() -> Void)?
    let onSwitchToVoice: ((String) -> Void)?
    @FocusState private var focused: Bool

    init(initialText: String, existing: Idea?, onFinished: (() -> Void)? = nil,
         onCancel: (() -> Void)? = nil, onSwitchToVoice: ((String) -> Void)? = nil) {
        self.existing = existing
        self.onFinished = onFinished
        self.onCancel = onCancel
        self.onSwitchToVoice = onSwitchToVoice
        _value = State(initialValue: initialText)
    }

    private var hasText: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            SoftPurpleAtmosphere(bottom: false)
            VStack(spacing: 0) {
                HStack {
                    Button { close() } label: {
                        SketchGlyph(name: "chevron.left", size: 19)
                            .font(.custom("Noteworthy-Light", size: 17))
                            .frame(width: 40, height: 44)
                    }
                    Spacer()
                    Text(existing == nil ? "НОВАЯ МЫСЛЬ" : "РЕДАКТИРОВАТЬ")
                        .font(.custom("Noteworthy-Light", size: 10))
                        .tracking(2)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button { close() } label: {
                        SketchGlyph(name: "xmark", size: 19)
                            .font(.custom("Noteworthy-Light", size: 15))
                            .frame(width: 40, height: 44)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 17).padding(.top, 13)
                VStack(alignment: .leading, spacing: 14) {
                    Text(existing == nil ? "Опиши свою\nидею..." : "Развивай\nэту мысль...")
                        .font(.custom("Noteworthy-Light", size: 33))
                        .foregroundStyle(Theme.muted.opacity(0.70))
                        .tracking(-1)
                    SketchRule(seed: 8, amplitude: 1.0)
                        .stroke(Theme.ink.opacity(focused ? 0.72 : 0.25), lineWidth: 1.1)
                        .frame(width: focused ? 48 : 20, height: 3)
                        .animation(.easeInOut(duration: 0.33), value: focused)
                    ZStack(alignment: .topLeading) {
                        if value.isEmpty {
                            Text("Напиши всё, что приходит в голову.")
                                .font(.custom("Noteworthy-Light", size: 19))
                                .foregroundStyle(Theme.muted.opacity(0.55))
                                .padding(.top, 9).padding(.leading, 4)
                        }
                        TextEditor(text: $value)
                            .font(.custom("Noteworthy-Light", size: 21))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(5)
                            .scrollContentBackground(.hidden)
                            .focused($focused)
                            .accessibilityLabel("Текст идеи")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, 53)
                .padding(.horizontal, 29)

                HStack(spacing: 10) {
                    Button { focused = false; onSwitchToVoice?(value) } label: {
                        SketchGlyph(name: "mic", size: 22)
                            .font(.custom("Noteworthy-Light", size: 19))
                            .frame(width: 53, height: 52)
                            .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).disabled(onSwitchToVoice == nil)
                        .opacity(onSwitchToVoice == nil ? 0.35 : 1)
                    Button {
                        guard hasText else { return }
                        store.save(value, existing: existing)
                        if let onFinished { onFinished() } else { dismiss() }
                    } label: {
                        Text("Сохранить")
                            .font(.custom("Noteworthy-Light", size: 15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain).disabled(!hasText)
                    .opacity(hasText ? 1 : 0.42)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 28).padding(.bottom, 17)
            }
        }
        .onAppear { focused = true }
    }
    private func close() {
        if let onCancel { onCancel() } else { dismiss() }
    }
}

struct PremiumIdeasScreen: View {
    @EnvironmentObject private var store: IdeaStore
    let onCreate: () -> Void
    let onSelect: (Idea) -> Void
    @State private var query = ""
    private var ideas: [Idea] {
        store.ideas
            .filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
            .sorted { store.energyFor($0).lastTouched > store.energyFor($1).lastTouched }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Твои идеи")
                        .font(.custom("Noteworthy-Light", size: 34))
                    Text("\(store.ideas.count) сохранено")
                        .font(.custom("Noteworthy-Light", size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(action: onCreate) {
                    SketchGlyph(name: "plus")
                        .font(.custom("Noteworthy-Light", size: 20))
                        .frame(width: 43, height: 43)
                        .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 12))
                }.foregroundStyle(Theme.ink)
            }
            HStack(spacing: 12) {
                SketchGlyph(name: "magnifyingglass", size: 18)
                TextField("Найти мысль", text: $query)
                    .textInputAutocapitalization(.never)
            }
            .font(.custom("Noteworthy-Light", size: 14))
            .foregroundStyle(Theme.muted)
            .padding(15)
            .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 11))

            if store.ideas.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    ThinkStar().stroke(Theme.ink, lineWidth: 1.2).frame(width: 42, height: 42)
                    Text("Тут появятся твои идеи")
                        .font(.custom("Noteworthy-Light", size: 22))
                    Text("Начни с одной маленькой мысли.")
                        .font(.custom("Noteworthy-Light", size: 14))
                        .foregroundStyle(Theme.muted)
                    Button("Создать идею", action: onCreate)
                        .buttonStyle(ThinkActionStyle())
                        .padding(.top, 14)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(ideas) { idea in
                            Button { onSelect(idea) } label: {
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack {
                                        ThinkStar().stroke(Theme.ink, lineWidth: 1.2).frame(width: 14, height: 14)
                                        Text(store.energyFor(idea).pinned ? "ВАЖНАЯ ИДЕЯ" : "ИДЕЯ")
                                            .font(.custom("Noteworthy-Light", size: 10))
                                            .tracking(1.2)
                                        Spacer()
                                        SketchGlyph(name: "arrow.up.right", size: 17)
                                    }
                                    .foregroundStyle(Theme.muted)
                                    Text(idea.text)
                                        .font(.custom("Noteworthy-Light", size: 17))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading).lineLimit(4)
                                    HStack(spacing: 8) {
                                        Text(store.energyFor(idea).lastTouched, style: .date)
                                        Spacer()
                                        if store.isFading(idea) {
                                            SketchLabel("Угасает", symbol: "hourglass")
                                                .foregroundStyle(Theme.purple)
                                        } else {
                                            Text("ещё \(max(1, Int(ceil(store.remaining(idea) / 86400)))) дн.")
                                        }
                                    }
                                    .font(.custom("Noteworthy-Light", size: 11))
                                    .foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(19)
                                .background(Theme.paper, in: SketchRoundedRectangle(cornerRadius: 14))
                                .overlay(SketchRoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 0.8))
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(idea.id)
                                } label: {
                                    SketchLabel("Удалить", symbol: "trash")
                                }
                            }
                        }
                    }.padding(.bottom, 15)
                }.scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 27)
        .padding(.top, 32)
    }
}

struct PremiumStarsScreen: View {
    @EnvironmentObject private var store: IdeaStore
    @State private var feedback: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Text("Твои звёзды")
                    .font(.custom("Noteworthy-Light", size: 34))
                    .foregroundStyle(Theme.ink)

                VStack(spacing: 14) {
                    ThinkStar().stroke(Theme.ink, lineWidth: 1.2)
                        .frame(width: 51, height: 51)
                        
                    Text("\(store.stars)")
                        .font(.custom("Noteworthy-Light", size: 73))
                        .foregroundStyle(Theme.ink)
                    Text("звёзд за живые идеи")
                        .font(.custom("Noteworthy-Light", size: 13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 14))

                if let feedback {
                    Text(feedback)
                        .font(.custom("Noteworthy-Light", size: 13))
                        .foregroundStyle(Theme.purple)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 11))
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Как растут звёзды")
                        .font(.custom("Noteworthy-Light", size: 23))
                    rule("Новая идея", "+10", "plus")
                    rule("Вернуться через сутки", "+2", "arrow.uturn.backward")
                    rule("Изменить текст идеи", "+3", "pencil")
                    Text("Если к идее не возвращаться 7 дней, она угасает и переходит в архив, а заработанные ею звёзды списываются. На шестой день идея подсвечивается в списке.")
                        .font(.custom("Noteworthy-Light", size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 15) {
                    Text("Защита идей")
                        .font(.custom("Noteworthy-Light", size: 23))
                    if store.ideas.isEmpty {
                        Text("Создай первую идею, чтобы управлять её жизнью.")
                            .font(.custom("Noteworthy-Light", size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(store.ideas) { idea in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 10) {
                                ThinkStar().stroke(Theme.ink, lineWidth: 1.2)
                                    .frame(width: 12, height: 12).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(idea.text)
                                        .font(.custom("Noteworthy-Light", size: 15))
                                        .lineLimit(2)
                                    Text(store.isFading(idea)
                                         ? "Идея угасает — осталось меньше суток"
                                         : "Осталось примерно \(max(1, Int(ceil(store.remaining(idea) / 86400)))) дн.")
                                        .font(.custom("Noteworthy-Light", size: 11))
                                        .foregroundStyle(store.isFading(idea) ? Theme.purple : Theme.muted)
                                }
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                shopButton("7 дней · 30", cost: 30) {
                                    if store.protect(idea.id, days: 7, cost: 30) {
                                        feedback = "Идея защищена ещё на 7 дней."
                                    }
                                }
                                shopButton("30 дней · 80", cost: 80) {
                                    if store.protect(idea.id, days: 30, cost: 80) {
                                        feedback = "Идея защищена ещё на 30 дней."
                                    }
                                }
                            }
                            if !store.energyFor(idea).pinned {
                                shopButton("Отметить важной · 20", cost: 20) {
                                    if store.pin(idea.id) {
                                        feedback = "Идея отмечена как важная."
                                    }
                                }
                            } else {
                                SketchLabel("Важная идея", symbol: "pin.fill")
                                    .font(.custom("Noteworthy-Light", size: 12))
                                    .foregroundStyle(Theme.purple)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.paper, in: SketchRoundedRectangle(cornerRadius: 13))
                        .overlay(
                            SketchRoundedRectangle(cornerRadius: 13)
                                .stroke(Theme.line, lineWidth: 0.8)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Поделиться идеей")
                        .font(.custom("Noteworthy-Light", size: 23))
                    HStack(spacing: 12) {
                        SketchGlyph(name: "qrcode", size: 24)
                            .foregroundStyle(Theme.purple)
                            .font(.custom("Noteworthy-Light", size: 25))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("QR-коды бесплатны")
                                .font(.custom("Noteworthy-Light", size: 15))
                            Text("QR-коды бесплатны для всех")
                                .font(.custom("Noteworthy-Light", size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        SketchGlyph(name: "checkmark.circle.fill", size: 22)
                            .foregroundStyle(Theme.purple)
                    }
                    .padding(16)
                    .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 12))
                }

                if !store.faded.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Архив угасших")
                            .font(.custom("Noteworthy-Light", size: 23))
                        Text("Идеи исчезли из твоего списка, но ты ещё можешь вернуть их.")
                            .font(.custom("Noteworthy-Light", size: 12))
                            .foregroundStyle(Theme.muted)
                        ForEach(store.faded) { fadedIdea in
                            HStack(spacing: 12) {
                                Text(fadedIdea.idea.text)
                                    .font(.custom("Noteworthy-Light", size: 14))
                                    .lineLimit(2)
                                Spacer()
                                Button("Вернуть · 60") {
                                    if store.recover(fadedIdea.id) {
                                        feedback = "Идея восстановлена. У неё снова 7 дней."
                                    }
                                }
                                .disabled(store.stars < 60)
                                .font(.custom("Noteworthy-Light", size: 12))
                                .foregroundStyle(Theme.purple)
                            }
                            .padding(.vertical, 12)
                            SketchRule(seed: 4).stroke(Theme.line, lineWidth: 1).frame(height: 2)
                        }
                    }
                }
                Text("Звёзды можно тратить только при достаточном балансе. Закрепление не предотвращает угасание; для этого нужна защита.")
                    .font(.custom("Noteworthy-Light", size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(4)
                    .padding(.bottom, 21)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 27)
            .padding(.top, 28)
        }
        .scrollIndicators(.hidden)
        .onAppear { store.refreshLifecycle() }
    }

    private func shopButton(_ label: String, cost: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Noteworthy-Light", size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.panel, in: SketchRoundedRectangle(cornerRadius: 9))
        }
        .disabled(store.stars < cost)
        .opacity(store.stars < cost ? 0.45 : 1)
        .buttonStyle(.plain)
    }

    private func rule(_ title: String, _ amount: String, _ symbol: String) -> some View {
        HStack {
            SketchGlyph(name: symbol, size: 20).frame(width: 30)
            Text(title).font(.custom("Noteworthy-Light", size: 14))
            Spacer()
            Text(amount).font(.custom("Noteworthy-Light", size: 14)).foregroundStyle(Theme.muted)
        }.padding(.vertical, 5)
    }
}

struct PremiumIdeaDetail: View {
    @EnvironmentObject private var store: IdeaStore
    @Environment(\.dismiss) private var dismiss
    let idea: Idea
    @State private var editing = false
    @State private var qr = false
    @State private var deleteConfirm = false

    private var current: Idea {
        store.ideas.first { $0.id == idea.id } ?? idea
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SoftPurpleAtmosphere()
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            SketchGlyph(name: "chevron.left", size: 20)
                                .frame(width: 42, height: 42)
                        }
                        Spacer()
                        Text("ИДЕЯ").font(SketchFont.bold(12)).tracking(2.0)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Menu {
                            ShareLink(item: current.text) {
                                SketchLabel("Отправить текст", symbol: "square.and.arrow.up")
                            }
                            Button(role: .destructive) { deleteConfirm = true } label: {
                                SketchLabel("Удалить идею", symbol: "trash")
                            }
                        } label: {
                            SketchGlyph(name: "ellipsis", size: 22)
                                .frame(width: 42, height: 42)
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 23) {
                            HStack(spacing: 8) {
                                ThinkStar().stroke(Theme.ink, lineWidth: 1.2)
                                    .frame(width: 17, height: 17)
                                Text("ТВОЯ ИДЕЯ")
                                    .font(.custom("Noteworthy-Bold", size: 11))
                                    .tracking(1.7)
                                    .foregroundStyle(Theme.muted)
                            }.padding(.top, 34)
                            Text(current.text)
                                .font(.custom("Noteworthy-Light", size: 23))
                                .lineSpacing(7)
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                            SketchRule(seed: 3).stroke(Theme.line, lineWidth: 1).frame(height: 2)
                                .padding(.top, 15)
                            Text(current.createdAt, format: .dateTime.day().month(.wide).year())
                                .font(.custom("Noteworthy-Light", size: 12))
                                .foregroundStyle(Theme.muted)
                            HStack {
                                SketchGlyph(name: "hourglass", size: 14)
                                Text(store.isFading(current) ? "Идея скоро угаснет" :
                                    "Идея активна — возвращайся к ней раз в неделю")
                            }
                            .font(.custom("Noteworthy-Light", size: 12))
                            .foregroundStyle(store.isFading(current) ? Theme.purple : Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 29)
                    }
                    HStack(spacing: 10) {
                        Button {
                            editing = true
                        } label: {
                            SketchLabel("Редактировать", symbol: "pencil")
                        }.buttonStyle(ThinkActionStyle())
                        Button { qr = true } label: {
                            SketchLabel("Поделиться", symbol: "square.and.arrow.up")
                        }.buttonStyle(ThinkActionStyle(filled: true))
                    }.padding(.horizontal, 26).padding(.bottom, 22)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $editing) {
            PremiumTextEditor(initialText: current.text, existing: current)
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $qr) {
            PremiumQRScreen(text: current.text)
        }
        .onAppear { store.touch(idea.id) }
        .confirmationDialog("Удалить эту идею?", isPresented: $deleteConfirm) {
            Button("Удалить", role: .destructive) {
                store.delete(idea.id)
                dismiss()
            }
        }
    }
}
