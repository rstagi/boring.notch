import Foundation

@main
struct AgentActivityQueueTests {
    static func main() throws {
        try updatesSameIDInPlace()
        try cyclesIDsWithoutDiscardingWaiting()
        try expiresIdleButRetainsWaiting()
        try prioritizesAttentionOverWorking()
        try givesEveryQueuedIdleEventATurn()
        try dismissesOnlyTheSelectedID()
        print("PASS: agent activity queue")
    }

    static func updatesSameIDInPlace() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting", message: "Choose a target"), at: now)
        queue.receive(try event("a", state: "idle", message: "Deployed"), at: now)
        expect(queue.events.count == 1, "Same ID must occupy one queue slot")
        expect(queue.currentEvent?.message == "Deployed", "Same ID must update the visible content")
    }

    static func cyclesIDsWithoutDiscardingWaiting() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting"), at: now)
        queue.receive(try event("b", state: "waiting"), at: now)
        expect(queue.currentEvent?.id == "a", "New IDs must queue behind the visible event")
        queue.advance(at: now.addingTimeInterval(60))
        expect(queue.currentEvent?.id == "b", "Next ID must get its turn")
        queue.advance(at: now.addingTimeInterval(120))
        expect(queue.currentEvent?.id == "a", "Waiting must survive elapsed time and cycle back")
        expect(queue.events.count == 2, "Cycling must retain both waiting IDs")
    }

    static func expiresIdleButRetainsWaiting() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "idle"), at: now)
        queue.receive(try event("b", state: "waiting"), at: now)
        queue.advance(at: now.addingTimeInterval(8))
        expect(queue.events.map(\.id) == ["b"], "Idle peeks expire after eight seconds; waiting remains")
        queue.receive(try event("b", state: "idle"), at: now.addingTimeInterval(8))
        queue.advance(at: now.addingTimeInterval(16))
        expect(queue.currentEvent == nil, "A later idle event must release sticky waiting")
    }

    static func prioritizesAttentionOverWorking() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "working"), at: now)
        queue.receive(try event("b", state: "waiting"), at: now)
        expect(queue.currentEvent?.id == "b", "Waiting must replace a subtle working indicator")
        queue.receive(try event("c", state: "idle"), at: now)
        queue.advance(at: now.addingTimeInterval(4))
        expect(queue.currentEvent?.id == "c", "Working IDs must not interrupt attention peeks")
        queue.receive(try event("b", state: "working"), at: now.addingTimeInterval(4))
        queue.advance(at: now.addingTimeInterval(12))
        expect(queue.currentEvent?.state == .working, "Working indicator returns after attention clears")
        expect(queue.events.map(\.id) == ["a", "b"], "Working tabs remain available as indicators")
    }

    static func givesEveryQueuedIdleEventATurn() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        for id in ["a", "b", "c"] {
            queue.receive(try event(id, state: "idle"), at: now)
        }
        queue.advance(at: now.addingTimeInterval(4))
        expect(queue.currentEvent?.id == "b", "Second completion must get its turn")
        queue.advance(at: now.addingTimeInterval(8))
        expect(queue.currentEvent?.id == "c", "Queued completions must not expire before their first turn")
    }

    static func dismissesOnlyTheSelectedID() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting"), at: now)
        queue.receive(try event("b", state: "idle"), at: now)
        queue.dismiss(id: "a", at: now.addingTimeInterval(20))
        expect(queue.events.map(\.id) == ["b"], "Dismissal must remove only the selected ID")
        expect(queue.currentEvent?.id == "b", "The next queued event must become visible")
        queue.advance(at: now.addingTimeInterval(24))
        expect(queue.currentEvent?.id == "b", "A newly visible idle event must get its full display time")
        queue.advance(at: now.addingTimeInterval(28))
        expect(queue.currentEvent == nil, "The last event must expire normally after dismissal")
    }

    static func event(_ id: String, state: String, message: String = "Needs input") throws -> ExternalNotifyEvent {
        let payload: [String: Any] = [
            "v": 1, "id": id, "source": "ws", "state": state, "prev": "working",
            "title": "ws", "message": message, "detail": "", "agent": "codex",
            "repo": "api", "branch": "main", "focused": false, "sound": "",
            "actions": [], "ts": 100
        ]
        return try JSONDecoder().decode(ExternalNotifyEvent.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
