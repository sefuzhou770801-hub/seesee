import Foundation

@main
struct DigestOverviewCheck {
    static func main() throws {
        checkTimecode()
        checkTranscriptFormat()
        checkPromptCoverageRule()
        checkParse()
        try checkCacheRoundTrip()
        print("digest_overview_check=passed")
    }

    private static func checkTimecode() {
        precondition(DigestTimecode.format(0) == "0:00")
        precondition(DigestTimecode.format(45) == "0:45")
        precondition(DigestTimecode.format(150) == "2:30")
        precondition(DigestTimecode.format(3750) == "1:02:30")
        precondition(DigestTimecode.seconds(from: "2:30") == 150)
        precondition(DigestTimecode.seconds(from: "0:45") == 45)
        precondition(DigestTimecode.seconds(from: "1:02:30") == 3750)
        precondition(DigestOverviewPrompt.lateThreshold(duration: 600) == 450)
        precondition(DigestOverviewPrompt.lateThreshold(duration: 10) == 7.5)
    }

    private static func checkTranscriptFormat() {
        let cues = [
            VideoSubtitleCue(startTime: 0, endTime: 2, text: "Welcome\n欢迎"),
            VideoSubtitleCue(startTime: 150, endTime: 154, text: "We wanted to think outside the box")
        ]
        let text = DigestOverviewPrompt.timestampedTranscript(from: cues)
        precondition(text.contains("[0:00] Welcome 欢迎"))
        precondition(text.contains("[2:30] We wanted to think outside the box"))
        let lines = text.split(separator: "\n")
        precondition(lines.count == 2)
        precondition(lines[0].hasPrefix("[0:00]"))
    }

    private static func checkPromptCoverageRule() {
        let prompt = DigestOverviewPrompt.systemPrompt(duration: 600)
        precondition(prompt.contains("COVER THE ENTIRE VIDEO"))
        precondition(prompt.contains("7:30"), "lateThreshold 须写入提示词，实际未含 7:30")
        precondition(prompt.contains("10:00"))
        precondition(prompt.contains("Do NOT stop partway through"))
        precondition(prompt.contains("简体中文"), "章节必须强制简体中文")
        precondition(prompt.contains("translation"), "金句须带中文翻译字段")
        precondition(!prompt.contains("same language as the transcript"))
        let user = DigestOverviewPrompt.userPrompt(title: "Talk", author: "A", duration: 600, transcript: "[0:00] hi")
        precondition(user.contains("简体中文"))

        let early = [
            DigestGeneratedChapter(title: "开场", timestamp: "0:00", timestampSeconds: 0, summary: ""),
            DigestGeneratedChapter(title: "中段", timestamp: "2:00", timestampSeconds: 120, summary: "")
        ]
        precondition(!DigestOverviewPrompt.lastChapterCoversLatePart(chapters: early, duration: 600))

        let covered = early + [
            DigestGeneratedChapter(title: "收尾", timestamp: "8:00", timestampSeconds: 480, summary: "")
        ]
        precondition(DigestOverviewPrompt.lastChapterCoversLatePart(chapters: covered, duration: 600))
    }

    private static func checkParse() {
        let raw = """
        {
          "chapters": [
            {"title": "开场", "timestamp": "0:00", "timestampSeconds": 0, "summary": "介绍主题"},
            {"title": "结论", "timestamp": "8:10", "timestampSeconds": 490, "summary": "收束"}
          ],
          "keyQuotes": [
            {"quote": "Keep the speaker's voice", "translation": "保留说话人的原话", "timestamp": "2:30", "timestampSeconds": 150}
          ]
        }
        """
        let parsed = DigestOverviewCodec.parse(raw)
        precondition(parsed?.chapters.count == 2)
        precondition(parsed?.chapters[1].title == "结论")
        precondition(parsed?.chapters[1].timestampSeconds == 490)
        precondition(parsed?.keyQuotes.count == 1)
        precondition(parsed?.keyQuotes[0].quote == "Keep the speaker's voice")
        precondition(parsed?.keyQuotes[0].translation == "保留说话人的原话")

        let fenced = """
        ```json
        \(raw)
        ```
        """
        precondition(DigestOverviewCodec.parse(fenced)?.chapters.count == 2, "须剥掉 markdown 围栏")

        let intSeconds = """
        {"chapters":[{"title":"A","timestamp":"1:00","timestampSeconds":60,"summary":""}],"keyQuotes":[]}
        """
        precondition(DigestOverviewCodec.parse(intSeconds)?.chapters.first?.timestampSeconds == 60)

        let fromStamp = """
        {"chapters":[{"title":"A","timestamp":"2:30","summary":""}],"keyQuotes":[]}
        """
        precondition(
            DigestOverviewCodec.parse(fromStamp)?.chapters.first?.timestampSeconds == 150,
            "缺 timestampSeconds 时从时间码回推"
        )

        precondition(DigestOverviewCodec.parse("not json") == nil)
    }

    private static func checkCacheRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-overview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let payload = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "开场", timestamp: "0:00", timestampSeconds: 0, summary: "介绍")
            ],
            keyQuotes: [
                DigestKeyQuote(quote: "hello", translation: "你好", timestamp: "0:15", timestampSeconds: 15)
            ]
        )
        let record = DigestOverviewRecord(
            payload: payload,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-sonnet-5"
        )
        try DigestOverviewStore.save(record, itemID: itemID, folder: folder)
        let url = DigestOverviewStore.fileURL(itemID: itemID, in: folder)
        precondition(url.lastPathComponent.hasSuffix(".digest.json"))
        precondition(url.lastPathComponent.hasPrefix(itemID.uuidString + "."))

        let loaded = DigestOverviewStore.load(itemID: itemID, folder: folder)
        precondition(loaded?.payload.chapters.count == 1)
        precondition(loaded?.payload.chapters[0].title == "开场")
        precondition(loaded?.payload.keyQuotes[0].quote == "hello")
        precondition(loaded?.payload.keyQuotes[0].translation == "你好")
        precondition(loaded?.model == "claude-sonnet-5")
        precondition(loaded?.language == "zh-Hans")
        precondition(loaded?.schemaVersion == 2)
        precondition(loaded?.generatedAt.timeIntervalSince1970 == 1_700_000_000)

        let stale = DigestOverviewRecord(
            payload: payload,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-sonnet-5",
            language: "",
            schemaVersion: 1
        )
        let staleID = UUID()
        try DigestOverviewStore.save(stale, itemID: staleID, folder: folder)
        precondition(DigestOverviewStore.fileExists(itemID: staleID, folder: folder))
        precondition(DigestOverviewStore.load(itemID: staleID, folder: folder) == nil, "旧英文缓存必须视为无效")

        let missingID = UUID()
        precondition(DigestOverviewStore.load(itemID: missingID, folder: folder) == nil)
    }
}
