import Foundation

/// Per-tab notification state, independent of the socket and SwiftUI.
struct AgentActivityQueue {
    static let idleDuration: TimeInterval = 8

    private(set) var events: [ExternalNotifyEvent] = []
    private var currentID: String?
    private var idleDeadlines: [String: Date] = [:]
    /// Remaining idle time for IDs presented then hidden; hidden time does not count.
    private var pausedRemaining: [String: TimeInterval] = [:]
    /// Bumped per applied event so the view can ignore present/hide signals for superseded content.
    private var revisions: [String: Int] = [:]
    /// Survives dismissal so delayed stale events for a dismissed ID stay dropped.
    private var lastAppliedSeq: [String: Int64] = [:]

    var currentEvent: ExternalNotifyEvent? {
        visibleEvents.first(where: { $0.id == currentID }) ?? visibleEvents.first
    }

    var visibleCount: Int { visibleEvents.count }

    /// Events may arrive out of order; one whose `seq` is <= the last applied `seq` for its ID is dropped.
    /// Events without `seq` are treated as newest.
    mutating func receive(_ event: ExternalNotifyEvent, at date: Date) {
        if let seq = event.seq {
            if let last = lastAppliedSeq[event.id], seq <= last { return }
            lastAppliedSeq[event.id] = seq
        }
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        revisions[event.id, default: 0] += 1
        clearTimers(for: event.id)
        currentID = currentEvent?.id
    }

    func revision(of id: String) -> Int { revisions[id] ?? 0 }

    /// Starts or resumes the idle deadline once the event is actually displayed. Returns whether state changed.
    @discardableResult
    mutating func markPresented(id: String, revision: Int, at date: Date) -> Bool {
        guard let event = currentEvent, event.id == id, event.state == .idle,
              revision == self.revision(of: id), idleDeadlines[id] == nil else { return false }
        idleDeadlines[id] = date.addingTimeInterval(pausedRemaining.removeValue(forKey: id) ?? Self.idleDuration)
        return true
    }

    /// Pauses a running deadline when the view stops showing the event, even if it is no longer current.
    @discardableResult
    mutating func markHidden(id: String, revision: Int, at date: Date) -> Bool {
        guard revision == self.revision(of: id), let deadline = idleDeadlines[id] else { return false }
        pausedRemaining[id] = max(0, deadline.timeIntervalSince(date))
        idleDeadlines[id] = nil
        return true
    }

    mutating func dismiss(id: String, at date: Date) {
        events.removeAll { $0.id == id }
        clearTimers(for: id)
        currentID = currentEvent?.id
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
    }

    private mutating func clearTimers(for id: String) {
        idleDeadlines[id] = nil
        pausedRemaining[id] = nil
    }

    private var visibleEvents: [ExternalNotifyEvent] {
        let attention = events.filter { $0.state != .working }
        return attention.isEmpty ? events : attention
    }
}
