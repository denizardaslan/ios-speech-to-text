import SwiftUI

/// Shown for the brief moment the keyboard opens the app: the mic turns on, recording
/// starts and we jump back to the previous app. If jumping back is off or did not work,
/// it tells the user to tap ◀ (recording keeps running, so they can talk right away).
struct KeyboardHandoffView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                if controller.needsManualReturn || controller.lastError != nil {
                    HStack {
                        Spacer()
                        Button {
                            controller.keyboardHandoffVisible = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Close")
                    }
                }

                Spacer()

                MicButton(state: controller.state, level: controller.level, size: 110) {
                    controller.toggleRecording(origin: .keyboard)
                }

                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                if let error = controller.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if controller.needsManualReturn {
                    Label("Tap ◀ in the top-left corner to go back. Keep talking, it's already recording.",
                          systemImage: "arrow.uturn.backward")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
                Spacer()
            }
            .padding(24)
        }
    }

    private var title: String {
        if controller.lastError != nil { return "Couldn't start" }
        switch controller.state {
        case .off: return "Turning on the microphone…"
        case .ready: return controller.needsManualReturn ? "Ready" : "Going back…"
        case .recording: return controller.needsManualReturn ? "Listening…" : "Listening… going back"
        case .transcribing: return "Transcribing…"
        }
    }
}
