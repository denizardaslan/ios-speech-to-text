import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var confirmClear = false

    var body: some View {
        List {
            ForEach(history.items) { item in
                HistoryRow(item: item)
            }
            .onDelete(perform: history.delete)
        }
        .overlay {
            if history.items.isEmpty {
                ContentUnavailableView("Henüz kayıt yok", systemImage: "text.bubble")
            }
        }
        .navigationTitle("Geçmiş")
        .toolbar {
            if !history.items.isEmpty {
                Button("Temizle", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Tüm geçmiş silinsin mi?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { history.clear() }
        }
    }
}

struct HistoryRow: View {
    let item: HistoryItem
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = item.text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                HStack {
                    Text(item.source)
                    Text("·")
                    Text(item.date, style: .relative)
                    Spacer()
                    if copied {
                        Label("Kopyalandı", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
            ShareLink(item: item.text)
        }
    }
}
