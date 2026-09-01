import Foundation

@main
struct DigestAPICheck {
    static func main() {
        checkExplainPrompt()
        checkRequestJSON()
        checkResponseParse()
        checkMissingKeyHint()
        checkProviderResolve()
        checkGeminiKeyResolve()
        checkGeminiRequestJSON()
        checkGeminiResponseParse()
        print("digest_api_check=passed")
    }

    private static func checkExplainPrompt() {
        precondition(DigestExplainPrompt.systemPrompt.contains("1 到 3 句") || DigestExplainPrompt.systemPrompt.contains("1到3句"))
        precondition(DigestExplainPrompt.systemPrompt.contains("最多"))
        precondition(DigestExplainPrompt.systemPrompt.contains("简体中文"))
        precondition(DigestExplainPrompt.systemPrompt.contains("不得写成英文句子"))
        let user = DigestExplainPrompt.userText(
            videoTitle: "Demo",
            selected: "transformer",
            context: "[1:00] we use a transformer"
        )
        precondition(user.contains("SELECTED: \"transformer\""))
        precondition(user.contains("VIDEO: Demo"))
        precondition(user.contains("[1:00] we use a transformer"))

        let emptyContext = DigestExplainPrompt.userText(videoTitle: "Demo", selected: "x", context: "  ")
        precondition(emptyContext.contains("CONTEXT: None"))
        precondition(user.contains("简体中文"))

        let cues = [
            VideoSubtitleCue(startTime: 0, endTime: 2, text: "one"),
            VideoSubtitleCue(startTime: 10, endTime: 12, text: "two\n二"),
            VideoSubtitleCue(startTime: 20, endTime: 22, text: "three"),
            VideoSubtitleCue(startTime: 30, endTime: 32, text: "four")
        ]
        let around = DigestExplainPrompt.context(around: 1, in: cues, window: 1)
        precondition(around.contains("[0:00] one"))
        precondition(around.contains("[0:10] two 二"))
        precondition(around.contains("[0:20] three"))
        precondition(!around.contains("[0:30] four"))
    }

    private static func checkRequestJSON() {
        let object = DigestRequestBuilder.jsonObject(
            system: "sys",
            user: "hello",
            maxTokens: 256
        )
        precondition(object["model"] as? String == WatchQARequestBuilder.model)
        precondition(object["model"] as? String == "claude-sonnet-5")
        precondition(object["max_tokens"] as? Int == 256)
        precondition(object["stream"] as? Bool == false)
        precondition(object["system"] as? String == "sys")
        let messages = object["messages"] as? [[String: Any]]
        precondition(messages?.count == 1)
        precondition(messages?[0]["role"] as? String == "user")
        precondition(messages?[0]["content"] as? String == "hello")
        precondition(DigestRequestBuilder.endpoint == WatchQARequestBuilder.endpoint)
        precondition(DigestRequestBuilder.anthropicVersion == WatchQARequestBuilder.anthropicVersion)
    }

