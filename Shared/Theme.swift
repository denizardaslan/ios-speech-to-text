import SwiftUI

/// Colors and the few visual building blocks shared by the app and the keyboard.
enum Theme {
    static let violet = Color(red: 0.44, green: 0.36, blue: 0.96)
    static let blue = Color(red: 0.10, green: 0.52, blue: 1.00)
    static let coral = Color(red: 1.00, green: 0.45, blue: 0.38)
    static let red = Color(red: 0.98, green: 0.23, blue: 0.35)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.20)
    static let orange = Color(red: 1.00, green: 0.50, blue: 0.16)

    static func colors(for state: EngineState) -> [Color] {
        switch state {
        case .off, .ready: return [violet, blue]
        case .recording: return [coral, red]
        case .transcribing: return [amber, orange]
        }
    }

    static func gradient(for state: EngineState) -> LinearGradient {
        LinearGradient(colors: colors(for: state), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let brand = LinearGradient(colors: [violet, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The round microphone "orb". Its color and content follow the engine state:
/// mic (idle), moving bars (recording), spinner (transcribing).
/// Pass `level` (0…1) to make it react to the voice; without it the motion is synthetic
/// (the keyboard does not know the audio level).
struct MicOrb: View {
    let state: EngineState
    var level: CGFloat? = nil
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            if state == .recording {
                if let level {
                    Circle()
                        .fill(Theme.red.opacity(0.14))
                        .frame(width: size, height: size)
                        .scaleEffect(1.2 + level * 0.6)
                    Circle()
                        .fill(Theme.red.opacity(0.22))
                        .frame(width: size, height: size)
                        .scaleEffect(1.08 + level * 0.3)
                } else {
                    PulseRing(size: size)
                }
            }
            Circle()
                .fill(Theme.gradient(for: state))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: glowColor.opacity(0.45), radius: size * 0.16, y: size * 0.08)
            icon
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.easeInOut(duration: 0.25), value: state)
    }

    private var glowColor: Color { Theme.colors(for: state).last ?? .clear }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .transcribing:
            ProgressView()
                .tint(.white)
                .scaleEffect(size / 60)
        case .recording:
            WaveformBars(level: level, color: .white, maxHeight: size * 0.40)
        case .off, .ready:
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// A few capsule bars that move like a voice waveform.
struct WaveformBars: View {
    var level: CGFloat? = nil
    var color: Color = .white
    var barCount: Int = 5
    var barWidth: CGFloat = 4
    var maxHeight: CGFloat = 32

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: barWidth) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(index: index, time: time))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let wave = CGFloat((sin(time * 7 + Double(index) * 1.4) + 1) / 2)
        let amount: CGFloat
        if let level {
            amount = 0.2 + 0.8 * min(max(level, 0), 1)
        } else {
            amount = 0.75
        }
        let minHeight = barWidth * 1.5
        return minHeight + (maxHeight - minHeight) * wave * amount
    }
}

/// A ring that keeps expanding and fading around the orb.
struct PulseRing: View {
    var size: CGFloat = 84
    var color: Color = Theme.red
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.5), lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(animate ? 1.45 : 1)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
