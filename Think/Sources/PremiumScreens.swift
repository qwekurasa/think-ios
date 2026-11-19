import SwiftUI

struct ThinkActionStyle: ButtonStyle {
    var filled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(filled ? Theme.panel : Theme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Theme.line, lineWidth: filled ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SoftPurpleAtmosphere: View {
    var bottom = true
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.paper
                RadialGradient(
                    colors: [
                        Theme.purpleLight.opacity(0.27),
                        Theme.purpleLight.opacity(0.1),
                        .clear
                    ],
                    center: bottom ? .bottom : .top,
                    startRadius: 0,
                    endRadius: max(400, geometry.size.height * 0.73)
                )
            }
        }.ignoresSafeArea().allowsHitTesting(false)
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
            SoftPurpleAtmosphere(bottom: true)
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
            if index == 1 && activeTab == 1 {
                store.returnToAllIdeas()
            }
            withAnimation(.easeInOut(duration: 0.18)) { activeTab = index }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: .regular))
                Text(caption).font(.system(size: 10, weight: .medium))
            }
            .frame(width: 56, height: 43)
            .foregroundStyle(activeTab == index ? Theme.purple : Theme.muted)
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

    private let ink = Color(red: 0.055, green: 0.047, blue: 0.075)
    private let muted = Color(red: 0.49, green: 0.46, blue: 0.53)

    var body: some View {
        GeometryReader { geometry in
            let orbSide = min(min(geometry.size.width * 0.90, geometry.size.height * 0.56), 355)

            VStack(spacing: 0) {
                ThinkWordmark()
                    .frame(width: 192, height: 46)
                    .padding(.top, 14)

                Spacer(minLength: 24)

                Button(action: voice) {
                    ThinkLivingOrb()
                        .frame(width: orbSide, height: orbSide)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("О чём ты думаешь? Нажми на шар, чтобы начать запись идеи")

                Spacer(minLength: 23)

                VStack(spacing: 10) {
                    Text("О чём ты думаешь?")
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .tracking(-0.75)
                        .foregroundStyle(ink)

                    Text("Нажми на шарик, чтобы поймать мысль.")
                        .font(.system(size: 14, weight: .regular))
                        .tracking(0.05)
                        .foregroundStyle(muted)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)

                Spacer(minLength: 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.995, green: 0.991, blue: 0.998).ignoresSafeArea())
    }
}

/// Original vector lettering in the geometric, monoline spirit of the
/// reference wordmark. This is not a font file or a bitmap.
private struct ThinkWordmark: View {
    var body: some View {
        Canvas(opaque: false) { context, size in
            let scale = min(size.width / 294.0, size.height / 70.0)
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            var letters = Path()

            // t
            letters.move(to: CGPoint(x: 26, y: 9))
            letters.addLine(to: CGPoint(x: 26, y: 58))
            letters.move(to: CGPoint(x: 9, y: 25))
            letters.addLine(to: CGPoint(x: 43, y: 25))

            // h: a straight ascender, circular shoulder, clean terminal.
            letters.move(to: CGPoint(x: 59, y: 8))
            letters.addLine(to: CGPoint(x: 59, y: 59))
            letters.move(to: CGPoint(x: 59, y: 39))
            letters.addCurve(to: CGPoint(x: 98, y: 40),
                             control1: CGPoint(x: 65, y: 16),
                             control2: CGPoint(x: 98, y: 17))
            letters.addLine(to: CGPoint(x: 98, y: 59))

            // i
            letters.move(to: CGPoint(x: 120, y: 27))
            letters.addLine(to: CGPoint(x: 120, y: 59))

            // n
            letters.move(to: CGPoint(x: 144, y: 27))
            letters.addLine(to: CGPoint(x: 144, y: 59))
            letters.move(to: CGPoint(x: 144, y: 40))
            letters.addCurve(to: CGPoint(x: 184, y: 40),
                             control1: CGPoint(x: 151, y: 17),
                             control2: CGPoint(x: 184, y: 17))
            letters.addLine(to: CGPoint(x: 184, y: 59))

            // k: long stem and open geometric diagonals.
            letters.move(to: CGPoint(x: 209, y: 8))
            letters.addLine(to: CGPoint(x: 209, y: 59))
            letters.move(to: CGPoint(x: 245, y: 27))
            letters.addLine(to: CGPoint(x: 210, y: 45))
            letters.addLine(to: CGPoint(x: 247, y: 59))

            let black = Color(red: 0.035, green: 0.035, blue: 0.044)
            context.stroke(
                letters.applying(transform),
                with: .color(black),
                style: StrokeStyle(lineWidth: 9.4 * scale,
                                   lineCap: .round, lineJoin: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 115, y: 7, width: 10, height: 10)).applying(transform),
                with: .color(black)
            )
            context.fill(
                sparkle(center: CGPoint(x: 264, y: 15), size: 17).applying(transform),
                with: .color(black)
            )
            context.fill(
                sparkle(center: CGPoint(x: 284, y: 2), size: 6).applying(transform),
                with: .color(black)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("think")
    }

    private func sparkle(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - size))
        path.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y),
                          control: CGPoint(x: center.x + size * 0.21, y: center.y - size * 0.21))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size),
                          control: CGPoint(x: center.x + size * 0.21, y: center.y + size * 0.21))
        path.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y),
                          control: CGPoint(x: center.x - size * 0.21, y: center.y + size * 0.21))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size),
                          control: CGPoint(x: center.x - size * 0.21, y: center.y - size * 0.21))
        path.closeSubpath()
        return path
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
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17))
                            .frame(width: 40, height: 44)
                    }
                    Spacer()
                    Text(existing == nil ? "НОВАЯ МЫСЛЬ" : "РЕДАКТИРОВАТЬ")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15))
                            .frame(width: 40, height: 44)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 17).padding(.top, 13)
                VStack(alignment: .leading, spacing: 14) {
                    Text(existing == nil ? "Опиши свою\nидею..." : "Развивай\nэту мысль...")
                        .font(.system(size: 33))
                        .foregroundStyle(Theme.muted.opacity(0.70))
                        .tracking(-1)
                    Rectangle()
                        .fill(Theme.purple.opacity(focused ? 0.55 : 0.16))
                        .frame(width: focused ? 48 : 20, height: 2)
                        .animation(.easeInOut(duration: 0.33), value: focused)
                    ZStack(alignment: .topLeading) {
                        if value.isEmpty {
                            Text("Напиши всё, что приходит в голову.")
                                .font(.system(size: 19))
                                .foregroundStyle(Theme.muted.opacity(0.55))
                                .padding(.top, 9).padding(.leading, 4)
                        }
                        TextEditor(text: $value)
                            .font(.system(size: 21, weight: .regular))
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
                        Image(systemName: "mic")
                            .font(.system(size: 19))
                            .frame(width: 53, height: 52)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).disabled(onSwitchToVoice == nil)
                        .opacity(onSwitchToVoice == nil ? 0.35 : 1)
                    Button {
                        guard hasText else { return }
                        store.save(value, existing: existing)
                        if let onFinished { onFinished() } else { dismiss() }
                    } label: {
                        Text("Сохранить")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
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
                        .font(.system(size: 34, weight: .regular, design: .serif))
                    Text("\(store.ideas.count) сохранено")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .frame(width: 43, height: 43)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                }.foregroundStyle(Theme.ink)
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                TextField("Найти мысль", text: $query)
                    .textInputAutocapitalization(.never)
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.muted)
            .padding(15)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))

            if store.ideas.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    ThinkStar().fill(Theme.purple).frame(width: 42, height: 42)
                    Text("Тут появятся твои идеи")
                        .font(.system(size: 22, design: .serif))
                    Text("Начни с одной маленькой мысли.")
                        .font(.system(size: 14))
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
                                        ThinkStar().fill(Theme.purple).frame(width: 14, height: 14)
                                        Text(store.energyFor(idea).pinned ? "ВАЖНАЯ ИДЕЯ" : "ИДЕЯ")
                                            .font(.system(size: 10, weight: .medium))
                                            .tracking(1.2)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .foregroundStyle(Theme.muted)
                                    Text(idea.text)
                                        .font(.system(size: 17))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading).lineLimit(4)
                                    HStack(spacing: 8) {
                                        Text(store.energyFor(idea).lastTouched, style: .date)
                                        Spacer()
                                        if store.isFading(idea) {
                                            Label("Угасает", systemImage: "hourglass")
                                                .foregroundStyle(Theme.purple)
                                        } else {
                                            Text("ещё \(max(1, Int(ceil(store.remaining(idea) / 86400)))) дн.")
                                        }
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(19)
                                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 0.8))
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(idea.id)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
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
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)

                VStack(spacing: 14) {
                    ThinkStar().fill(Theme.purple)
                        .frame(width: 51, height: 51)
                        .shadow(color: Theme.purple.opacity(0.22), radius: 22)
                    Text("\(store.stars)")
                        .font(.system(size: 73, weight: .light, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("звёзд за живые идеи")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))

                if let feedback {
                    Text(feedback)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.purple)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Как растут звёзды")
                        .font(.system(size: 23, weight: .regular, design: .serif))
                    rule("Новая идея", "+10", "plus")
                    rule("Вернуться через сутки", "+2", "arrow.uturn.backward")
                    rule("Изменить текст идеи", "+3", "pencil")
                    Text("Если к идее не возвращаться 7 дней, она угасает и переходит в архив, а заработанные ею звёзды списываются. На шестой день идея подсвечивается в списке.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 15) {
                    Text("Защита идей")
                        .font(.system(size: 23, weight: .regular, design: .serif))
                    if store.ideas.isEmpty {
                        Text("Создай первую идею, чтобы управлять её жизнью.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(store.ideas) { idea in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 10) {
                                ThinkStar().fill(Theme.purple)
                                    .frame(width: 12, height: 12).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(idea.text)
                                        .font(.system(size: 15, weight: .medium))
                                        .lineLimit(2)
                                    Text(store.isFading(idea)
                                         ? "Идея угасает — осталось меньше суток"
                                         : "Осталось примерно \(max(1, Int(ceil(store.remaining(idea) / 86400)))) дн.")
                                        .font(.system(size: 11))
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
                                Label("Важная идея", systemImage: "pin.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.purple)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Theme.line, lineWidth: 0.8)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Поделиться идеей")
                        .font(.system(size: 23, weight: .regular, design: .serif))
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .foregroundStyle(Theme.purple)
                            .font(.system(size: 25, weight: .light))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("QR-коды бесплатны")
                                .font(.system(size: 15, weight: .medium))
                            Text("Пурпурное оформление доступно каждому")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.purple)
                    }
                    .padding(16)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                }

                if !store.faded.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Архив угасших")
                            .font(.system(size: 23, weight: .regular, design: .serif))
                        Text("Идеи исчезли из твоего списка, но ты ещё можешь вернуть их.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                        ForEach(store.faded) { fadedIdea in
                            HStack(spacing: 12) {
                                Text(fadedIdea.idea.text)
                                    .font(.system(size: 14))
                                    .lineLimit(2)
                                Spacer()
                                Button("Вернуть · 60") {
                                    if store.recover(fadedIdea.id) {
                                        feedback = "Идея восстановлена. У неё снова 7 дней."
                                    }
                                }
                                .disabled(store.stars < 60)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.purple)
                            }
                            .padding(.vertical, 12)
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                Text("Звёзды можно тратить только при достаточном балансе. Закрепление не предотвращает угасание; для этого нужна защита.")
                    .font(.system(size: 12))
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
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
        }
        .disabled(store.stars < cost)
        .opacity(store.stars < cost ? 0.45 : 1)
        .buttonStyle(.plain)
    }

    private func rule(_ title: String, _ amount: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(Theme.purple).frame(width: 30)
            Text(title).font(.system(size: 14))
            Spacer()
            Text(amount).font(.system(size: 14)).foregroundStyle(Theme.muted)
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 23) {
                            HStack(spacing: 8) {
                                ThinkStar().fill(Theme.purple)
                                    .frame(width: 17, height: 17)
                                Text("ТВОЯ ИДЕЯ")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.7)
                                    .foregroundStyle(Theme.muted)
                            }.padding(.top, 34)
                            Text(current.text)
                                .font(.system(size: 23, weight: .regular))
                                .lineSpacing(7)
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                            Divider().overlay(Theme.line)
                                .padding(.top, 15)
                            Text(current.createdAt, format: .dateTime.day().month(.wide).year())
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                            HStack {
                                Image(systemName: "hourglass")
                                Text(store.isFading(current) ? "Идея скоро угаснет" :
                                    "Идея активна — возвращайся к ней раз в неделю")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(store.isFading(current) ? Theme.purple : Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 29)
                    }
                    HStack(spacing: 10) {
                        Button {
                            editing = true
                        } label: {
                            Label("Редактировать", systemImage: "pencil")
                        }.buttonStyle(ThinkActionStyle())
                        Button { qr = true } label: {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }.buttonStyle(ThinkActionStyle(filled: true))
                    }.padding(.horizontal, 26).padding(.bottom, 22)
                }
            }
            .navigationTitle("Идея")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: current.text) {
                            Label("Отправить текст", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { deleteConfirm = true } label: {
                            Label("Удалить идею", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
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