    private static func checkResponseParse() {
        let data = Data(#"{"content":[{"type":"text","text":"第一句。第二句。"}]}"#.utf8)
        precondition(DigestRequestBuilder.text(fromResponse: data) == "第一句。第二句。")

        let empty = Data(#"{"content":[]}"#.utf8)
        precondition(DigestRequestBuilder.text(fromResponse: empty) == nil)

        let errorData = Data(#"{"error":{"message":"invalid x-api-key"}}"#.utf8)
        precondition(DigestRequestBuilder.errorMessage(status: 401, data: errorData) == "invalid x-api-key")
    }

    private static func checkMissingKeyHint() {
        precondition(DigestRequestBuilder.missingKeyHint == "未配置密钥")
        let empty = UserDefaults(suiteName: "digest-api-empty-\(UUID().uuidString)")!
        precondition(WatchQAAPIKey.resolve(defaults: empty, environment: [:]) == nil)
        precondition(DigestGeminiAPIKey.resolve(defaults: empty, environment: [:]) == nil)
        precondition(DigestAPIKey.resolve(provider: .anthropic, defaults: empty, environment: [:]) == nil)
        precondition(DigestAPIKey.resolve(provider: .gemini, defaults: empty, environment: [:]) == nil)
    }

    private static func checkProviderResolve() {
        let suite = "digest-provider-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(DigestProvider.resolve(defaults: defaults) == .anthropic, "缺省须为 anthropic")
        defaults.set("gemini", forKey: DigestProvider.defaultsKey)
        precondition(DigestProvider.resolve(defaults: defaults) == .gemini)
        defaults.set(" GEMINI ", forKey: DigestProvider.defaultsKey)
        precondition(DigestProvider.resolve(defaults: defaults) == .gemini, "大小写与空白须忽略")
        defaults.set("anthropic", forKey: DigestProvider.defaultsKey)
        precondition(DigestProvider.resolve(defaults: defaults) == .anthropic)
        defaults.set("unknown", forKey: DigestProvider.defaultsKey)
        precondition(DigestProvider.resolve(defaults: defaults) == .anthropic, "未知值回落 anthropic")
        precondition(DigestProvider.defaultsKey == "DigestProvider")
    }

    private static func checkGeminiKeyResolve() {
        let suite = "digest-gemini-key-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(DigestGeminiAPIKey.defaultsKey == "GeminiAPIKey")
        precondition(DigestGeminiAPIKey.environmentKey == "GEMINI_API_KEY")
        precondition(DigestGeminiAPIKey.resolve(defaults: defaults, environment: [:]) == nil)

        defaults.set("  gemini-from-defaults  ", forKey: DigestGeminiAPIKey.defaultsKey)
        precondition(
            DigestGeminiAPIKey.resolve(
                defaults: defaults,
                environment: [DigestGeminiAPIKey.environmentKey: "gemini-from-env"]
            ) == "gemini-from-defaults",
            "defaults 优先于环境变量"
        )

        defaults.removeObject(forKey: DigestGeminiAPIKey.defaultsKey)
        precondition(
            DigestGeminiAPIKey.resolve(
                defaults: defaults,
                environment: [DigestGeminiAPIKey.environmentKey: "  gemini-from-env  "]
            ) == "gemini-from-env",
            "defaults 为空时用 GEMINI_API_KEY"
        )

        precondition(
            DigestAPIKey.resolve(provider: .gemini, defaults: defaults, environment: [
                DigestGeminiAPIKey.environmentKey: "gemini-from-env"
            ]) == "gemini-from-env"
        )
        precondition(
            DigestAPIKey.resolve(
                provider: .anthropic,
                defaults: defaults,
                environment: [DigestGeminiAPIKey.environmentKey: "gemini-from-env"]
            ) == nil,
            "anthropic 提供方不得误用 Gemini 密钥"
        )
    }

    private static func checkGeminiRequestJSON() {
        let object = DigestGeminiRequestBuilder.jsonObject(
            system: "sys",
            user: "hello",
            maxTokens: 256
        )
        let instruction = object["systemInstruction"] as? [String: Any]
        let instructionParts = instruction?["parts"] as? [[String: Any]]
        precondition(instructionParts?.count == 1)
        precondition(instructionParts?[0]["text"] as? String == "sys")

        let contents = object["contents"] as? [[String: Any]]
        precondition(contents?.count == 1)
        precondition(contents?[0]["role"] as? String == "user")
        let userParts = contents?[0]["parts"] as? [[String: Any]]
        precondition(userParts?[0]["text"] as? String == "hello")

        let config = object["generationConfig"] as? [String: Any]
        precondition(config?["maxOutputTokens"] as? Int == 256)
        precondition(object["model"] == nil, "Gemini 模型在 URL 路径里，不进 JSON 体")

        precondition(DigestGeminiRequestBuilder.model == "gemini-3.7-flash")
        let url = DigestGeminiRequestBuilder.requestURL(apiKey: "abc/def")
        precondition(url.absoluteString.contains("generativelanguage.googleapis.com/v1beta/models/gemini-3.7-flash:generateContent"))
        precondition(url.absoluteString.contains("key="))
        precondition(url.absoluteString.contains("abc") && url.absoluteString.contains("def"))
        precondition(DigestProviderKind.gemini.activeModel == "gemini-3.7-flash")
        precondition(DigestProviderKind.anthropic.activeModel == WatchQARequestBuilder.model)
    }

    private static func checkGeminiResponseParse() {
        let data = Data(#"{"candidates":[{"content":{"parts":[{"text":"第一句。"},{"text":"第二句。"}]}}]}"#.utf8)
        precondition(DigestGeminiRequestBuilder.text(fromResponse: data) == "第一句。第二句。")

        let empty = Data(#"{"candidates":[]}"#.utf8)
        precondition(DigestGeminiRequestBuilder.text(fromResponse: empty) == nil)

        let blocked = Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8)
        precondition(DigestGeminiRequestBuilder.text(fromResponse: blocked) == nil)

        let errorData = Data(#"{"error":{"message":"API key not valid","code":400}}"#.utf8)
        precondition(DigestRequestBuilder.errorMessage(status: 400, data: errorData) == "API key not valid")
    }
}
