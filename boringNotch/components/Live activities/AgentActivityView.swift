import SwiftUI

/// Attention peeks sit below the camera; working uses only a small side indicator.
struct AgentActivityView: View {
    let event: ExternalNotifyEvent
    let count: Int
    let notchWidth: CGFloat
    let onFocus: () -> Void

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
            HStack(spacing: 10) {
                Image(systemName: event.state == .waiting ? "exclamationmark.bubble.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(event.state == .waiting ? .orange : .green)
                    .accessibilityLabel(event.state == .waiting ? "Needs input" : "Done")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(event.title.isEmpty ? event.source : event.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if count > 1 {
                            Text("\(count) tabs")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                    }
                    Text(event.message)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
            .accessibilityElement(children: .combine)
        }
    }
}
