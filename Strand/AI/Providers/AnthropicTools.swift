import Foundation

// Anthropic tool use for the Coach (personal fork).
//
// The text-only `AnthropicClient.stream` stays as it is for every other path. A question asked with
// tools goes through `streamTurn`: one request per round, its server-sent events folded by
// `AnthropicTurnAccumulator` into the text shown as it arrives and the tool calls the round ends on.
// The engine runs the tools and asks again (`AICoachEngine.streamToolAnswer`). The request bodies and
// the event folding are pure, so both are tested without a network.

/// One content block of an assistant turn.
enum AnthropicBlock: Equatable, Sendable {
    case text(String)
    /// A tool call: its id, the tool's name and its input as the JSON text the model wrote.
    case toolUse(id: String, name: String, inputJSON: String)
}

/// One assistant turn as the stream left it.
struct AnthropicTurn: Equatable, Sendable {
    var blocks: [AnthropicBlock] = []
    /// "end_turn", "tool_use", "max_tokens"…; nil if the stream ended before saying.
    var stopReason: String?

    /// The turn's text, block after block.
    var text: String {
        blocks.compactMap { block -> String? in
            if case .text(let t) = block { return t } else { return nil }
        }.joined()
    }

    /// The tool calls, in the order the model made them.
    var toolCalls: [(id: String, name: String, inputJSON: String)] {
        blocks.compactMap { block -> (id: String, name: String, inputJSON: String)? in
            if case let .toolUse(id, name, json) = block { return (id, name, json) } else { return nil }
        }
    }
}

/// What a tool round streams to the engine: text as it arrives, then the whole turn once.
enum AnthropicStreamEvent: Sendable {
    case text(String)
    case finished(AnthropicTurn)
}

/// Folds the Messages API's server-sent events into text deltas and the turn's content blocks.
struct AnthropicTurnAccumulator {
    private enum Pending {
        case text(String)
        case tool(id: String, name: String, json: String)
    }

    private var pending: [Int: Pending] = [:]
    private var order: [Int] = []
    private var stopReason: String?

    /// Fold one `data:` payload. Returns the text it adds, if any. Throws the provider's message for
    /// an `error` event (an overloaded server sends one in the middle of a 200 stream).
    mutating func consume(_ payload: String) throws -> String? {
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }
        switch type {
        case "content_block_start":
            guard let index = event["index"] as? Int,
                  let block = event["content_block"] as? [String: Any] else { return nil }
            if !order.contains(index) { order.append(index) }
            if block["type"] as? String == "tool_use" {
                pending[index] = .tool(id: block["id"] as? String ?? "", name: block["name"] as? String ?? "",
                                       json: "")
                return nil
            }
            let text = block["text"] as? String ?? ""
            pending[index] = .text(text)
            return text.isEmpty ? nil : text
        case "content_block_delta":
            guard let index = event["index"] as? Int,
                  let delta = event["delta"] as? [String: Any] else { return nil }
            switch (delta["type"] as? String, pending[index]) {
            case ("text_delta"?, .text(let so)?):
                let piece = delta["text"] as? String ?? ""
                pending[index] = .text(so + piece)
                return piece.isEmpty ? nil : piece
            case ("text_delta"?, nil):
                // A delta without its start: keep the text rather than lose it.
                let piece = delta["text"] as? String ?? ""
                order.append(index)
                pending[index] = .text(piece)
                return piece.isEmpty ? nil : piece
            case ("input_json_delta"?, .tool(let id, let name, let json)?):
                pending[index] = .tool(id: id, name: name, json: json + (delta["partial_json"] as? String ?? ""))
                return nil
            default:
                return nil
            }
        case "message_delta":
            if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
            return nil
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "stream error"
            throw AICoachError.network(message)
        default:
            return nil
        }
    }

    /// The turn so far: its blocks in the order they started, empty text blocks left out.
    func turn() -> AnthropicTurn {
        var blocks: [AnthropicBlock] = []
        for index in order {
            switch pending[index] {
            case .text(let text)?:
                if !text.isEmpty { blocks.append(.text(text)) }
            case let .tool(id, name, json)?:
                let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(.toolUse(id: id, name: name, inputJSON: trimmed.isEmpty ? "{}" : trimmed))
            case nil:
                break
            }
        }
        return AnthropicTurn(blocks: blocks, stopReason: stopReason)
    }
}

/// The JSON a tool round sends. Pure.
enum AnthropicToolRequest {

    /// A plain text message of the conversation so far.
    static func message(role: String, text: String) -> [String: Any] {
        ["role": role, "content": text]
    }

    /// An assistant turn sent back as it came: its text, then its tool calls with their inputs.
    static func assistant(_ turn: AnthropicTurn) -> [String: Any] {
        var content: [[String: Any]] = []
        for block in turn.blocks {
            switch block {
            case .text(let text):
                content.append(["type": "text", "text": text])
            case let .toolUse(id, name, json):
                content.append(["type": "tool_use", "id": id, "name": name,
                                "input": CoachTools.input(fromJSON: json)])
            }
        }
        return ["role": "assistant", "content": content]
    }

    /// The answers to a turn's tool calls, one `tool_result` each, in one user message.
    static func toolResults(_ results: [(id: String, text: String, isError: Bool)]) -> [String: Any] {
        ["role": "user",
         "content": results.map { result -> [String: Any] in
             var block: [String: Any] = ["type": "tool_result", "tool_use_id": result.id, "content": result.text]
             if result.isError { block["is_error"] = true }
             return block
         }]
    }

    /// The streamed request body. `allowTools` false keeps the definitions (earlier turns refer to
    /// them) but forbids a new call, so the round ends in text.
    static func body(model: String, system: String, messages: [[String: Any]], tools: [[String: Any]],
                     allowTools: Bool, maxTokens: Int = 4096) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "stream": true,
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            if !allowTools { body["tool_choice"] = ["type": "none"] }
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}

extension AnthropicClient {

    /// Stream one tool round: `onEvent` gets the text as it arrives, then the finished turn.
    func streamTurn(key: String, body: Data, session: URLSession,
                    onEvent: (AnthropicStreamEvent) -> Void) async throws {
        var req = URLRequest(url: AIProvider.anthropic.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body

        var accumulator = AnthropicTurnAccumulator()
        var failure: Error?
        try await performStreamingRequest(req, session: session) { payload in
            guard failure == nil else { return }
            do {
                if let piece = try accumulator.consume(payload) { onEvent(.text(piece)) }
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        onEvent(.finished(accumulator.turn()))
    }
}
