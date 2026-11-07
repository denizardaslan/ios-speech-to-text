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
                    Text("Keyboard Session")
                } footer: {
                    Text("While the session is on, the microphone waits in the background (an orange dot shows at the top of the screen) and 🎤 on the Voice Type keyboard listens instantly. It turns itself off if unused for the time you set.")
                }

                Section("Setup") {
                    NavigationLink {
                        KeyboardGuideView()
                    } label: {
                        Label("Enable the Keyboard", systemImage: "keyboard")
                    }
                    NavigationLink {
                        BackTapGuideView()
                    } label: {
                        Label("Double Back Tap", systemImage: "hand.tap")
                    }
                }

                if !history.items.isEmpty {
                    Section {
                        ForEach(history.items.prefix(3)) { item in
                            HistoryRow(item: item)
                        }
                        NavigationLink("All History") { HistoryView() }
                    } header: {
                        Text("Recent")
                    }
                }
            }
            .navigationTitle("Voice Type")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}

/// In-app dictation: a big mic button plus the result.
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
                            Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = controller.lastText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        ShareLink(item: controller.lastText) {
                            Label("Share", systemImage: "square.and.arrow.up")
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
        case .off, .ready: return "Tap to speak"
        case .recording: return "Listening… tap to finish"
        case .transcribing: return "Transcribing…"
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
            Text(controller.sessionActive ? "On: you can go back to the keyboard" : "Off")
            Spacer()
            Button(controller.sessionActive ? "Stop" : "Start") {
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
            Label("Use ◀ in the top-left corner to go back to the app you were typing in, then tap 🎤.", systemImage: "arrow.uturn.backward")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Round mic button whose color and icon follow the engine state.
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
        .accessibilityLabel(state == .recording ? "Stop recording" : "Start speaking")
    }

    private var color: Color {
        switch state {
        case .off, .ready: return .accentColor
        case .recording: return .red
        case .transcribing: return .orange
        }
    }
}

/// Full-screen recording view opened by the "Dictate" shortcut.
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
                case .recording: Text("Listening… tap to finish")
                case .transcribing: Text("Transcribing…")
                case .off, .ready:
                    if controller.copiedToClipboard {
                        Label("Copied to clipboard. Use ◀ in the top-left to go back and paste.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Tap to speak")
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
