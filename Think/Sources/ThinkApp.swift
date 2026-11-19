import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum Theme {
    static let paper = Color(red: 0.997, green: 0.994, blue: 1)
    static let ink = Color(red: 0.17, green: 0.16, blue: 0.21)
    static let muted = Color(red: 0.54, green: 0.52, blue: 0.59)
    static let panel = Color(red: 0.964, green: 0.959, blue: 0.980)
    static let yellow = Color(red: 0.63, green: 0.30, blue: 0.90)
    static let purple = Color(red: 0.61, green: 0.24, blue: 0.91)
    static let purpleLight = Color(red: 0.91, green: 0.79, blue: 0.99)
    static let line = Color(red: 0.90, green: 0.89, blue: 0.92)
}

struct ThinkStar: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.02))
        p.addQuadCurve(to: CGPoint(x: w * 0.67, y: h * 0.36), control: CGPoint(x: w * 0.57, y: h * 0.33))
        p.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.50), control: CGPoint(x: w * 0.84, y: h * 0.47))
        p.addQuadCurve(to: CGPoint(x: w * 0.66, y: h * 0.65), control: CGPoint(x: w * 0.80, y: h * 0.56))
        p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.98), control: CGPoint(x: w * 0.54, y: h * 0.78))
        p.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.65), control: CGPoint(x: w * 0.46, y: h * 0.75))
        p.addQuadCurve(to: CGPoint(x: w * 0.02, y: h * 0.50), control: CGPoint(x: w * 0.19, y: h * 0.55))
        p.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.35), control: CGPoint(x: w * 0.18, y: h * 0.45))
        p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.02), control: CGPoint(x: w * 0.46, y: h * 0.19))
        return p
    }
}

