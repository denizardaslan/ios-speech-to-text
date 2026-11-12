import SwiftUI

// MARK: - Cards

extension View {
    /// The rounded "card" most screens are built from.
    func card(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

/// Small uppercase title above a card.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }
}

/// An SF Symbol on a rounded gradient tile.
struct IconTile: View {
    let systemImage: String
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.brand)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Buttons

/// Full-width gradient button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.brand))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Small tinted capsule button.
struct ChipButtonStyle: ButtonStyle {
    var tint: Color = Theme.violet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.25 : 0.14)))
    }
}

/// Shrinks its label slightly while pressed (used for the mic orb).
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Mic

/// The tappable mic orb used on every recording screen of the app.
struct MicButton: View {
    let state: EngineState
    let level: Float
    var size: CGFloat = 96
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MicOrb(state: state, level: CGFloat(level), size: size)
                .frame(width: size * 1.7, height: size * 1.7)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(state == .transcribing)
        .sensoryFeedback(.impact, trigger: state == .recording)
        .accessibilityLabel(state == .recording ? "Stop recording" : "Start speaking")
    }
}

/// Elapsed recording time, e.g. "0:07".
struct RecordingTimer: View {
    let start: Date?

    var body: some View {
        if let start {
            Text(start, style: .timer)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.red)
        }
    }
}

// MARK: - Steps

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.brand))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
