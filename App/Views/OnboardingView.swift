import SwiftUI

/// First launch: paste the Gemini API key once, validate it, save it.
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("Welcome to Voice Type")
                            .font(.largeTitle.bold())
                        Text("Speak, and your words are typed wherever you want. To get started you need a free Google Gemini API key.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 1, text: "Sign in to Google AI Studio with your Google account using the link below.")
                        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                            Label("aistudio.google.com/apikey", systemImage: "arrow.up.right.square")
                        }
                        .padding(.leading, 36)
                        StepRow(number: 2, text: "Tap \"Create API key\" to create a key and copy it.")
                        StepRow(number: 3, text: "Paste it here. The key is stored encrypted in the iOS Keychain, only on this phone.")
                    }

                    APIKeyForm()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}

/// Form to paste and validate the key (used on first launch and in Settings).
struct APIKeyForm: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var draft = ""
    @State private var isChecking = false
    @State private var errorMessage: String?
    private let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SecureField("AIza…", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    if let pasted = UIPasteboard.general.string {
                        draft = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .accessibilityLabel("Paste from clipboard")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                HStack {
                    if isChecking { ProgressView().tint(.white) }
                    Text(isChecking ? "Checking…" : "Save and Validate")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChecking)
        }
    }

    private func save() async {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let models = try await GeminiTranscriber.listModels(apiKey: key)
            // If the default model is not available with this key, pick the best "flash" model.
            if !models.contains(settings.model),
               let flash = models.first(where: { $0 == AppSettings.defaultModel })
                ?? models.last(where: { $0.contains("flash") && !$0.contains("lite") && !$0.contains("preview") }) {
                settings.model = flash
            }
            settings.apiKey = key
            draft = ""
            onSaved?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
