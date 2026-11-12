import SwiftUI

final class KeyboardModel: ObservableObject {
    @Published var engineState: EngineState = .off
    @Published var hasFullAccess = true
    @Published var showsGlobeKey = true
    @Published var errorMessage: String?
    /// We just sent the user to the app to turn on the microphone.
    @Published var openingApp = false
    @Published var canRetry = false
    @Published var canUndo = false
    @Published var recordingStartedAt: Date?
    @Published var returnKeyTitle = "return"

    var onMic: () -> Void = {}
    var onCancel: () -> Void = {}
    var onRetry: () -> Void = {}
    var onUndo: () -> Void = {}
    var onEndSession: () -> Void = {}
    var onSpace: () -> Void = {}
    var onReturn: () -> Void = {}
    var onDelete: () -> Void = {}
    var onNextKeyboard: () -> Void = {}

    /// Takes over the state the app published.
    func apply(_ snapshot: SharedSnapshot) {
        engineState = snapshot.engineState
        errorMessage = snapshot.lastError
        canRetry = snapshot.canRetry ?? false
        recordingStartedAt = snapshot.engineState == .recording ? snapshot.recordingStartedAt : nil
        if snapshot.engineState == .recording { canUndo = false }
    }
}

struct KeyboardView: View {
    static let height: CGFloat = 250

    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 6) {
            topBar
            Spacer(minLength: 0)
            if model.hasFullAccess {
                micArea
            } else {
                fullAccessNotice
            }
            Spacer(minLength: 0)
            bottomRow
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(height: Self.height)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(model.errorMessage == nil ? Color.secondary : Theme.red)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            trailingAction
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch model.engineState {
        case .recording:
            PillButton(title: "Cancel", systemImage: "xmark", action: model.onCancel)
        case .transcribing:
            EmptyView()
        case .off, .ready:
            HStack(spacing: 6) {
                if model.canRetry {
                    PillButton(title: "Retry", systemImage: "arrow.clockwise", action: model.onRetry)
                } else if model.canUndo {
                    PillButton(title: "Undo", systemImage: "arrow.uturn.backward", action: model.onUndo)
                }
                if model.engineState == .ready {
                    PillButton(title: nil, systemImage: "power", action: model.onEndSession)
                        .accessibilityLabel("Turn off the microphone")
                }
            }
        }
    }

    private var statusColor: Color {
        if model.errorMessage != nil { return Theme.red }
        switch model.engineState {
        case .off: return Color.gray.opacity(0.5)
        case .ready: return .green
        case .recording: return Theme.red
        case .transcribing: return Theme.orange
        }
    }

    private var statusText: String {
        if let error = model.errorMessage { return error }
        if model.openingApp, model.engineState == .off { return "Opening Voice Type… swipe back and talk." }
        switch model.engineState {
        case .off: return "Tap to dictate"
        case .ready: return "Ready. Tap to speak"
        case .recording: return "Listening… tap to finish"
        case .transcribing: return "Transcribing…"
        }
    }

    // MARK: - Microphone

    private var micArea: some View {
        VStack(spacing: 2) {
            Button(action: model.onMic) {
                MicOrb(state: model.engineState, size: 82)
                    .frame(width: 200, height: 112)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(model.engineState == .transcribing)
            .accessibilityLabel(model.engineState == .recording ? "Stop recording" : "Start speaking")

            // Keeps its height so the orb does not jump when the timer appears.
            Group {
                if let start = model.recordingStartedAt {
                    Text(start, style: .timer)
                } else {
                    Text(" ")
                }
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var fullAccessNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.open.fill")
                .font(.title2)
                .foregroundStyle(Theme.brand)
            Text("Full Access required")
                .font(.headline)
            Text("Settings › General › Keyboard › Keyboards › Voice Type › Allow Full Access")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.showsGlobeKey {
                KeyButton(systemImage: "globe", action: model.onNextKeyboard)
                    .frame(width: 44)
            }
            KeyButton(title: "space", isPrimary: true, action: model.onSpace)
            RepeatingKeyButton(systemImage: "delete.left", action: model.onDelete)
                .frame(width: 56)
            KeyButton(title: model.returnKeyTitle, action: model.onReturn)
                .frame(width: 84)
        }
        .frame(height: 44)
    }
}

// MARK: - Small controls

/// A compact capsule button for the top bar (Cancel, Undo, Retry, power).
private struct PillButton: View {
    let title: String?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                if let title { Text(title) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Shrinks the mic slightly while it is pressed.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Keys

private struct KeyBackground: View {
    var isPrimary: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isPrimary
                  ? (colorScheme == .dark ? Color(white: 0.42) : Color.white)
                  : (colorScheme == .dark ? Color(white: 0.28) : Color(white: 0.68)))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
    }
}

private struct KeyButton: View {
    var title: String?
    var systemImage: String?
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                KeyBackground(isPrimary: isPrimary)
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let title {
                    Text(title).font(.system(size: 15))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

/// A key that repeats while held (delete).
private struct RepeatingKeyButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isPressed = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            KeyBackground()
                .opacity(isPressed ? 0.6 : 1)
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    action()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    timer?.invalidate()
                    timer = nil
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Delete")
        .accessibilityAction { action() }
    }
}
