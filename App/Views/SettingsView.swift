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
                LabeledContent("API Key", value: maskedKey)
                if showKeyForm {
                    APIKeyForm { showKeyForm = false }
                } else {
                    Button("Change Key") { showKeyForm = true }
                }
                Button("Delete Key", role: .destructive) { confirmDelete = true }
            } header: {
                Text("Gemini")
            } footer: {
                Text("The key is stored only in this device's Keychain. Audio is sent directly to Google; there is no server in between. Note: on Gemini's free tier, Google may use the data you send to improve its products.")
            }

            Section {
                Picker("Model", selection: $settings.model) {
                    ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    HStack {
                        Text("Fetch Available Models")
                        if loadingModels { Spacer(); ProgressView() }
                    }
                }
                if let modelError {
                    Text(modelError).font(.footnote).foregroundStyle(Theme.red)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("\"\(AppSettings.defaultModel)\" is a dedicated speech-to-text model and uses the style and language settings directly. \"flash\" models are general purpose.")
            }

            Section("Transcription") {
                Picker("Style", selection: $settings.style) {
                    ForEach(TranscriptionStyle.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.style.detail).font(.footnote).foregroundStyle(.secondary)
                Picker("Language", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Copy In-App Results to Clipboard", isOn: $settings.autoCopy)
            }

            Section {
                Picker("Keep Microphone On", selection: $settings.sessionDuration) {
                    ForEach(SessionDuration.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Start Recording When Keyboard Opens", isOn: $settings.autoStartOnKeyboardOpen)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Keyboards cannot use the microphone, so the Voice Type app records for the keyboard. While its microphone is on, iOS shows the microphone indicator (Dynamic Island or the orange dot); no app can hide that.\n\n\"Off after each dictation\" removes the indicator as soon as you finish, but every dictation opens the app once and you swipe back. A longer time keeps the microphone ready, so the keyboard listens instantly without leaving your app.")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete the API key?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { settings.apiKey = "" }
        }
    }

    private var modelOptions: [String] {
        var options = models
        for m in [settings.model, AppSettings.defaultModel] where !options.contains(m) {
            options.insert(m, at: 0)
        }
        return options
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var maskedKey: String {
        let key = settings.apiKey
        guard key.count > 8 else { return key.isEmpty ? "None" : "••••" }
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