struct ThinkLogo: View {
    var compact = false
    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 5, y: 23))
                    p.addCurve(to: CGPoint(x: 16, y: 3), control1: CGPoint(x: 3, y: 11), control2: CGPoint(x: 9, y: 3))
                    p.addCurve(to: CGPoint(x: 32, y: 15), control1: CGPoint(x: 27, y: 0), control2: CGPoint(x: 34, y: 6))
                    p.addCurve(to: CGPoint(x: 23, y: 29), control1: CGPoint(x: 34, y: 21), control2: CGPoint(x: 30, y: 26))
                    p.addLine(to: CGPoint(x: 24, y: 35))
                    p.addLine(to: CGPoint(x: 16, y: 35))
                    p.addLine(to: CGPoint(x: 15, y: 28))
                    p.addCurve(to: CGPoint(x: 5, y: 23), control1: CGPoint(x: 7, y: 27), control2: CGPoint(x: 6, y: 27))
                }
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                ThinkStar().fill(Theme.yellow).frame(width: 13, height: 13).offset(x: 1, y: -4)
            }.frame(width: 37, height: 38)
            if !compact {
                Text("Think").font(.system(size: 27, weight: .regular, design: .serif))
                    .tracking(-1.5).foregroundStyle(Theme.ink)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct Idea: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct IdeaEnergy: Codable {
    var lastTouched: Date
    var lastReviewReward: Date
    var accruedStars: Int
    var protectedUntil: Date?
    var pinned: Bool = false

    func deadline() -> Date {
        let normal = lastTouched.addingTimeInterval(7 * 24 * 3600)
        return max(normal, protectedUntil ?? .distantPast)
    }
}

struct FadedIdea: Codable, Identifiable {
    let idea: Idea
    let fadedAt: Date
    var id: UUID { idea.id }
}

@MainActor
final class IdeaStore: ObservableObject {
    @Published var ideas: [Idea] = [] { didSet { persistIdeas() } }
    @Published var stars: Int = 0 {
        didSet { UserDefaults.standard.set(stars, forKey: "think-stars") }
    }
    @Published var energy: [String: IdeaEnergy] = [:] {
        didSet { persistEnergy() }
    }
    @Published var faded: [FadedIdea] = [] {
        didSet { persistFaded() }
    }
    @Published var qrStyleUnlocked: Bool = false {
        didSet { UserDefaults.standard.set(qrStyleUnlocked, forKey: "think-purple-qr-unlocked") }
    }

    init() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "think-ideas"),
           let saved = try? decoder.decode([Idea].self, from: data) {
            ideas = saved
        }
        stars = UserDefaults.standard.integer(forKey: "think-stars")
        if let data = UserDefaults.standard.data(forKey: "think-energy-v12"),
           let saved = try? decoder.decode([String: IdeaEnergy].self, from: data) {
            energy = saved
        }
        if let data = UserDefaults.standard.data(forKey: "think-faded-v12"),
           let saved = try? decoder.decode([FadedIdea].self, from: data) {
            faded = saved
        }
        let paidPreviously = UserDefaults.standard.bool(forKey: "think-purple-qr-unlocked")
        if !UserDefaults.standard.bool(forKey: "think-free-qr-migrated-v13") {
            if paidPreviously {
                // Make-good for anyone who purchased a QR look before it became free.
                stars += 45
            }
            UserDefaults.standard.set(true, forKey: "think-free-qr-migrated-v13")
        }
        qrStyleUnlocked = true
        // Existing v1.1 ideas receive a new seven-day grace period after upgrading.
        for idea in ideas where energy[idea.id.uuidString] == nil {
            energy[idea.id.uuidString] = IdeaEnergy(
                lastTouched: Date(),
                lastReviewReward: Date(),
                accruedStars: 0
            )
        }
        refreshLifecycle()
    }

    func save(_ text: String, existing: Idea?) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if let existing, let index = ideas.firstIndex(where: { $0.id == existing.id }) {
            guard ideas[index].text != cleaned else {
                touch(existing.id, allowReward: false)
                return
            }
            ideas[index].text = cleaned
            ideas[index].updatedAt = Date()
            award(3, to: existing.id)
            touch(existing.id, allowReward: false)
        } else {
            let idea = Idea(text: cleaned)
            energy[idea.id.uuidString] = IdeaEnergy(
                lastTouched: Date(),
                lastReviewReward: Date(),
                accruedStars: 0
            )
            ideas.insert(idea, at: 0)
            award(10, to: idea.id)
        }
    }

    func touch(_ id: UUID, allowReward: Bool = true) {
        let key = id.uuidString
        guard var record = energy[key] else { return }
        let now = Date()
        if allowReward && now.timeIntervalSince(record.lastReviewReward) >= 24 * 3600 {
            record.lastReviewReward = now
            record.accruedStars += 2
            stars += 2
        }
        record.lastTouched = now
        energy[key] = record
    }

    func returnToAllIdeas() {
        // A visit to the library counts as returning to every living idea.
        // Daily review bonuses are awarded at most once per 24 hours per idea.
        refreshLifecycle()
        let ids = ideas.map(\.id)
        for id in ids {
            touch(id)
        }
    }

    func energyFor(_ idea: Idea) -> IdeaEnergy {
        energy[idea.id.uuidString] ??
        IdeaEnergy(lastTouched: Date(), lastReviewReward: Date(), accruedStars: 0)
    }

    func remaining(_ idea: Idea) -> TimeInterval {
        energyFor(idea).deadline().timeIntervalSinceNow
    }

    func isFading(_ idea: Idea) -> Bool {
        remaining(idea) <= 24 * 3600
    }

    func refreshLifecycle() {
        let now = Date()
        let expired = ideas.filter { energyFor($0).deadline() <= now }
        guard !expired.isEmpty else { return }
        for idea in expired {
            let record = energyFor(idea)
            stars = max(0, stars - record.accruedStars)
            faded.insert(FadedIdea(idea: idea, fadedAt: now), at: 0)
            energy.removeValue(forKey: idea.id.uuidString)
        }
        let ids = Set(expired.map(\.id))
        ideas.removeAll { ids.contains($0.id) }
    }

    func protect(_ id: UUID, days: Int, cost: Int) -> Bool {
        guard stars >= cost, ideas.contains(where: { $0.id == id }),
              var record = energy[id.uuidString] else { return false }
        let start = max(Date(), record.protectedUntil ?? .distantPast)
        record.protectedUntil = start.addingTimeInterval(TimeInterval(days) * 86400)
        energy[id.uuidString] = record
        stars -= cost
        return true
    }

    func pin(_ id: UUID) -> Bool {
        guard stars >= 20, var record = energy[id.uuidString], !record.pinned else { return false }
        record.pinned = true
        energy[id.uuidString] = record
        stars -= 20
        return true
    }

    func unlockQR() -> Bool {
        // QR sharing and its purple appearance are free for everyone.
        qrStyleUnlocked = true
        return true
    }

    func recover(_ id: UUID) -> Bool {
        guard stars >= 60, let idx = faded.firstIndex(where: { $0.id == id }) else { return false }
        let restored = faded.remove(at: idx).idea
        energy[id.uuidString] = IdeaEnergy(lastTouched: Date(), lastReviewReward: Date(), accruedStars: 0)
        ideas.insert(restored, at: 0)
        stars -= 60
        return true
    }

    func delete(_ id: UUID) {
        let earned = energy[id.uuidString]?.accruedStars ?? 0
        stars = max(0, stars - earned)
        energy.removeValue(forKey: id.uuidString)
        ideas.removeAll { $0.id == id }
    }

    private func award(_ amount: Int, to id: UUID) {
        guard var record = energy[id.uuidString] else { return }
        record.accruedStars += amount
        energy[id.uuidString] = record
        stars += amount
    }

    private func persistIdeas() {
        if let data = try? JSONEncoder().encode(ideas) {
            UserDefaults.standard.set(data, forKey: "think-ideas")
        }
    }

    private func persistEnergy() {
        if let data = try? JSONEncoder().encode(energy) {
            UserDefaults.standard.set(data, forKey: "think-energy-v12")
        }
    }

    private func persistFaded() {
        if let data = try? JSONEncoder().encode(faded) {
            UserDefaults.standard.set(data, forKey: "think-faded-v12")
        }
    }
}

