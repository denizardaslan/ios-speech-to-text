import SwiftUI

/// İlk açılış: Gemini API anahtarını bir kere yapıştır, doğrula, kaydet.
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
                        Text("Sesli Yaz'a hoş geldin")
                            .font(.largeTitle.bold())
                        Text("Konuş, metin olarak istediğin yere yazılsın. Başlamak için ücretsiz bir Google Gemini API anahtarı gerekiyor.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 1, text: "Aşağıdaki bağlantıdan Google hesabınla Google AI Studio'ya gir.")
                        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                            Label("aistudio.google.com/apikey", systemImage: "arrow.up.right.square")
                        }
                        .padding(.leading, 36)
                        StepRow(number: 2, text: "\"Create API key\" ile bir anahtar oluştur ve kopyala.")
                        StepRow(number: 3, text: "Buraya yapıştır. Anahtar sadece bu telefonda, iOS Anahtar Zinciri'nde şifreli saklanır.")
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

/// Anahtarı yapıştırma + doğrulama formu (ilk açılışta ve Ayarlar'da kullanılır).
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
                .accessibilityLabel("Panodan yapıştır")
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
                    Text(isChecking ? "Kontrol ediliyor…" : "Kaydet ve doğrula")
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
            // Varsayılan model bu anahtarla kullanılamıyorsa en uygun "flash" modelini seç.
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
