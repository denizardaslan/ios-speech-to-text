import SwiftUI

struct MainView: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    DictationPanel()

                    VStack(spacing: 8) {
                        SectionTitle("Keyboard")
                        SessionCard()
                    }

                    VStack(spacing: 8) {
                        SectionTitle("Setup")
                        HStack(spacing: 12) {
                            GuideTile(title: "Keyboard", subtitle: "Type by voice in any app", systemImage: "keyboard") {
                                KeyboardGuideView()
                            }
                            GuideTile(title: "Back Tap", subtitle: "Dictate to the clipboard", systemImage: "hand.tap.fill") {
                                BackTapGuideView()
                            }
                        }
                    }

                    if !history.items.isEmpty {
                        VStack(spacing: 8) {
                            SectionTitle("Recent")
                            RecentCard()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Voice Type")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}

// MARK: - Dictation

/// In-app dictation: the big mic orb plus the result.
struct DictationPanel: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        VStack(spacing: 10) {
            MicButton(state: controller.state, level: controller.level, size: 104) {
                controller.toggleRecording(origin: .app)
            }

            Text(statusText)
                .font(.title3.weight(.semibold))

            if controller.state == .recording {
                RecordingTimer(start: controller.recordingStartedAt)
            } else {
                Text("Dictate here, or use the keyboard in any app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ErrorBanner()

            if !controller.lastText.isEmpty {
                ResultCard()
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var statusText: String {
        switch controller.state {
        case .off, .ready: return "Tap to speak"
        case .recording: return "Listening… tap to finish"
        case .transcribing: return "Transcribing…"
        }
    }
}

/// The last error, with a retry button when the audio is still available.
struct ErrorBanner: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        if let error = controller.lastError {
            VStack(spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
                    .multilineTextAlignment(.leading)
                if controller.canRetry {
                    Button {
                        controller.retryTranscription()
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ChipButtonStyle(tint: Theme.red))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.red.opacity(0.1)))
            .padding(.top, 6)
        }
    }
}

/// The most recent transcription with copy and share actions.
struct ResultCard: View {
    @EnvironmentObject private var controller: DictationController
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.lastText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = controller.lastText
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { justCopied = false }
                } label: {
                    Label(copyTitle, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(ChipButtonStyle(tint: copied ? .green : Theme.violet))

                ShareLink(item: controller.lastText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ChipButtonStyle())

                Spacer()
            }
        }
        .card()
    }

    private var copied: Bool { justCopied || controller.copiedToClipboard }
    private var copyTitle: String { copied ? "Copied" : "Copy" }
}

// MARK: - Keyboard session

/// Shows whether the microphone is waiting in the background for the keyboard, and toggles it.
struct SessionCard: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(controller.sessionActive ? Color.green : Color.gray.opacity(0.35))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.sessionActive ? "Microphone is ready" : "Microphone is off")
                        .font(.headline)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(controller.sessionActive ? "Turn Off" : "Turn On") {
                    if controller.sessionActive {
                        controller.endSession()
                    } else {
                        Task { await controller.startSession() }
                    }
                }
                .buttonStyle(ChipButtonStyle(tint: controller.sessionActive ? Theme.red : Theme.violet))
            }

            Divider()

            HStack {
                Label("Keep it on", systemImage: "timer")
                    .font(.subheadline)
                Spacer()
                Picker("Keep it on", selection: $settings.sessionDuration) {
                    ForEach(SessionDuration.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .tint(Color.secondary)
            }
        }
        .card()
    }

    private var detail: String {
        if controller.sessionActive {
            return "Swipe back to your app. The Voice Type keyboard listens instantly."
        }
        return "The keyboard turns it on when you dictate. Turn it on here to skip that step."
    }
}

// MARK: - Setup tiles

struct GuideTile<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(systemImage: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .card(padding: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent

struct RecentCard: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        VStack(spacing: 12) {
            ForEach(history.items.prefix(3)) { item in
                HistoryRow(item: item)
                Divider()
            }
            NavigationLink {
                HistoryView()
            } label: {
                HStack {
                    Text("All History")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .card()
    }
}

// MARK: - "Dictate" shortcut

/// Full-screen recording view opened by the "Dictate" shortcut.
struct QuickDictationView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button {
                    controller.cancelRecording()
                    controller.quickDictationVisible = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }

            Spacer()

            MicButton(state: controller.state, level: controller.level, size: 124) {
                controller.toggleRecording(origin: .app)
            }

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            if controller.state == .recording {
                RecordingTimer(start: controller.recordingStartedAt)
            } else if controller.copiedToClipboard, controller.state != .transcribing {
                Text("Go back to your app and paste.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ErrorBanner()

            if !controller.lastText.isEmpty, controller.state != .recording {
                ResultCard()
                    .padding(.top, 8)
            }

            Spacer()
            Spacer()
        }
        .padding(24)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var title: String {
        switch controller.state {
        case .recording: return "Listening… tap to finish"
        case .transcribing: return "Transcribing…"
        case .off, .ready: return controller.copiedToClipboard ? "Copied to clipboard" : "Tap to speak"
        }
    }
}
