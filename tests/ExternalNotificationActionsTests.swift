import Foundation

@main
struct ExternalNotificationActionsTests {
    static func main() async throws {
        try await launchesShellWithoutWaitingForExit()
        print("PASS: external notification actions")
    }

    static func launchesShellWithoutWaitingForExit() async throws {
        let marker = URL(fileURLWithPath: ".build/agent-activity-tests/focus-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: marker) }
        let command = "sleep 2; value='focused tab'; printf '%s' \"$value\" > '\(marker.path)'"
        let start = Date()
        let launched: Bool = await withCheckedContinuation { continuation in
            BoringNotchXPCHelper().runExternalNotificationAction(command) { success in
                continuation.resume(returning: success)
            }
        }
        expect(launched, "The helper must launch the focus command")
        expect(Date().timeIntervalSince(start) < 1.5, "Launch acknowledgement must not wait for command exit")
        expect(!FileManager.default.fileExists(atPath: marker.path), "The delayed command must still be running")
        for _ in 0..<100 {
            if let text = try? String(contentsOf: marker, encoding: .utf8), text == "focused tab" { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        expect(false, "The shell must execute the complete command with shell syntax intact")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
