import Darwin
import Foundation

actor LaunchedCommands {
    private(set) var values: [String] = []
    func append(_ command: String) { values.append(command) }
}

@main
struct ExternalNotifyServerTests {
    @MainActor
    static func main() async throws {
        try await focusesSelectedEventAndDismissesIt()
        print("PASS: external notification server")
    }

    @MainActor
    static func focusesSelectedEventAndDismissesIt() async throws {
        let url = URL(string: "file:.build/agent-activity-tests/focus.sock")!
        let server = ExternalNotifyServer(socketURL: url)
        try server.start()
        defer { server.stop() }
        try send(id: "a", actions: [
            ["id": "other", "label": "Other", "command": "wrong command"],
            ["id": "focus", "label": "Focus tab", "command": "tmux select-window -t @12"]
        ], to: url)
        try send(id: "b", actions: [], to: url)
        try await waitUntil { server.activityQueue.events.count == 2 }
        let commands = LaunchedCommands()
        server.focus(id: "a") { command in await commands.append(command) }
        expect(server.activityQueue.events.map(\.id) == ["b"], "Click must dismiss only the selected tab immediately")
        for _ in 0..<100 {
            if await commands.values == ["tmux select-window -t @12"] { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        expect(false, "Click must execute the focus action, regardless of its position")
    }

    static func send(id: String, actions: [[String: String]], to url: URL) throws {
        let payload: [String: Any] = [
            "v": 1, "id": id, "source": "ws", "state": "waiting", "prev": "working",
            "title": "ws", "message": "Needs input", "detail": "", "agent": "codex",
            "repo": "api", "branch": "main", "focused": false, "sound": "",
            "actions": actions, "ts": 100
        ]
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(url.path.utf8CString)
        expect(path.count <= MemoryLayout.size(ofValue: address.sun_path), "Test socket path must fit")
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            for (index, byte) in path.enumerated() { bytes[index] = UInt8(bitPattern: byte) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!, $0.count) }
        expect(written == data.count, "The complete event must reach the socket")
    }

    @MainActor
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        expect(false, "Timed out waiting for notification state")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
