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
        editing = idea
        text = idea?.text ?? draft
        step = idea?.step ?? draftStep
        showStep = !step.isEmpty
        page = .editor
    }
    private func save() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, (words + "\n\n" + action).utf8.count <= 1800 else { return }
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
                    Text("Коснись звезды, пока идея не погасла.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.accessibilityLabel("Записать идею")
            Spacer(minLength: 20)
            Button { page = .collection } label: {
                Label("Мои идеи · \(book.ideas.count)", systemImage: "square.stack").font(.callout)
                    .padding(.horizontal, 20).frame(minHeight: 48).background(.white.opacity(0.07), in: Capsule())
            }.padding(.bottom, 12)
        }.buttonStyle(.plain).foregroundStyle(.white)
         .background(RadialGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.13), ink, .black], center: .center, startRadius: 10, endRadius: 550).ignoresSafeArea())
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { focus = nil; page = editing == nil ? .spark : .collection } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Назад")
                Spacer()
                Text(editing == nil ? "Новая мысль" : "Редактирование").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                SparkShape().fill(accent).frame(width: 16, height: 16).padding(.horizontal, 14)
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text("О чём ты думаешь?").foregroundStyle(.white.opacity(0.42)).padding(.top, 8).padding(.leading, 5) }
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
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (text + "\n\n" + step).utf8.count > 1800)
            }
        }.padding(.horizontal, 22).padding(.bottom, 8).foregroundStyle(.white)
         .background(ZStack { ink; RoundedRectangle(cornerRadius: 46).stroke(.indigo.opacity(0.55), lineWidth: 9).blur(radius: 14) }.ignoresSafeArea())
         .task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { focus = .thought } }
    }
    private var archive: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Button { page = .spark } label: { brand }.accessibilityLabel("Главная"); Spacer(); balance }
            Text("Мои идеи").font(.largeTitle.bold()).tracking(-1.5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if book.ideas.isEmpty {
                        Text("Здесь появится твоя первая мысль.").font(.title3).foregroundStyle(.secondary).padding(.vertical, 32)
                    }
                    ForEach(book.ideas) { idea in
                        VStack(alignment: .leading, spacing: 13) {
                            HStack { Text(idea.created, format: .dateTime.day().month(.wide)).font(.caption); Spacer(); Text("✳ \(idea.award)").font(.caption.monospacedDigit()) }.foregroundStyle(.secondary)
                            Button { begin(idea) } label: {
                                Text(idea.text).font(.system(.title3, design: .serif)).multilineTextAlignment(.leading).lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Divider()
                            HStack { Button("Изменить") { begin(idea) }; Spacer(); Button { panel = .qr(idea) } label: { Label("Поделиться", systemImage: "qrcode") } }.font(.subheadline).frame(minHeight: 44)
                        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 24)).shadow(color: .black.opacity(0.035), radius: 8, y: 4)
                    }
                }.padding(.bottom, 8)
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
