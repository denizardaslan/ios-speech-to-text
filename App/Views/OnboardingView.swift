import SwiftUI

/// First launch: paste the Gemini API key once, validate it, save it.
struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.violet.opacity(0.14))
                            .frame(width: 148, height: 148)
                        MicOrb(state: .off, size: 96)
                    }
                    Text("Voice Type")
                        .font(.largeTitle.bold())
                    Text("Speak, and your words are typed in any app. Punctuated, cleaned up, in your language.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Add your free Gemini API key")
                        .font(.headline)
                    StepRow(number: 1, text: "Open Google AI Studio and sign in with your Google account.")
                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        Label("aistudio.google.com/apikey", systemImage: "arrow.up.right.square.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.leading, 36)
                    StepRow(number: 2, text: "Tap \"Create API key\" and copy the key.")
                    StepRow(number: 3, text: "Paste it below. It is stored in the iOS Keychain, only on this phone.")
                }
                .card()

                APIKeyForm()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
            }

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if isChecking { ProgressView().tint(.white) }
                    Text(isChecking ? "Checking…" : "Save and Validate")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
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
