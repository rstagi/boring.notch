import Foundation

/// Per-tab notification state, independent of the socket and SwiftUI.
struct AgentActivityQueue {
    static let idleDuration: TimeInterval = 8

    private(set) var events: [ExternalNotifyEvent] = []
    private var currentID: String?
    private var idleDeadlines: [String: Date] = [:]

    var currentEvent: ExternalNotifyEvent? {
        visibleEvents.first(where: { $0.id == currentID }) ?? visibleEvents.first
    }

    var visibleCount: Int { visibleEvents.count }

    mutating func receive(_ event: ExternalNotifyEvent, at date: Date) {
        idleDeadlines[event.id] = nil
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        currentID = currentEvent?.id
        startIdleDeadline(at: date)
    }

    mutating func advance(at date: Date) {
        events.removeAll { event in
            if let deadline = idleDeadlines[event.id], deadline <= date {
                idleDeadlines[event.id] = nil
                return true
            }
            return false
        }
        let candidates = visibleEvents
        guard !candidates.isEmpty else { currentID = nil; return }
        let index = candidates.firstIndex(where: { $0.id == currentID })
        currentID = candidates[index.map { ($0 + 1) % candidates.count } ?? 0].id
        startIdleDeadline(at: date)
    }

    private var visibleEvents: [ExternalNotifyEvent] {
        let attention = events.filter { $0.state != .working }
        return attention.isEmpty ? events : attention
    }

    private mutating func startIdleDeadline(at date: Date) {
        guard let event = currentEvent, event.state == .idle, idleDeadlines[event.id] == nil else { return }
        idleDeadlines[event.id] = date.addingTimeInterval(Self.idleDuration)
    }
}
