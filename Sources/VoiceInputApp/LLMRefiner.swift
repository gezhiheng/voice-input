import Foundation

final class LLMRefiner: TextRefining {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let systemPrompt = """
    You are correcting speech recognition output. Be extremely conservative.
    Only fix obvious recognition errors. Keep wording, order, punctuation, spacing, and line breaks whenever they already look correct.
    Focus on obvious homophone mistakes, especially Chinese homophones and English technical terms misrecognized as Chinese characters.
    Examples: 配森 -> Python, 杰森 -> JSON, type script in Chinese context -> TypeScript only when clearly intended.
    Never rewrite for style. Never summarize. Never omit content. If the text already looks correct, return it unchanged.
    Output only the corrected text.
    """

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: configuration)
        }
    }

    func refine(_ text: String, configuration: LLMConfiguration) async throws -> String {
        let response = try await complete(
            userText: text,
            configuration: configuration
        )

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoiceInputError.llmResponseMissingContent
        }

        return trimmed
    }

    func testConnection(configuration: LLMConfiguration) async throws {
        _ = try await complete(
            userText: "配森 和 杰森",
            configuration: configuration
        )
    }

    func normalizedEndpoint(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil, components.host != nil else {
            throw VoiceInputError.invalidLLMEndpoint
        }

        let currentPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let finalPath: String

        switch currentPath {
        case let path where path.hasSuffix("chat/completions"):
            finalPath = path
        case let path where path.hasSuffix("v1"):
            finalPath = path + "/chat/completions"
        case "":
            finalPath = "v1/chat/completions"
        default:
            finalPath = pathHasTerminalV1Segment(path: currentPath) ? currentPath + "/chat/completions" : currentPath + "/v1/chat/completions"
        }

        components.path = "/" + finalPath

        guard let url = components.url else {
            throw VoiceInputError.invalidLLMEndpoint
        }

        return url
    }

    private func pathHasTerminalV1Segment(path: String) -> Bool {
        path.split(separator: "/").last == "v1"
    }

    private func complete(userText: String, configuration: LLMConfiguration) async throws -> String {
        guard configuration.isConfigured else {
            throw VoiceInputError.message("LLM refinement is not configured.")
        }

        let endpoint = try normalizedEndpoint(from: configuration.baseURL)

        let body = ChatCompletionRequest(
            model: configuration.model,
            temperature: 0,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userText)
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            let payload = String(data: data, encoding: .utf8) ?? "Unknown server response."
            throw VoiceInputError.message("LLM request failed: \(payload)")
        }

        let decoded = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw VoiceInputError.llmResponseMissingContent
        }

        return content
    }
}

private extension LLMRefiner {
    struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }

        var model: String
        var temperature: Double
        var messages: [Message]
    }

    struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }

            var message: Message
        }

        var choices: [Choice]
    }
}
