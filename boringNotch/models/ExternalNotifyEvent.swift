import Foundation

/// The v1 adapter payload. Unknown JSON fields are ignored by Codable.
struct ExternalNotifyEvent: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case working, idle, waiting
    }

    struct Action: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let label: String
        let command: String
    }

    let v: Int
    let id: String
    let source: String
    let state: State
    let prev: String
    let title: String
    let message: String
    let detail: String
    let agent: String
    let repo: String
    let branch: String
    let focused: Bool
    let sound: String
    let actions: [Action]
    let ts: Double
    /// Optional per-hook ordering key (microseconds since epoch); `ts` is informational.
    let seq: Int64?

    private enum CodingKeys: String, CodingKey {
        case v, id, source, state, prev, title, message, detail
        case agent, repo, branch, focused, sound, actions, ts, seq
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        v = try values.decode(Int.self, forKey: .v)
        guard v == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .v, in: values, debugDescription: "Unsupported notification version: \(v)")
        }
        id = try values.decode(String.self, forKey: .id)
        source = try values.decode(String.self, forKey: .source)
        state = try values.decode(State.self, forKey: .state)
        prev = try values.decode(String.self, forKey: .prev)
        title = try values.decode(String.self, forKey: .title)
        message = try values.decode(String.self, forKey: .message)
        detail = try values.decode(String.self, forKey: .detail)
        agent = try values.decode(String.self, forKey: .agent)
        repo = try values.decode(String.self, forKey: .repo)
        branch = try values.decode(String.self, forKey: .branch)
        focused = try values.decode(Bool.self, forKey: .focused)
        sound = try values.decode(String.self, forKey: .sound)
        actions = try values.decode([Action].self, forKey: .actions)
        ts = try values.decode(Double.self, forKey: .ts)
        seq = try values.decodeIfPresent(Int64.self, forKey: .seq)
    }
}