@main
struct ThinkApp: App {
    @StateObject private var store = IdeaStore()
    var body: some Scene {
        WindowGroup {
            PremiumRootScreen().environmentObject(store).preferredColorScheme(.light)
        }
    }
}

struct RootScreen: View {
    @EnvironmentObject private var store: IdeaStore
    @State private var tab = 0
    @State private var editing = false
    @State private var selected: Idea?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ThinkLogo()
                Spacer()
                HStack(spacing: 6) {
                    ThinkStar().fill(Theme.yellow).frame(width: 15, height: 15)
                    Text("\(store.stars)").font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Theme.ink).padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.panel, in: Capsule())
            }.padding(.horizontal, 27).padding(.top, 12)
            Group {
                if tab == 0 { HomeScreen(onNew: { editing = true }) }
                else if tab == 1 { IdeaListScreen(onNew: { editing = true }, onSelect: { selected = $0 }) }
                else { RewardScreen() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                tabButton("Главная", symbol: "sparkle", index: 0)
                Spacer()
                tabButton("Идеи", symbol: "square.stack", index: 1)
                Spacer()
                tabButton("Звёзды", symbol: "star", index: 2)
            }
            .padding(.horizontal, 42).padding(.top, 15).padding(.bottom, 9)
            .background(Theme.paper)
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $editing) { IdeaEditor(existing: nil) }
        .sheet(item: $selected) { idea in IdeaDetailScreen(idea: idea) }
    }
    private func tabButton(_ label: String, symbol: String, index: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.22)) { tab = index } } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 21, weight: tab == index ? .semibold : .regular))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tab == index ? Theme.ink : Theme.muted)
            .frame(minWidth: 60)
        }.buttonStyle(.plain)
    }
}

