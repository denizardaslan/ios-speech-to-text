import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelError: String?
    @State private var showKeyForm = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                LabeledContent("API anahtarı", value: maskedKey)
                if showKeyForm {
                    APIKeyForm { showKeyForm = false }
                } else {
                    Button("Anahtarı değiştir") { showKeyForm = true }
                }
                Button("Anahtarı sil", role: .destructive) { confirmDelete = true }
            } header: {
                Text("Gemini")
            } footer: {
                Text("Anahtar sadece bu cihazın Anahtar Zinciri'nde saklanır. Ses doğrudan Google'a gönderilir; arada başka sunucu yok. Not: Gemini'nin ücretsiz katmanında Google, gönderilen verileri ürünlerini geliştirmek için kullanabilir.")
            }

            Section {
                Picker("Model", selection: $settings.model) {
                    ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    HStack {
                        Text("Kullanılabilir modelleri getir")
                        if loadingModels { Spacer(); ProgressView() }
                    }
                }
                if let modelError {
                    Text(modelError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("\"\(AppSettings.defaultModel)\" konuşmayı yazıya çevirmek için özel bir model; stil ve dil ayarlarını doğrudan kullanır. \"flash\" modelleri genel amaçlıdır.")
            }

            Section("Yazım") {
                Picker("Stil", selection: $settings.style) {
                    ForEach(TranscriptionStyle.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.style.detail).font(.footnote).foregroundStyle(.secondary)
                Picker("Dil", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Uygulamada sonucu panoya kopyala", isOn: $settings.autoCopy)
            }

            Section {
                Stepper(value: $settings.sessionTimeoutMinutes, in: 1...60) {
                    LabeledContent("Kapanma süresi", value: "\(settings.sessionTimeoutMinutes) dk")
                }
            } header: {
                Text("Klavye oturumu")
            } footer: {
                Text("Klavye oturumu bu süre boyunca kullanılmazsa mikrofon kapatılır. Sonraki 🎤 basışında uygulama bir anlığına tekrar açılır.")
            }
        }
        .navigationTitle("Ayarlar")
        .confirmationDialog("API anahtarı silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { settings.apiKey = "" }
        }
    }

    private var modelOptions: [String] {
        var options = models
        for m in [settings.model, AppSettings.defaultModel] where !options.contains(m) {
            options.insert(m, at: 0)
        }
        return options
    }

    private var maskedKey: String {
        let key = settings.apiKey
        guard key.count > 8 else { return key.isEmpty ? "Yok" : "••••" }
        return "\(key.prefix(4))••••\(key.suffix(4))"
    }

    private func loadModels() async {
        loadingModels = true
        modelError = nil
        defer { loadingModels = false }
        do {
            models = try await GeminiTranscriber.listModels(apiKey: settings.apiKey)
        } catch {
            modelError = error.localizedDescription
        }
    }
}
