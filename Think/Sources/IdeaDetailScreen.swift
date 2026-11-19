import SwiftUI
import UIKit

struct IdeaDetailScreen: View {
    @EnvironmentObject private var store: IdeaStore
    @Environment(\.dismiss) private var dismiss
    let idea: Idea
    @State private var editing = false
    @State private var qr = false
    @State private var deleteConfirm = false

    private var current: Idea { store.ideas.first(where: { $0.id == idea.id }) ?? idea }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Text(current.createdAt, format: .dateTime.day().month(.wide).year())
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .padding(.top, 25)
                    Text(current.text)
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(7).textSelection(.enabled)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Button { editing = true } label: {
                        Label("Редактировать идею", systemImage: "pencil")
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(Theme.panel, in: Capsule())
                    }
                    Button { qr = true } label: {
                        Label("Поделиться QR-кодом", systemImage: "qrcode")
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Theme.yellow, in: Capsule())
                    }
                    ShareLink(item: current.text) {
                        Label("Поделиться текстом", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(Theme.panel, in: Capsule())
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 27)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Твоя искра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Назад") { dismiss() }.foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { deleteConfirm = true } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .sheet(isPresented: $editing) { IdeaEditor(existing: current) }
        .sheet(isPresented: $qr) { QRScreen(text: current.text) }
        .confirmationDialog("Удалить идею?", isPresented: $deleteConfirm) {
            Button("Удалить", role: .destructive) {
                store.delete(idea.id)
                dismiss()
            }
        }
    }
}
