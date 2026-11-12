import SwiftUI

/// Shown when the keyboard opens the app to turn on the microphone.
///
/// iOS has no way for an app to send the user back to the previous app, so this screen
/// does one thing: tell them to swipe back. Recording has already started, so they can
/// talk while they do it.
struct KeyboardHandoffView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                HStack {
                    Text("Voice Type")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button {
                        controller.keyboardHandoffVisible = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.18)))
                    }
                    .accessibilityLabel("Stay in Voice Type")
                }

                Spacer()

                MicButton(state: controller.state, level: controller.level, size: 116) {
                    controller.toggleRecording(origin: .keyboard)
                }

                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Group {
                    if let error = controller.lastError {
                        Text(error)
                    } else if controller.state == .recording {
                        Text("Keep talking. You don't have to wait.")
                    } else if controller.state == .ready {
                        Text("The microphone is ready for the keyboard.")
                    }
                }
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

                Spacer()
                Spacer()

                if controller.lastError == nil {
                    SwipeBackHint()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .environment(\.colorScheme, .dark)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.12)
            RadialGradient(
                colors: [Theme.colors(for: controller.state).first!.opacity(0.55), .clear],
                center: .center, startRadius: 20, endRadius: 420
            )
            .offset(y: -80)
            LinearGradient(
                colors: [.clear, Theme.blue.opacity(0.25)],
                startPoint: .center, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: controller.state)
    }

    private var title: String {
        if controller.lastError != nil { return "Couldn't start" }
        switch controller.state {
        case .off: return "Turning on the mic…"
        case .ready: return "Ready"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        }
    }
}

/// "Swipe right along the bottom edge": the gesture that takes you to the previous app.
/// A dot slides along a copy of the home indicator to show it.
private struct SwipeBackHint: View {
    @State private var slide = false

    private let trackWidth: CGFloat = 220

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Swipe right to go back")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Slide along the bar at the bottom of the screen,\nor tap ◀ in the top-left corner.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            ZStack {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.25 + 0.2 * Double(index)))
                    }
                }
                .offset(y: -24)

                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: trackWidth, height: 5)

                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: .white.opacity(0.6), radius: 10)
                    .offset(x: slide ? trackWidth / 2 - 15 : -trackWidth / 2 + 15)
                    .opacity(slide ? 0 : 1)
            }
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                slide = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
