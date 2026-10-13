import SwiftUI

/// Attention peeks are a card below the camera; working uses only a small side indicator.
/// Clicking the card focuses the tab (caller wires the tap); ✕ only dismisses.
struct AgentActivityView: View {
    let event: ExternalNotifyEvent
    let count: Int
    let notchWidth: CGFloat
    let onFocus: () -> Void
    var onDismiss: () -> Void = {}

    @State private var dismissHovered = false

    var body: some View {
        content
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Focus agent tab and dismiss notification")
            .accessibilityAction { onFocus() }
    }

    @ViewBuilder
    private var content: some View {
        if event.state == .working {
            HStack(spacing: 8) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .symbolEffect(.pulse, options: .repeating)
                    .opacity(0.6)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    // Icon clicks focus; clear areas fall through to the notch (opens it).
                    .onTapGesture { onFocus() }
                Color.clear.frame(width: max(0, notchWidth - 20))
                Color.clear.frame(width: 16, height: 16)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Agent working")
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.state == .waiting ? "exclamationmark.bubble.fill" : "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .frame(width: 32)
                    .accessibilityLabel(stateLabel)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !event.agent.isEmpty {
                            Text(event.agent)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.gray)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.white.opacity(0.12)))
                        }
                        Spacer(minLength: 0)
                        if count > 1 {
                            Text("\(count) tabs")
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                        }
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(dismissHovered ? .white : .gray)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.white.opacity(dismissHovered ? 0.22 : 0.1)))
                        }
                        .buttonStyle(.plain)
                        .onHover { dismissHovered = $0 }
                        .help("Dismiss")
                        .accessibilityLabel("Dismiss")
                    }
                    (Text(stateLabel).foregroundStyle(stateColor).fontWeight(.medium)
                        + Text(body2.isEmpty ? "" : "  \(body2)").foregroundStyle(.white.opacity(0.75)))
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    private var stateColor: Color { event.state == .waiting ? .orange : .green }
    private var stateLabel: String { event.state == .waiting ? "Needs input" : "Done" }

    /// `repo · branch` when the producer sends them, else its title.
    private var headline: String {
        if !event.repo.isEmpty {
            return event.branch.isEmpty ? event.repo : "\(event.repo) · \(event.branch)"
        }
        return event.title.isEmpty ? event.source : event.title
    }

    /// The agent's own words (prompt / last message) beat the generic producer message.
    private var body2: String {
        let detail = event.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return (detail.isEmpty ? event.message : detail)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
