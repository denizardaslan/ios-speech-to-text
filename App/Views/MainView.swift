import SwiftUI

struct MainView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DictationPanel()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    SessionRow()
                } header: {
                    Text("Klavye oturumu")
                } footer: {
                    Text("Oturum açıkken mikrofon arka planda hazır bekler (ekranın üstünde turuncu nokta görünür) ve Sesli Yaz klavyesindeki 🎤 anında dinler. Ayarladığın süre boyunca kullanılmazsa kendiliğinden kapanır.")
                }

                Section("Kurulum") {
                    NavigationLink {
                        KeyboardGuideView()
                    } label: {
                        Label("Klavyeyi etkinleştir", systemImage: "keyboard")
                    }
                    NavigationLink {
                        BackTapGuideView()
                    } label: {
                        Label("Arkaya iki kez dokun", systemImage: "hand.tap")
                    }
                }

                if !history.items.isEmpty {
                    Section {
                        ForEach(history.items.prefix(3)) { item in
                            HistoryRow(item: item)
                        }
                        NavigationLink("Tüm geçmiş") { HistoryView() }
                    } header: {
                        Text("Son çeviriler")
                    }
                }
            }
            .navigationTitle("Sesli Yaz")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ayarlar")
                }
            }
        }
    }
}

/// Uygulama içinden dikte: büyük mikrofon düğmesi + sonuç.
struct DictationPanel: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        VStack(spacing: 16) {
            MicButton(state: controller.state, level: controller.level, size: 96) {
                controller.toggleRecording(origin: .app)
            }
            .padding(.top, 12)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = controller.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if !controller.lastText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.lastText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        if controller.copiedToClipboard {
                            Label("Panoya kopyalandı", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = controller.lastText
                        } label: {
                            Label("Kopyala", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        ShareLink(item: controller.lastText) {
                            Label("Paylaş", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var statusText: String {
        switch controller.state {
        case .off, .ready: return "Konuşmak için dokun"
        case .recording: return "Dinliyorum… bitirmek için dokun"
        case .transcribing: return "Yazıya çevriliyor…"
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        HStack {
            Circle()
                .fill(controller.sessionActive ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
            Text(controller.sessionActive ? "Açık: klavyeye dönebilirsin" : "Kapalı")
            Spacer()
            Button(controller.sessionActive ? "Kapat" : "Başlat") {
                if controller.sessionActive {
                    controller.endSession()
                } else {
                    Task { await controller.startSession() }
                }
            }
            .buttonStyle(.bordered)
            .tint(controller.sessionActive ? Color.red : Color.accentColor)
        }
        if controller.sessionActive {
            Label("Sol üst köşedeki ◀ ile yazdığın uygulamaya geri dön ve 🎤'a bas.", systemImage: "arrow.uturn.backward")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Durumuna göre renk/ikon değiştiren yuvarlak mikrofon düğmesi.
struct MicButton: View {
    let state: EngineState
    let level: Float
    var size: CGFloat = 80
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .recording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: size, height: size)
                        .scaleEffect(1 + CGFloat(level) * 0.6)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .shadow(color: color.opacity(0.4), radius: 8, y: 4)
                if state == .transcribing {
                    ProgressView().tint(.white).scaleEffect(1.4)
                } else {
                    Image(systemName: state == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size * 1.6, height: size * 1.6)
        }
        .buttonStyle(.plain)
        .disabled(state == .transcribing)
        .accessibilityLabel(state == .recording ? "Kaydı bitir" : "Konuşmaya başla")
    }

    private var color: Color {
        switch state {
        case .off, .ready: return .accentColor
        case .recording: return .red
        case .transcribing: return .orange
        }
    }
}

/// "Dikte Et" kestirmesiyle açılan tam ekran kayıt görünümü.
struct QuickDictationView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button {
                    controller.cancelRecording()
                    controller.quickDictationVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            MicButton(state: controller.state, level: controller.level, size: 120) {
                controller.toggleRecording(origin: .app)
            }
            Group {
                switch controller.state {
                case .recording: Text("Dinliyorum… bitirmek için dokun")
                case .transcribing: Text("Yazıya çevriliyor…")
                case .off, .ready:
                    if controller.copiedToClipboard {
                        Label("Panoya kopyalandı. Sol üstteki ◀ ile geri dönüp yapıştır.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Konuşmak için dokun")
                    }
                }
            }
            .font(.headline)
            .multilineTextAlignment(.center)

            if let error = controller.lastError {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if !controller.lastText.isEmpty, controller.state != .recording {
                Text(controller.lastText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            }
            Spacer()
        }
        .padding(24)
    }
}
