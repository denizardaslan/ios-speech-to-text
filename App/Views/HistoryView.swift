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
                ContentUnavailableView("No transcriptions yet", systemImage: "text.bubble")
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !history.items.isEmpty {
                Button("Clear", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Delete all history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { history.clear() }
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
                        Label("Copied", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
            ShareLink(item: item.text)
        }
    }
}