struct BreathingStar: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = CGFloat(1.0 + 0.065 * sin(t * 2 * .pi / 3.2))
            ZStack {
                Canvas { context, size in
                    let middle = CGPoint(x: size.width/2, y: size.height/2)
                    for i in 0..<280 {
                        let fi = Double(i)
                        let theta = fi * 2.399963229728653
                        let r = 45 + 100 * sqrt((fi + 0.5)/280)
                        let phase = sin(t * 1.8 + fi * 0.19)
                        let rr = r * (1 + 0.055 * phase) * Double(breath)
                        let x = middle.x + CGFloat(cos(theta) * rr)
                        let y = middle.y + CGFloat(sin(theta) * rr)
                        let sz = CGFloat(0.55 + (1 + sin(fi * 10.3 + t * 2.0)) * 0.6)
                        let fade = max(0.09, 1 - (r - 45)/135)
                        let color = Color(red: 1 - (1-fade)*0.45, green: 0.82 - (1-fade)*0.5, blue: 0.18)
                        let dot = Path(ellipseIn: CGRect(x: x, y: y, width: sz, height: sz))
                        context.fill(dot, with: .color(color.opacity(fade * 0.65)))
                    }
                }
                ThinkStar()
                    .fill(Theme.yellow)
                    .frame(width: 83 * breath, height: 83 * breath)
                    .shadow(color: Theme.yellow.opacity(0.28), radius: 21 * breath)
            }
        }
        .frame(height: 320)
        .accessibilityLabel("Дышащая жёлтая звезда")
    }
}

struct HomeScreen: View {
    let onNew: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            Text("У каждой идеи\nесть искра.")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .tracking(-1.2).lineSpacing(3).multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
            Button(action: onNew) { BreathingStar().contentShape(Rectangle()) }
                .buttonStyle(.plain).padding(.vertical, 10)
                .accessibilityLabel("Нажми на звезду, чтобы записать идею")
            Text("Нажми на звёздочку,\nпока мысль не растворилась.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
                .lineSpacing(5).multilineTextAlignment(.center)
            Spacer()
            Button(action: onNew) {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                    Text("Записать идею").font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(Theme.yellow, in: Capsule())
            }
            .buttonStyle(.plain).padding(.horizontal, 30).padding(.bottom, 28)
        }.frame(maxWidth: .infinity)
    }
}

struct IdeaEditor: View {
    @EnvironmentObject private var store: IdeaStore
    @Environment(\.dismiss) private var dismiss
    let existing: Idea?
    @State private var value: String
    @FocusState private var focused: Bool
    init(existing: Idea?) {
        self.existing = existing
        _value = State(initialValue: existing?.text ?? "")
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(existing == nil ? "Что за идея?" : "Развиваем мысль")
                    .font(.system(size: 37, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink).padding(.top, 24)
                Text("Не пытайся сделать её идеальной. Просто сохрани.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                ZStack(alignment: .topLeading) {
                    if value.isEmpty {
                        Text("А что, если...")
                            .font(.system(size: 20)).foregroundStyle(Theme.muted.opacity(0.65))
                            .padding(.top, 12).padding(.leading, 5)
                    }
                    TextEditor(text: $value).font(.system(size: 20))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Theme.ink)
                        .focused($focused)
                }.frame(maxHeight: .infinity)
                Button {
                    store.save(value, existing: existing)
                    dismiss()
                } label: {
                    HStack(spacing: 9) {
                        ThinkStar().fill(Theme.ink).frame(width: 16, height: 16)
                        Text("Сохранить мысль").font(.system(size: 16, weight: .medium))
                    }.frame(maxWidth: .infinity).padding(.vertical, 18)
                        .foregroundStyle(Theme.ink).background(Theme.yellow, in: Capsule())
                }
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .padding(.bottom, 15)
            }
            .padding(.horizontal, 27)
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }.foregroundStyle(Theme.muted)
                }
            }
        }
        .onAppear { focused = true }
    }
}

struct IdeaListScreen: View {
    @EnvironmentObject private var store: IdeaStore
    let onNew: () -> Void
    let onSelect: (Idea) -> Void
    @State private var search = ""
    private var filtered: [Idea] {
        store.ideas.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .firstTextBaseline) {
                Text("Твои идеи").font(.system(size: 37, weight: .regular, design: .serif))
                Spacer()
                Button(action: onNew) {
                    Image(systemName: "plus").foregroundStyle(Theme.ink)
                        .frame(width: 43, height: 43).background(Theme.yellow, in: Circle())
                }
            }.foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("Найти мысль", text: $search)
                    .autocorrectionDisabled()
            }
            .font(.system(size: 15)).foregroundStyle(Theme.muted)
            .padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            if store.ideas.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ThinkStar().fill(Theme.yellow).frame(width: 37, height: 37)
                    Text("Здесь будут твои мысли").font(.system(size: 23, design: .serif))
                    Text("Одна записанная идея может изменить всё.")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { idea in
                            Button { onSelect(idea) } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(idea.text)
                                        .font(.system(size: 17)).foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading).lineLimit(5)
                                    HStack {
                                        Text(idea.updatedAt, style: .date)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(19)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { store.delete(idea.id) } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }.padding(.horizontal, 26).padding(.top, 29)
    }
}

