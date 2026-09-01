import Foundation

struct DigestGeneratedChapter: Codable, Equatable, Identifiable {
    var title: String
    var timestamp: String
    var timestampSeconds: Double
    var summary: String

    var id: String { "\(timestampSeconds)-\(title)" }

    enum CodingKeys: String, CodingKey {
        case title, timestamp, timestampSeconds, summary
    }

    init(title: String, timestamp: String, timestampSeconds: Double, summary: String) {
        self.title = title
        self.timestamp = timestamp
        self.timestampSeconds = timestampSeconds
        self.summary = summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        if let value = try? container.decode(Double.self, forKey: .timestampSeconds) {
            timestampSeconds = value
        } else if let value = try? container.decode(Int.self, forKey: .timestampSeconds) {
            timestampSeconds = Double(value)
        } else {
            timestampSeconds = DigestTimecode.seconds(from: timestamp) ?? 0
        }
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(timestampSeconds, forKey: .timestampSeconds)
        try container.encode(summary, forKey: .summary)
    }
}

struct DigestKeyQuote: Codable, Equatable, Identifiable {
    var quote: String
    var timestamp: String
    var timestampSeconds: Double

    var id: String { "\(timestampSeconds)-\(quote)" }

    enum CodingKeys: String, CodingKey {
        case quote, timestamp, timestampSeconds
    }

    init(quote: String, timestamp: String, timestampSeconds: Double) {
        self.quote = quote
        self.timestamp = timestamp
        self.timestampSeconds = timestampSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quote = try container.decode(String.self, forKey: .quote)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        if let value = try? container.decode(Double.self, forKey: .timestampSeconds) {
            timestampSeconds = value
        } else if let value = try? container.decode(Int.self, forKey: .timestampSeconds) {
            timestampSeconds = Double(value)
        } else {
            timestampSeconds = DigestTimecode.seconds(from: timestamp) ?? 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quote, forKey: .quote)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(timestampSeconds, forKey: .timestampSeconds)
    }
}

struct DigestOverviewPayload: Codable, Equatable {
    var chapters: [DigestGeneratedChapter]
    var keyQuotes: [DigestKeyQuote]

    enum CodingKeys: String, CodingKey {
        case chapters, keyQuotes
    }

    init(chapters: [DigestGeneratedChapter], keyQuotes: [DigestKeyQuote]) {
        self.chapters = chapters
        self.keyQuotes = keyQuotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapters = try container.decodeIfPresent([DigestGeneratedChapter].self, forKey: .chapters) ?? []
        keyQuotes = try container.decodeIfPresent([DigestKeyQuote].self, forKey: .keyQuotes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chapters, forKey: .chapters)
        try container.encode(keyQuotes, forKey: .keyQuotes)
    }
}

struct DigestOverviewRecord: Codable, Equatable {
    var payload: DigestOverviewPayload
    var generatedAt: Date
    var model: String
}

enum DigestTimecode {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%d:%02d", minutes, remaining)
    }

    static func seconds(from text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        if parts.count == 1 { return Double(parts[0]) }
        if parts.count == 2 { return Double(parts[0] * 60 + parts[1]) }
        return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
    }
}

enum DigestOverviewPrompt {
    static func resolvedDuration(itemDuration: Double?, cues: [VideoSubtitleCue]) -> Double {
        if let itemDuration, itemDuration.isFinite, itemDuration > 0 {
            return itemDuration
        }
        return cues.map(\.endTime).max() ?? 0
    }

    static func lateThreshold(duration: Double) -> Double {
        duration * 0.75
    }

    static func timestampedTranscript(from cues: [VideoSubtitleCue]) -> String {
        cues.map { cue in
            let stamp = DigestTimecode.format(cue.startTime)
            let body = cue.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return "[\(stamp)] \(body)"
        }.joined(separator: "\n")
    }

