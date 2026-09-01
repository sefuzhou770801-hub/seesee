import Foundation

@main
struct DigestAPICheck {
    static func main() {
        checkExplainPrompt()
        checkRequestJSON()
        checkResponseParse()
        checkMissingKeyHint()
        print("digest_api_check=passed")
    }

    private static func checkExplainPrompt() {
        precondition(DigestExplainPrompt.systemPrompt.contains("1 到 3 句") || DigestExplainPrompt.systemPrompt.contains("1到3句"))
        precondition(DigestExplainPrompt.systemPrompt.contains("最多"))
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
        precondition(WatchQAAPIKey.resolve(defaults: UserDefaults(suiteName: "digest-api-empty-\(UUID().uuidString)")!, environment: [:]) == nil)
    }
}