struct RewardScreen: View {
    @EnvironmentObject private var store: IdeaStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text("Твои звёзды").font(.system(size: 37, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                VStack(spacing: 9) {
                    ThinkStar().fill(Theme.yellow).frame(width: 75, height: 75)
                    Text("\(store.stars)").font(.system(size: 68, weight: .light, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("искры вдохновения").font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 27))
                Text("Как получить звёзды").font(.system(size: 24, design: .serif))
                rewardRow("Записать новую идею", "+5", "pencil")
                rewardRow("Развить существующую", "+2", "sparkle")
                Text("Скоро ты сможешь обменивать звёзды на персонализацию, оформления и новые анимации.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .lineSpacing(5).padding(.top, 10)
            }.foregroundStyle(Theme.ink).padding(.horizontal, 26).padding(.top, 29)
        }.scrollIndicators(.hidden)
    }
    private func rewardRow(_ title: String, _ amount: String, _ symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).frame(width: 37, height: 37).background(Theme.panel, in: Circle())
            Text(title).font(.system(size: 15))
            Spacer()
            Text(amount).foregroundStyle(Theme.muted)
        }.padding(.vertical, 5)
    }
}

struct QRScreen: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var showQR = false
    private var qr: UIImage? {
        guard !text.isEmpty, text.utf8.count < 600 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        let context = CIContext()
        guard let ci = filter.outputImage, let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    var body: some View {
        VStack(spacing: 25) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 42, height: 42).background(Theme.panel, in: Circle())
                }.foregroundStyle(Theme.ink)
                Spacer()
                ThinkLogo(compact: true)
            }
            Spacer(minLength: 30)
            Text("Поделись искрой").font(.system(size: 38, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Покажи код — мысль откроется\nобычным текстом, без приложения.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(.white)
                    .shadow(color: .black.opacity(0.04), radius: 22, y: 5)
                if let qr {
                    Image(uiImage: qr)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(width: 260, height: 260)
                        .padding(25)
                        .opacity(showQR ? 1 : 0)
                    if !showQR {
                        QRParticles()
                            .transition(.opacity)
                    }
                } else {
                    Text("Для длинной идеи используй\nобычную отправку текста.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted).padding()
                }
            }
            .frame(width: 310, height: 310)
            Spacer()
            ShareLink(item: text) {
                Text("Отправить текст идеи")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 19)
                    .background(Theme.yellow, in: Capsule())
                    .foregroundStyle(Theme.ink)
            }
            .padding(.bottom, 17)
        }
        .padding(.horizontal, 27)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1550))
                withAnimation(.easeOut(duration: 0.3)) { showQR = true }
            }
        }
    }
}

struct QRParticles: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            let t = max(0, timeline.date.timeIntervalSince(start))
            let progress = min(1.0, t / 1.5)
            Canvas { context, size in
                for i in 0..<380 {
                    let fi = Double(i)
                    let x0 = sin(fi * 73.27) * 0.5 + 0.5
                    let y0 = sin(fi * 23.47 + 8) * 0.5 + 0.5
                    let x1 = (Double(i % 24) + 0.5) / 24.0
                    let y1 = (Double(i / 24) + 0.5) / 24.0
                    let p = progress * progress * (3 - 2 * progress)
                    let px = CGFloat(x0 * (1-p) + x1 * p) * size.width
                    let py = CGFloat(y0 * (1-p) + y1 * p) * size.height
                    let dot = Path(ellipseIn: CGRect(x: px, y: py, width: CGFloat(1.7 + p), height: CGFloat(1.7 + p)))
                    context.fill(dot, with: .color(Theme.ink.opacity(0.3 + p * 0.6)))
                }
            }
        }
        .frame(width: 250, height: 250)
        .onAppear { start = Date() }
    }
}