    static func systemPrompt(duration: Double) -> String {
        let durationFormatted = DigestTimecode.format(duration)
        let late = DigestTimecode.format(lateThreshold(duration: duration))
        let maxTimestampSeconds = Int(duration.rounded())
        return """
        You're my executive assistant. I'm interested in this video. Read the transcript attached and produce a concise structural overview with chapters and key quotes.

        You must provide:
        - Chapters with timestamps that COVER THE ENTIRE VIDEO from start to finish. This video runs until \(durationFormatted). Use your own judgment for how many chapters there should be and where the natural topic shifts happen — make as many or as few as the content genuinely calls for. The only hard rule is COVERAGE: the chapters must span the whole timeline, and your LAST chapter MUST come after \(late). Do NOT stop partway through or cluster all the chapters near the beginning — the later parts of the video need chapters too.
        - 3-5 key quotes from the transcript with their timestamps

        For quotes, focus on:
        - Unique or contrarian insights that challenge conventional thinking
        - Surprising facts or statistics
        - Interesting anecdotes or stories
        - Quotable one-liners that capture the essence of an argument

        The quotes should be exactly what the speaker said, but clean up:
        - Transcription errors and typos
        - Missing or incorrect punctuation
        - Filler words (um, uh, like, you know, sort of, kind of)
        - Speech tics and false starts
        - Repeated words from stuttering
        Keep the speaker's voice and word choices intact — just polish for readability.

        Write chapter titles and summaries in the same language as the transcript (Chinese if the transcript is Chinese). Quotes stay in the speaker's language after polish.

        CRITICAL: TIMESTAMP EXTRACTION
        The transcript is formatted EXACTLY like this:
        [0:00] Welcome to today's video
        [0:15] Let me tell you about our project

        RULES FOR EXTRACTING TIMESTAMPS:
        1. Every line starts with a timestamp in [M:SS], [MM:SS], or [H:MM:SS] format
        2. To get the timestamp for a quote, find the LINE containing those words
        3. The timestamp is the [X:XX] at the START of that line
        4. Convert to seconds: [2:30] = 150 seconds, [0:45] = 45 seconds

        DO NOT:
        - Make up timestamps that don't exist in the transcript
        - Use 0:00 as a default — find the actual timestamp
        - Use timestamps > \(durationFormatted) (video is only \(maxTimestampSeconds) seconds)

        For CHAPTERS: Find where a topic begins, use that line's timestamp
        For QUOTES: Find the line containing the quote, use that line's timestamp
        Output JSON (no markdown fences):
        {
          "chapters": [
            {"title": "Title", "timestamp": "0:00", "timestampSeconds": 0, "summary": "What this section covers"}
          ],
          "keyQuotes": [
            {"quote": "Exact quote from transcript", "timestamp": "2:30", "timestampSeconds": 150}
          ]
        }

        CRITICAL:
        - timestamp: The [M:SS] from the transcript line (e.g., "2:30")
        - timestampSeconds: Convert to seconds (2:30 = 2*60+30 = 150)
        - NEVER use 0:00/0 unless the content actually starts at [0:00]
        - EVERY timestamp must exist in the transcript — look it up!
        """
    }

    static func userPrompt(
        title: String,
        author: String,
        duration: Double,
        transcript: String
    ) -> String {
        let durationFormatted = DigestTimecode.format(duration)
        let maxTimestampSeconds = Int(duration.rounded())
        return """
        Video title: \(title)
        Channel: \(author)
        VIDEO DURATION: \(durationFormatted) (\(maxTimestampSeconds) seconds) — do not use any timestamp beyond this!

        TRANSCRIPT:
        \(transcript)
        """
    }

    static func lastChapterCoversLatePart(chapters: [DigestGeneratedChapter], duration: Double) -> Bool {
        guard duration > 0, let last = chapters.max(by: { $0.timestampSeconds < $1.timestampSeconds }) else {
            return false
        }
        return last.timestampSeconds >= lateThreshold(duration: duration)
    }
}

enum DigestOverviewCodec {
    static func parse(_ text: String) -> DigestOverviewPayload? {
        guard let json = extractJSONObject(from: text),
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(DigestOverviewPayload.self, from: data)
    }

    static func extractJSONObject(from text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            if let firstNewline = body.firstIndex(of: "\n") {
                body = String(body[body.index(after: firstNewline)...])
            }
            if let fence = body.range(of: "```", options: .backwards) {
                body = String(body[..<fence.lowerBound])
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = body.firstIndex(of: "{"),
              let end = body.lastIndex(of: "}")
        else { return nil }
        return String(body[start...end])
    }
}

enum DigestOverviewStore {
    static let sidecarSuffix = "digest.json"

    static func fileURL(itemID: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent("\(itemID.uuidString).\(sidecarSuffix)")
    }

    static func load(itemID: UUID, folder: URL) -> DigestOverviewRecord? {
        load(from: fileURL(itemID: itemID, in: folder))
    }

    static func load(from url: URL) -> DigestOverviewRecord? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DigestOverviewRecord.self, from: data)
    }

    static func save(_ record: DigestOverviewRecord, itemID: UUID, folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: fileURL(itemID: itemID, in: folder), options: .atomic)
    }
}
