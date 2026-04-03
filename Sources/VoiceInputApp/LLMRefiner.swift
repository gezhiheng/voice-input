import Foundation

final class LLMRefiner: TextRefining {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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

    func refine(
        _ text: String,
        configuration: LLMConfiguration,
        mode: LLMRefinementMode
    ) async throws -> String {
        let response = try await complete(
            userText: text,
            configuration: configuration,
            mode: mode
        )

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoiceInputError.llmResponseMissingContent
        }

        return trimmed
    }

    func testConnection(configuration: LLMConfiguration) async throws {
        _ = try await complete(
            userText: "我在改配森服务的杰森配置",
            configuration: configuration,
            mode: .conservativeCorrection
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

    private func complete(
        userText: String,
        configuration: LLMConfiguration,
        mode: LLMRefinementMode
    ) async throws -> String {
        guard configuration.isConfigured else {
            throw VoiceInputError.message("LLM refinement is not configured.")
        }

        let endpoint = try normalizedEndpoint(from: configuration.baseURL)

        let body = ChatCompletionRequest(
            model: configuration.model,
            temperature: 0,
            seed: 1234,
            enableThinking: false,
            messages: [
                .init(role: "system", content: systemPrompt(for: mode)),
                .init(role: "user", content: userPrompt(for: userText, mode: mode))
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

    private func systemPrompt(for mode: LLMRefinementMode) -> String {
        switch mode {
        case .conservativeCorrection:
            """
            你是语音识别纠错器。
            你的唯一任务是修正语音转写文本中的明显识别错误，并返回修正后的文本。

            请严格遵守以下规则：
            1. 只修正明显错误，不要润色，不要改写，不要扩写，不要总结，不要补充省略信息。
            2. 保持原文的语序、句式、语气、标点、空格和换行；如果原文看起来已经正确，就原样返回。
            3. 优先修正中文同音字、近音词、英文技术词误识别、中英混说时的术语错误。
            4. 如果无法确定，不要猜，保留原文。
            5. 输出只能是修正后的文本本身，不要添加解释、前缀、引号或代码块。

            参考示例：
            - 配森 -> Python
            - 杰森 -> JSON
            - type script -> TypeScript（仅在上下文明确时）
            """
        case .structuredRewrite:
            """
            你是口述内容整理助手。
            你的任务是将用户的一大段口述内容整理得更有条理、更易读、更适合直接发送或记录。

            请严格遵守以下规则：
            1. 保留原意和关键信息，不要凭空添加事实。
            2. 允许删除明显重复、口头禅和冗余表达，但不要丢失核心内容。
            3. 优先重组结构、补足必要标点、断句和分段，让内容更清晰。
            4. 如果原文明显是在罗列事项，可以整理成短段落或项目符号；否则优先输出自然流畅的短段落。
            5. 输出只能是整理后的正文，不要解释你做了什么，不要加标题前缀，不要使用代码块。
            """
        }
    }

    private func userPrompt(for text: String, mode: LLMRefinementMode) -> String {
        switch mode {
        case .conservativeCorrection:
            """
            以下内容来自 macOS 语音输入的原始转写，请只修正明显识别错误。
            如果不确定，请保留原文。
            只返回修正后的文本。

            原始转写：
            \(text)
            """
        case .structuredRewrite:
            """
            以下内容来自 macOS 语音输入的原始转写，请总结、提炼并优化表达，使其更有条理、更适合直接使用。
            保留原意和关键信息，不要凭空补充事实。
            只返回整理后的正文。

            原始转写：
            \(text)
            """
        }
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
        var seed: Int
        var enableThinking: Bool
        var messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case temperature
            case seed
            case enableThinking = "enable_thinking"
            case messages
        }
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
