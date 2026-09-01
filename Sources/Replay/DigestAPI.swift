import Foundation

enum DigestExplainPrompt {
    static let systemPrompt = """
    你解释视频字幕里被选中的文字。务必极简。

    规则：
    - 最多 1 到 3 句
    - 如果是词或术语：给简短定义
    - 如果是短语或论断：结合上下文解释含义
    - 不要套话，不要写「这指的是」，直接解释
    - 必须用简体中文作答。解释正文不得写成英文句子；专名、术语原文可以夹在中文里。
    """

    static let maxTokens = 256

    static func userText(videoTitle: String, selected: String, context: String) -> String {
        let contextLine = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        VIDEO: \(videoTitle)

        SELECTED: "\(selected)"

        CONTEXT: \(contextLine.isEmpty ? "None" : contextLine)

        请用简体中文简要解释。
        """
    }

    static func context(around index: Int, in cues: [VideoSubtitleCue], window: Int = 2) -> String {
        guard cues.indices.contains(index) else { return "" }
        let start = max(0, index - window)
        let end = min(cues.count - 1, index + window)
        return (start...end).map { cueIndex in
            let cue = cues[cueIndex]
            let body = cue.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return "[\(DigestTimecode.format(cue.startTime))] \(body)"
        }.joined(separator: "\n")
    }
}

struct DigestClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DigestProviderKind: String {
    case anthropic
    case gemini

    var activeModel: String {
        switch self {
        case .anthropic:
            return WatchQARequestBuilder.model
        case .gemini:
            return DigestGeminiRequestBuilder.model
        }
    }
}

enum DigestProvider {
    static let defaultsKey = "DigestProvider"

    static func resolve(defaults: UserDefaults = .standard) -> DigestProviderKind {
        let raw = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return DigestProviderKind(rawValue: raw) ?? .anthropic
    }
}

enum DigestGeminiAPIKey {
    static let defaultsKey = "GeminiAPIKey"
    static let environmentKey = "GEMINI_API_KEY"

    static func resolve(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let fromDefaults = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromDefaults.isEmpty { return fromDefaults }
        let fromEnvironment = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromEnvironment.isEmpty { return fromEnvironment }
        return nil
    }
}

enum DigestAPIKey {
    static func resolve(
        provider: DigestProviderKind = DigestProvider.resolve(),
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        switch provider {
        case .anthropic:
            return WatchQAAPIKey.resolve(defaults: defaults, environment: environment)
        case .gemini:
            return DigestGeminiAPIKey.resolve(defaults: defaults, environment: environment)
        }
    }
}

enum DigestGeminiRequestBuilder {
    static let model = "gemini-3.7-flash"
    static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.7-flash:generateContent")!

    static func requestURL(apiKey: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: allowed) ?? apiKey
        return URL(string: "\(endpoint.absoluteString)?key=\(encoded)")!
    }

    static func jsonObject(system: String, user: String, maxTokens: Int) -> [String: Any] {
        [
            "systemInstruction": [
                "parts": [
                    ["text": system]
                ]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": user]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens
            ]
        ]
    }

    static func jsonData(system: String, user: String, maxTokens: Int) -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject(system: system, user: user, maxTokens: maxTokens))
    }

    static func text(fromResponse data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }
        let joined = parts.compactMap { $0["text"] as? String }.joined()
        return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
    }
}

enum DigestRequestBuilder {
    static let missingKeyHint = "未配置密钥"
    static var model: String { WatchQARequestBuilder.model }
    static var endpoint: URL { WatchQARequestBuilder.endpoint }
    static var anthropicVersion: String { WatchQARequestBuilder.anthropicVersion }
    static let overviewMaxTokens = 8192

    static func jsonObject(system: String, user: String, maxTokens: Int) -> [String: Any] {
        [
            "model": model,
            "max_tokens": maxTokens,
            "stream": false,
            "system": system,
            "messages": [
                [
                    "role": "user",
                    "content": user
                ]
            ]
        ]
    }

    static func jsonData(system: String, user: String, maxTokens: Int) -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject(system: system, user: user, maxTokens: maxTokens))
    }

    static func text(fromResponse data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let content = object["content"] as? [[String: Any]] {
            let parts = content.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return item["text"] as? String
            }
            let joined = parts.joined()
            if !joined.isEmpty { return joined }
        }
        return nil
    }

    static func errorMessage(status: Int, data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }
        return "请求失败（\(status)）"
    }
}

enum DigestAPIClient {
    static func complete(
        system: String,
        user: String,
        apiKey: String,
        maxTokens: Int,
        provider: DigestProviderKind = DigestProvider.resolve(),
        session: URLSession = .shared
    ) async throws -> String {
        switch provider {
        case .anthropic:
            return try await completeAnthropic(
                system: system,
                user: user,
                apiKey: apiKey,
                maxTokens: maxTokens,
                session: session
            )
        case .gemini:
            return try await completeGemini(
                system: system,
                user: user,
                apiKey: apiKey,
                maxTokens: maxTokens,
                session: session
            )
        }
    }

    private static func completeAnthropic(
        system: String,
        user: String,
        apiKey: String,
        maxTokens: Int,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: DigestRequestBuilder.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(DigestRequestBuilder.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        guard let httpBody = DigestRequestBuilder.jsonData(system: system, user: user, maxTokens: maxTokens) else {
            throw DigestClientError(message: "请求无法编码")
        }
        request.httpBody = httpBody
        return try await send(request, session: session, extract: DigestRequestBuilder.text(fromResponse:))
    }

    private static func completeGemini(
        system: String,
        user: String,
        apiKey: String,
        maxTokens: Int,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: DigestGeminiRequestBuilder.requestURL(apiKey: apiKey))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        guard let httpBody = DigestGeminiRequestBuilder.jsonData(system: system, user: user, maxTokens: maxTokens) else {
            throw DigestClientError(message: "请求无法编码")
        }
        request.httpBody = httpBody
        return try await send(request, session: session, extract: DigestGeminiRequestBuilder.text(fromResponse:))
    }

    private static func send(
        _ request: URLRequest,
        session: URLSession,
        extract: (Data) -> String?
    ) async throws -> String {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DigestClientError(message: DigestRequestBuilder.errorMessage(status: http.statusCode, data: data))
        }
        guard let text = extract(data),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw DigestClientError(message: "没有得到有效回答")
        }
        return text
    }
}
