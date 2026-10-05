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
        try keepsIdleUntilPresented()
        try restartsDeadlineAfterSameIDIdleUpdate()
        try pausesDeadlineWhileHidden()
        try ignoresHideWithStaleRevision()
        try staleSeqDoesNotBumpRevision()
        try dropsReorderedSeq()
        try dropsEqualSeq()
        try appliesMissingSeqAsNewest()
        try dropsStaleSeqAfterDismiss()
        try decodesOptionalSeq()
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
        queue.markPresented(id: "a", revision: queue.revision(of: "a"), at: now)
        queue.advance(at: now.addingTimeInterval(8))
        expect(queue.events.map(\.id) == ["b"], "Idle peeks expire after eight seconds; waiting remains")
        queue.receive(try event("b", state: "idle"), at: now.addingTimeInterval(8))
        queue.markPresented(id: "b", revision: queue.revision(of: "b"), at: now.addingTimeInterval(8))
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
        queue.markPresented(id: "c", revision: queue.revision(of: "c"), at: now.addingTimeInterval(4))
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
        queue.markPresented(id: "a", revision: queue.revision(of: "a"), at: now)
        queue.advance(at: now.addingTimeInterval(4))
        expect(queue.currentEvent?.id == "b", "Second completion must get its turn")
        queue.markPresented(id: "b", revision: queue.revision(of: "b"), at: now.addingTimeInterval(4))
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
        queue.markPresented(id: "b", revision: queue.revision(of: "b"), at: now.addingTimeInterval(20))
        queue.advance(at: now.addingTimeInterval(24))
        expect(queue.currentEvent?.id == "b", "A newly visible idle event must get its full display time")
        queue.advance(at: now.addingTimeInterval(28))
        expect(queue.currentEvent == nil, "The last event must expire normally after dismissal")
    }

    static func keepsIdleUntilPresented() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "idle"), at: now)
        queue.receive(try event("b", state: "waiting"), at: now)
        queue.markPresented(id: "b", revision: queue.revision(of: "b"), at: now)
        for offset in stride(from: 4.0, through: 60, by: 4) {
            queue.advance(at: now.addingTimeInterval(offset))
        }
        expect(queue.events.count == 2, "Idle must not expire before it is displayed")
        queue.dismiss(id: "b", at: now.addingTimeInterval(60))
        queue.markPresented(id: "a", revision: queue.revision(of: "a"), at: now.addingTimeInterval(61))
        queue.advance(at: now.addingTimeInterval(68))
        expect(queue.currentEvent?.id == "a", "Idle must stay for its full display time")
        queue.advance(at: now.addingTimeInterval(69))
        expect(queue.currentEvent == nil, "Idle must expire eight seconds after first display")
    }

    static func restartsDeadlineAfterSameIDIdleUpdate() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "idle", seq: 1), at: now)
        let first = queue.revision(of: "a")
        queue.markPresented(id: "a", revision: first, at: now)
        queue.receive(try event("a", state: "idle", message: "Again", seq: 3), at: now.addingTimeInterval(2))
        let second = queue.revision(of: "a")
        expect(second != first, "Applied same-ID update must bump revision")
        expect(!queue.markPresented(id: "a", revision: first, at: now.addingTimeInterval(2)), "Stale revision must not present")
        expect(queue.markPresented(id: "a", revision: second, at: now.addingTimeInterval(2)), "New revision must restart the deadline")
        queue.advance(at: now.addingTimeInterval(9))
        expect(queue.currentEvent?.message == "Again", "Updated idle must get full display time")
        queue.advance(at: now.addingTimeInterval(10))
        expect(queue.currentEvent == nil, "Updated idle must expire eight seconds after re-presentation")
    }

    static func pausesDeadlineWhileHidden() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "idle"), at: now)
        let revision = queue.revision(of: "a")
        queue.markPresented(id: "a", revision: revision, at: now)
        expect(queue.markHidden(id: "a", revision: revision, at: now.addingTimeInterval(2)), "Hide must pause a running deadline")
        queue.advance(at: now.addingTimeInterval(60))
        expect(queue.currentEvent?.id == "a", "Hidden time must not count toward expiry")
        queue.markPresented(id: "a", revision: revision, at: now.addingTimeInterval(100))
        queue.advance(at: now.addingTimeInterval(105))
        expect(queue.currentEvent?.id == "a", "Re-presentation must resume remaining time")
        queue.advance(at: now.addingTimeInterval(106))
        expect(queue.currentEvent == nil, "Idle must expire after its remaining six seconds")
    }

    static func ignoresHideWithStaleRevision() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "idle"), at: now)
        let stale = queue.revision(of: "a")
        queue.receive(try event("a", state: "idle", message: "Again"), at: now)
        queue.markPresented(id: "a", revision: queue.revision(of: "a"), at: now)
        expect(!queue.markHidden(id: "a", revision: stale, at: now.addingTimeInterval(2)), "Stale hide must be a no-op")
        queue.advance(at: now.addingTimeInterval(8))
        expect(queue.currentEvent == nil, "Stale hide must not pause the current deadline")
    }

    static func staleSeqDoesNotBumpRevision() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        expect(queue.revision(of: "a") == 0, "Unknown ID must have revision zero")
        queue.receive(try event("a", state: "idle", seq: 200), at: now)
        let revision = queue.revision(of: "a")
        queue.receive(try event("a", state: "working", seq: 100), at: now)
        expect(queue.revision(of: "a") == revision, "Dropped stale seq must not bump revision")
    }

    static func dropsReorderedSeq() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting", seq: 200), at: now)
        queue.receive(try event("a", state: "working", seq: 100), at: now)
        expect(queue.currentEvent?.state == .waiting, "Older seq must not replace newer one")
    }

    static func dropsEqualSeq() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting", seq: 200), at: now)
        queue.receive(try event("a", state: "idle", seq: 200), at: now)
        expect(queue.currentEvent?.state == .waiting, "Duplicate seq must be dropped")
    }

    static func appliesMissingSeqAsNewest() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting", seq: 200), at: now)
        queue.receive(try event("a", state: "idle"), at: now)
        expect(queue.currentEvent?.state == .idle, "Events without seq must always apply")
        queue.receive(try event("a", state: "working", seq: 150), at: now)
        expect(queue.currentEvent?.state == .idle, "Missing seq must not lower the last applied seq")
    }

    static func dropsStaleSeqAfterDismiss() throws {
        var queue = AgentActivityQueue()
        let now = Date(timeIntervalSince1970: 100)
        queue.receive(try event("a", state: "waiting", seq: 200), at: now)
        queue.dismiss(id: "a", at: now)
        queue.receive(try event("a", state: "working", seq: 100), at: now)
        expect(queue.events.isEmpty, "Stale seq for a dismissed ID must be dropped")
        queue.receive(try event("a", state: "idle", seq: 300), at: now)
        expect(queue.currentEvent?.state == .idle, "Newer seq after dismissal must apply")
    }

    static func decodesOptionalSeq() throws {
        let withSeq = try event("a", state: "idle", seq: 1_791_182_700_123_456)
        let withoutSeq = try event("a", state: "idle")
        expect(withSeq.seq == 1_791_182_700_123_456, "seq must decode")
        expect(withoutSeq.seq == nil, "seq must be optional")
    }

    static func event(_ id: String, state: String, message: String = "Needs input", seq: Int64? = nil) throws -> ExternalNotifyEvent {
        var payload: [String: Any] = [
            "v": 1, "id": id, "source": "ws", "state": state, "prev": "working",
            "title": "ws", "message": message, "detail": "", "agent": "codex",
            "repo": "api", "branch": "main", "focused": false, "sound": "",
            "actions": [], "ts": 100
        ]
        if let seq { payload["seq"] = seq }
        return try JSONDecoder().decode(ExternalNotifyEvent.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
