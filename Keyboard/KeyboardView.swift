import SwiftUI

final class KeyboardModel: ObservableObject {
    @Published var engineState: EngineState = .off
    @Published var hasFullAccess = true
    @Published var showsGlobeKey = true
    @Published var errorMessage: String?
    @Published var needsSessionHint = false
    @Published var returnKeyTitle = "return"

    var onMic: () -> Void = {}
    var onCancel: () -> Void = {}
    var onEndSession: () -> Void = {}
    var onSpace: () -> Void = {}
    var onReturn: () -> Void = {}
    var onDelete: () -> Void = {}
    var onNextKeyboard: () -> Void = {}
    var onOpenApp: () -> Void = {}
}

struct KeyboardView: View {
    static let height: CGFloat = 250

    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 10) {
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
                .fill(model.engineState == .off ? Color.gray.opacity(0.5) : Color.green)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
            if model.engineState == .recording {
                Button("Cancel", action: model.onCancel)
                    .font(.footnote.bold())
            } else if model.engineState == .ready {
                Button(action: model.onEndSession) {
                    Image(systemName: "power")
                }
                .font(.footnote.bold())
                .accessibilityLabel("End session")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 32)
    }

    private var statusText: String {
        if let error = model.errorMessage { return error }
        if model.needsSessionHint { return "Turning on the mic… just start talking." }
        switch model.engineState {
        case .off: return "Tap 🎤 to dictate"
        case .ready: return "Ready: tap to speak"
        case .recording: return "Listening… tap to finish"
        case .transcribing: return "Transcribing…"
        }
    }

    // MARK: - Microphone

    private var micArea: some View {
        Button(action: model.onMic) {
            ZStack {
                if model.engineState == .recording {
                    PulseRing()
                }
                Circle()
                    .fill(micColor)
                    .frame(width: 84, height: 84)
                    .shadow(color: micColor.opacity(0.35), radius: 6, y: 3)
                if model.engineState == .transcribing {
                    ProgressView().tint(.white).scaleEffect(1.3)
                } else {
                    Image(systemName: model.engineState == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 130, height: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.engineState == .transcribing)
        .accessibilityLabel(model.engineState == .recording ? "Stop recording" : "Start speaking")
    }

    private var micColor: Color {
        switch model.engineState {
        case .off, .ready: return .accentColor
        case .recording: return .red
        case .transcribing: return .orange
        }
    }

    private var fullAccessNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.open")
                .font(.title2)
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

// MARK: - Keys

private struct KeyBackground: View {
    var isPrimary: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
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

/// A ring that pulses around the mic while recording.
private struct PulseRing: View {
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(Color.red.opacity(0.5), lineWidth: 3)
            .frame(width: 84, height: 84)
            .scaleEffect(animate ? 1.4 : 1)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
