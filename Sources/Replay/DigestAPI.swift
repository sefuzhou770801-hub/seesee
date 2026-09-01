import Foundation

enum DigestExplainPrompt {
    static let maxTokens = 512
    static let temperature = 0.2

    static let systemPrompt = """
    你在帮人看视频。对方划出了几个字，你用大白话告诉他这几个字在这句里是什么意思。

    只用简体中文，说一两句就够，最多三句。
    别把原句再说一遍，别客套，别用英文写解释。
    专名可以留原文。
    """

    struct Passage: Equatable {
        var selected: String
        var original: String
        var translation: String
        var previous: String
        var next: String
    }

    static func userText(videoTitle: String, passage: Passage) -> String {
        """
        视频：\(videoTitle)

        选中：\(passage.selected)

        它所在的这句
        原文：\(blank(passage.original))
        译文：\(blank(passage.translation))

        上一句：\(blank(passage.previous))
        下一句：\(blank(passage.next))

        这几个字在这里是什么意思？
        """
    }

    static func passage(selected: String, around index: Int, in cues: [VideoSubtitleCue]) -> Passage {
        let current = cues.indices.contains(index) ? pair(cues[index]) : ("", "")
        let previous = index > 0 ? joined(cues[index - 1]) : ""
        let next = index + 1 < cues.count ? joined(cues[index + 1]) : ""
        return Passage(
            selected: selected.trimmingCharacters(in: .whitespacesAndNewlines),
            original: current.0,
            translation: current.1,
            previous: previous,
            next: next
        )
    }

    private static func pair(_ cue: VideoSubtitleCue) -> (String, String) {
        let parts = cue.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rest = parts.dropFirst().joined(separator: " ")
        if parts.count >= 2, rest != parts[0] {
            return (parts[0], rest)
        }
        return ("", parts.first ?? cue.text)
    }

    private static func joined(_ cue: VideoSubtitleCue) -> String {
        let parts = pair(cue)
        if parts.0.isEmpty { return parts.1 }
        if parts.1.isEmpty { return parts.0 }
        return "\(parts.0) / \(parts.1)"
    }

    private static func blank(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无" : trimmed
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

    static func jsonObject(system: String, user: String, maxTokens: Int, temperature: Double? = nil) -> [String: Any] {
        var config: [String: Any] = ["maxOutputTokens": maxTokens]
        if let temperature {
            config["temperature"] = temperature
            config["thinkingConfig"] = ["thinkingBudget": 0]
        }
        return [
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
            "generationConfig": config
        ]
    }

    static func jsonData(system: String, user: String, maxTokens: Int, temperature: Double? = nil) -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject(system: system, user: user, maxTokens: maxTokens, temperature: temperature))
    }

    static func text(fromResponse data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }
        let joined = parts.compactMap { item -> String? in
            if item["thought"] as? Bool == true { return nil }
            return item["text"] as? String
        }.joined()
        return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
    }
}

enum DigestRequestBuilder {
    static let missingKeyHint = "还没填密钥"
    static var model: String { WatchQARequestBuilder.model }
    static var endpoint: URL { WatchQARequestBuilder.endpoint }
    static var anthropicVersion: String { WatchQARequestBuilder.anthropicVersion }
    static let overviewMaxTokens = 8192

    static func jsonObject(system: String, user: String, maxTokens: Int, temperature: Double? = nil) -> [String: Any] {
        var object: [String: Any] = [
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
        if let temperature {
            object["temperature"] = temperature
        }
        return object
    }

    static func jsonData(system: String, user: String, maxTokens: Int, temperature: Double? = nil) -> Data? {
        try? JSONSerialization.data(withJSONObject: jsonObject(system: system, user: user, maxTokens: maxTokens, temperature: temperature))
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
        temperature: Double? = nil,
        session: URLSession = .shared
    ) async throws -> String {
        switch provider {
        case .anthropic:
            return try await completeAnthropic(
                system: system,
                user: user,
                apiKey: apiKey,
                maxTokens: maxTokens,
                temperature: temperature,
                session: session
            )
        case .gemini:
            return try await completeGemini(
                system: system,
                user: user,
                apiKey: apiKey,
                maxTokens: maxTokens,
                temperature: temperature,
                session: session
            )
        }
    }

    private static func completeAnthropic(
        system: String,
        user: String,
        apiKey: String,
        maxTokens: Int,
        temperature: Double?,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: DigestRequestBuilder.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(DigestRequestBuilder.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        guard let httpBody = DigestRequestBuilder.jsonData(
            system: system,
            user: user,
            maxTokens: maxTokens,
            temperature: temperature
        ) else {
            throw DigestClientError(message: "这次没写成")
        }
        request.httpBody = httpBody
        return try await send(request, session: session, extract: DigestRequestBuilder.text(fromResponse:))
    }

    private static func completeGemini(
        system: String,
        user: String,
        apiKey: String,
        maxTokens: Int,
        temperature: Double?,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: DigestGeminiRequestBuilder.requestURL(apiKey: apiKey))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        guard let httpBody = DigestGeminiRequestBuilder.jsonData(
            system: system,
            user: user,
            maxTokens: maxTokens,
            temperature: temperature
        ) else {
            throw DigestClientError(message: "这次没写成")
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
            throw DigestClientError(message: "这次没写成")
        }
        return text
    }
}
