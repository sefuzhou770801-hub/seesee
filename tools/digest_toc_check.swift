import Foundation

@main
struct DigestTOCCheck {
    static func main() throws {
        checkCopy()
        checkMergeWithSkeleton()
        checkMergeWithoutSkeleton()
        checkMergeCountMismatch()
        checkMergeExtraAIChapters()
        checkQuoteSnapsToCueAndDropsInvented()
        checkAtMostOneQuotePerChapter()
        checkQuoteMatchesSentenceBlocks()
        try checkCacheVersionInvalidation()
        print("digest_toc_check=passed")
    }

    private static func checkCopy() {
        precondition(DigestTOCCopy.generateTitle == "生成目录")
        precondition(DigestTOCCopy.generatingLabel == "正在生成目录…")
        precondition(DigestTOCCopy.retryButtonTitle == "再试一次")
        precondition(DigestTOCCopy.collapsedTitle(chapterCount: 5, duration: 750) == "目录 · 5 章 · 12:30")
        precondition(DigestTOCCopy.collapsedTitle(chapterCount: 1, duration: 45) == "目录 · 1 章 · 0:45")
        precondition(
            DigestTOCCopy.sourceNote(.videoChapters) == "章节来自视频，概括与金句由 AI 补"
        )
        precondition(
            DigestTOCCopy.sourceNote(.generated) == "章节与概括由 AI 生成"
        )
        precondition(DigestTOCCopy.missingKeyHint == DigestCopy.missingKeyHint)
        precondition(!DigestTOCCopy.missingKeyHint.contains("defaults"))
        precondition(!DigestTOCCopy.missingKeyHint.contains("AnthropicAPIKey"))
        checkCompleteness()
        checkLooseQuoteMatch()
    }

    private static func checkCompleteness() {
        let cues = [
            VideoSubtitleCue(startTime: 15, endTime: 18, text: "We wanted to think outside the box\n我们想跳出框框来想"),
            VideoSubtitleCue(startTime: 180, endTime: 184, text: "Always measure twice"),
            VideoSubtitleCue(startTime: 320, endTime: 324, text: "That is the conclusion")
        ]
        let quote0 = DigestKeyQuote(
            quote: "We wanted to think outside the box",
            translation: "我们想跳出框框来想",
            timestamp: "0:15",
            timestampSeconds: 15
        )
        let complete = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "开场", timestamp: "0:00", timestampSeconds: 0, summary: "介绍问题", quote: quote0),
                DigestGeneratedChapter(title: "方法", timestamp: "2:00", timestampSeconds: 120, summary: "讲做法"),
                DigestGeneratedChapter(title: "结论", timestamp: "5:00", timestampSeconds: 300, summary: "收束观点")
            ],
            keyQuotes: [],
            source: .generated,
            durationSeconds: 400
        )
        precondition(DigestTOCCompleteness.hasAllSummaries(complete), "缺金句仍算结构完整")
        var missingSummary = complete
        missingSummary.chapters[0].summary = "  "
        precondition(!DigestTOCCompleteness.hasAllSummaries(missingSummary), "概括缺失才算不完整")
        let filled = DigestTOCCompleteness.fillingMissingSummaries(missingSummary)
        precondition(filled.chapters[0].summary == DigestCopy.missingSummaryPlaceholder)
        precondition(DigestTOCCompleteness.hasAllSummaries(filled), "占位后应能保存")

        var invented = complete
        invented.chapters[0].quote = DigestKeyQuote(
            quote: "this quote is not in the transcript",
            translation: "捏造的句子",
            timestamp: "0:15",
            timestampSeconds: 15
        )
        let composed = DigestTOCComposer.compose(
            skeleton: [],
            ai: invented,
            duration: 400,
            cues: cues
        )
        precondition(composed.chapters[0].quote == nil, "匹配不上的金句须丢弃，不得判整份失败")
        precondition(DigestTOCCompleteness.hasAllSummaries(composed))
    }

    private static func checkLooseQuoteMatch() {
        precondition(
            DigestQuoteNormalize.looselyMatches(
                quote: "Hello, WORLD!",
                translation: "",
                cueText: "hello world"
            ),
            "去标点与大小写后应能子串匹配"
        )
        precondition(
            DigestQuoteNormalize.looselyMatches(
                quote: "Ｈｅｌｌｏ",
                translation: "",
                cueText: "hello"
            ),
            "全半角统一后应能匹配"
        )
        precondition(
            DigestQuoteNormalize.looselyMatches(
                quote: "not in the original",
                translation: "大家好。",
                cueText: "Hello world.\n大家好。"
            ),
            "译文匹配即可"
        )
        precondition(
            !DigestQuoteNormalize.looselyMatches(
                quote: "totally invented line",
                translation: "完全捏造",
                cueText: "Hello world.\n大家好。"
            )
        )
        let cues = [
            VideoSubtitleCue(startTime: 15, endTime: 18, text: "We wanted to think outside the box\n我们想跳出框框来想")
        ]
        let punctuated = DigestKeyQuote(
            quote: "We wanted, to think outside the box!",
            translation: "",
            timestamp: "0:15",
            timestampSeconds: 15
        )
        precondition(
            DigestTOCComposer.quoteMatchesChapter(punctuated, range: 0..<30, cues: cues),
            "带标点的金句应对上原文"
        )
    }

    /// 有自带章节：目录章节数与自带章节一致，标题与时间码来自骨架，每章一句概括。
    private static func checkMergeWithSkeleton() {
        let skeleton = [
            VideoChapter(title: "开场", startTime: 0, endTime: 120),
            VideoChapter(title: "方法", startTime: 120, endTime: 300),
            VideoChapter(title: "结论", startTime: 300, endTime: nil)
        ]
        let ai = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "AI 会改这个标题", timestamp: "0:00", timestampSeconds: 0, summary: "介绍问题"),
                DigestGeneratedChapter(title: "AI 方法", timestamp: "2:00", timestampSeconds: 120, summary: "讲做法"),
                DigestGeneratedChapter(title: "AI 结论", timestamp: "5:00", timestampSeconds: 300, summary: "收束观点")
            ],
            keyQuotes: [
                DigestKeyQuote(
                    quote: "think outside the box",
                    translation: "跳出框框来想",
                    timestamp: "0:15",
                    timestampSeconds: 15
                )
            ]
        )
        let cues = [
            VideoSubtitleCue(
                startTime: 15,
                endTime: 18,
                text: "We wanted to think outside the box\n我们想跳出框框来想"
            ),
            VideoSubtitleCue(startTime: 180, endTime: 184, text: "Always measure twice")
        ]
        let toc = DigestTOCComposer.compose(
            skeleton: skeleton,
            ai: ai,
            duration: 420,
            cues: cues
        )
        precondition(toc.chapters.count == 3, "有骨架时章节数必须与自带章节一致")
        precondition(toc.chapters.map(\.title) == ["开场", "方法", "结论"], "标题必须来自视频章节")
        precondition(toc.chapters.map(\.timestampSeconds) == [0, 120, 300])
        precondition(toc.chapters[0].summary == "介绍问题")
        precondition(toc.chapters[1].summary == "讲做法")
        precondition(toc.chapters[2].summary == "收束观点")
        precondition(toc.source == .videoChapters)
        precondition(toc.durationSeconds == 420)
        precondition(toc.chapters[0].quote?.quote == "We wanted to think outside the box")
        precondition(toc.chapters[0].quote?.translation == "我们想跳出框框来想")
        precondition(toc.chapters[0].quote?.timestampSeconds == 15)
        precondition(toc.chapters[1].quote == nil)
        precondition(toc.chapters[2].quote == nil)
    }

    /// 无自带章节：采用 AI 分章，来源为 generated。
    private static func checkMergeWithoutSkeleton() {
        let ai = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "引入", timestamp: "0:00", timestampSeconds: 0, summary: "开场白"),
                DigestGeneratedChapter(title: "展开", timestamp: "4:00", timestampSeconds: 240, summary: "主体")
            ],
            keyQuotes: [
                DigestKeyQuote(
                    quote: "hello world",
                    translation: "你好世界",
                    timestamp: "0:10",
                    timestampSeconds: 10
                )
            ]
        )
        let cues = [
            VideoSubtitleCue(startTime: 10, endTime: 12, text: "hello world\n你好世界")
        ]
        let toc = DigestTOCComposer.compose(
            skeleton: [],
            ai: ai,
            duration: 600,
            cues: cues
        )
        precondition(toc.chapters.count == 2)
        precondition(toc.chapters[0].title == "引入")
        precondition(toc.chapters[1].title == "展开")
        precondition(toc.chapters[0].summary == "开场白")
        precondition(toc.source == .generated)
        precondition(toc.durationSeconds == 600)
        precondition(toc.chapters[0].quote?.quote == "hello world")
        precondition(toc.chapters[0].quote?.translation == "你好世界")
    }

    /// AI 返回的章节数少于骨架：仍保持骨架三章，按时间落入的概括与金句对齐。
    private static func checkMergeCountMismatch() {
        let skeleton = [
            VideoChapter(title: "一", startTime: 0, endTime: 100),
            VideoChapter(title: "二", startTime: 100, endTime: 200),
            VideoChapter(title: "三", startTime: 200, endTime: 300)
        ]
        let ai = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "错题", timestamp: "0:10", timestampSeconds: 10, summary: "第一章概括"),
                DigestGeneratedChapter(title: "也错", timestamp: "3:40", timestampSeconds: 220, summary: "第三章概括")
            ],
            keyQuotes: [
                DigestKeyQuote(
                    quote: "middle insight",
                    translation: "中间洞见",
                    timestamp: "2:00",
                    timestampSeconds: 120
                )
            ]
        )
        let cues = [
            VideoSubtitleCue(startTime: 10, endTime: 12, text: "start talk"),
            VideoSubtitleCue(startTime: 120, endTime: 124, text: "middle insight\n中间洞见"),
            VideoSubtitleCue(startTime: 220, endTime: 224, text: "ending now")
        ]
        let toc = DigestTOCComposer.compose(
            skeleton: skeleton,
            ai: ai,
            duration: 300,
            cues: cues
        )
        precondition(toc.chapters.count == 3, "章节数不一致时仍以骨架为准")
        precondition(toc.chapters.map(\.title) == ["一", "二", "三"])
        precondition(toc.chapters[0].summary == "第一章概括")
        precondition(toc.chapters[1].summary == "", "范围内没有 AI 章节时概括留空")
        precondition(toc.chapters[2].summary == "第三章概括")
        precondition(toc.chapters[1].quote?.quote == "middle insight")
        precondition(toc.source == .videoChapters)
    }

    /// AI 多返回章节时丢弃多余项，骨架长度不变。
    private static func checkMergeExtraAIChapters() {
        let skeleton = [
            VideoChapter(title: "上", startTime: 0, endTime: 60),
            VideoChapter(title: "下", startTime: 60, endTime: 120)
        ]
        let ai = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "A", timestamp: "0:00", timestampSeconds: 0, summary: "上半"),
                DigestGeneratedChapter(title: "B", timestamp: "0:30", timestampSeconds: 30, summary: "不该覆盖上半"),
                DigestGeneratedChapter(title: "C", timestamp: "1:10", timestampSeconds: 70, summary: "下半"),
                DigestGeneratedChapter(title: "D", timestamp: "1:50", timestampSeconds: 110, summary: "多余")
            ],
            keyQuotes: []
        )
        let toc = DigestTOCComposer.compose(
            skeleton: skeleton,
            ai: ai,
            duration: 120,
            cues: []
        )
        precondition(toc.chapters.count == 2)
        precondition(toc.chapters.map(\.title) == ["上", "下"])
        precondition(toc.chapters[0].summary == "上半")
        precondition(toc.chapters[1].summary == "下半")
    }

    /// 金句必须能在该章字幕里找到原文；编造的句子丢弃。
    private static func checkQuoteSnapsToCueAndDropsInvented() {
        let skeleton = [
            VideoChapter(title: "章", startTime: 0, endTime: 60)
        ]
        let invented = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "章", timestamp: "0:00", timestampSeconds: 0, summary: "概括")
            ],
            keyQuotes: [
                DigestKeyQuote(
                    quote: "this quote is not in the transcript",
                    translation: "字幕里没有",
                    timestamp: "0:10",
                    timestampSeconds: 10
                )
            ]
        )
        let cues = [
            VideoSubtitleCue(startTime: 8, endTime: 12, text: "welcome aboard")
        ]
        let dropped = DigestTOCComposer.compose(
            skeleton: skeleton,
            ai: invented,
            duration: 60,
            cues: cues
        )
        precondition(dropped.chapters[0].quote == nil, "编造金句必须丢弃")

        let nested = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(
                    title: "章",
                    timestamp: "0:00",
                    timestampSeconds: 0,
                    summary: "概括",
                    quote: DigestKeyQuote(
                        quote: "welcome aboard",
                        translation: "欢迎上船",
                        timestamp: "0:08",
                        timestampSeconds: 8
                    )
                )
            ],
            keyQuotes: []
        )
        let snapped = DigestTOCComposer.compose(
            skeleton: skeleton,
            ai: nested,
            duration: 60,
            cues: cues
        )
        precondition(snapped.chapters[0].quote?.quote == "welcome aboard")
        precondition(snapped.chapters[0].quote?.timestampSeconds == 8)
    }

    /// 一章至多一条金句；后续落入同章的金句丢弃。
    private static func checkAtMostOneQuotePerChapter() {
        let skeleton = [
            VideoChapter(title: "章", startTime: 0, endTime: 60)
        ]
        let ai = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "章", timestamp: "0:00", timestampSeconds: 0, summary: "概括")
            ],
            keyQuotes: [
                DigestKeyQuote(quote: "first line", translation: "第一句", timestamp: "0:05", timestampSeconds: 5),
                DigestKeyQuote(quote: "second line", translation: "第二句", timestamp: "0:20", timestampSeconds: 20)
            ]
        )
        let cues = [
            VideoSubtitleCue(startTime: 5, endTime: 8, text: "first line"),
            VideoSubtitleCue(startTime: 20, endTime: 24, text: "second line")
        ]
        let toc = DigestTOCComposer.compose(
            skeleton: skeleton,
            ai: ai,
            duration: 60,
            cues: cues
        )
        precondition(toc.chapters[0].quote?.quote == "first line")
    }

    /// 金句按句块回查：整句配对原文译文、跨块取时间码最近的一块、去掉语气词后仍能模糊命中。
    private static func checkQuoteMatchesSentenceBlocks() {
        let raw = [
            VideoSubtitleCue(startTime: 0.5, endTime: 2.26, text: "One of the most common questions my students\n我的学生问我最常见的问题之一"),
            VideoSubtitleCue(startTime: 2.28, endTime: 3.58, text: "at Stanford ask me is\n在斯坦福大学问我的是"),
            VideoSubtitleCue(startTime: 3.72, endTime: 4.92, text: "I'm stuck in a rut\n我陷入困境了"),
            VideoSubtitleCue(startTime: 5.02, endTime: 6.02, text: "what do I do?\n我该怎么办？"),
            VideoSubtitleCue(startTime: 6.18, endTime: 8.52, text: "My answer is, it's likely due to one of four things.\n我的回答是，这很可能与四件事中的一件有关。"),
            VideoSubtitleCue(startTime: 9.0, endTime: 11.0, text: "All right, so here we are, in front of the\n好了，我们现在"),
            VideoSubtitleCue(startTime: 11.0, endTime: 12.5, text: "elephants.\n在大象前面。"),
            VideoSubtitleCue(startTime: 20.0, endTime: 24.0, text: "So, um, you know, the key is to, like, keep shipping every single week.\n所以，呃，你知道，关键是，就像，每周都要持续交付。")
        ]
        let blocks = SubtitleSentenceBlocks.aggregate(raw)
        precondition(blocks.count == 4, "夹具应聚成 4 个句块，实际 \(blocks.count)")
        let skeleton = [VideoChapter(title: "章", startTime: 0, endTime: 60)]
        func compose(_ quote: DigestKeyQuote) -> DigestKeyQuote? {
            let ai = DigestOverviewPayload(
                chapters: [DigestGeneratedChapter(title: "章", timestamp: "0:00", timestampSeconds: 0, summary: "概括", quote: quote)],
                keyQuotes: []
            )
            return DigestTOCComposer.compose(skeleton: skeleton, ai: ai, duration: 60, cues: blocks).chapters[0].quote
        }

        // 整句金句跨四条 ASR 碎片：按碎片对不上，按句块整句命中，原文译文都是整句。
        let sentence = compose(DigestKeyQuote(
            quote: "One of the most common questions my students at Stanford ask me is: I'm stuck in a rut, what do I do?",
            translation: "我的学生问我最常见的问题之一是：我陷入困境了，该怎么办？",
            timestamp: "0:00",
            timestampSeconds: 0
        ))
        precondition(sentence != nil, "整句金句必须命中句块")
        precondition(sentence?.timestampSeconds == 0.5)
        precondition(sentence?.quote == "One of the most common questions my students at Stanford ask me is I'm stuck in a rut what do I do?")
        precondition(sentence?.translation == "我的学生问我最常见的问题之一在斯坦福大学问我的是我陷入困境了我该怎么办？")

        // #39 现象：原文取到半句、译文配成「大象」。改后原文译文各是完整一句。
        let elephants = compose(DigestKeyQuote(
            quote: "All right, so here we are, in front of the elephants",
            translation: "好了，我们现在在大象前面",
            timestamp: "0:09",
            timestampSeconds: 9
        ))
        precondition(elephants?.quote == "All right, so here we are, in front of the elephants.")
        precondition(elephants?.translation == "好了，我们现在在大象前面。")
        precondition(elephants?.timestampSeconds == 9.0)

        // 模型去掉了语气词：整句包含失败，词元重合命中。
        let cleaned = compose(DigestKeyQuote(
            quote: "The key is to keep shipping every single week.",
            translation: "关键是每周都要持续交付。",
            timestamp: "0:20",
            timestampSeconds: 20
        ))
        precondition(cleaned?.timestampSeconds == 20.0, "去语气词的金句应模糊命中")
        precondition(cleaned?.quote.hasPrefix("So, um, you know") == true, "命中后取句块原文")

        // 金句拼接了两句：两块都落在金句里，取时间码最近的一块。
        let spanning = compose(DigestKeyQuote(
            quote: "I'm stuck in a rut, what do I do? My answer is, it's likely due to one of four things.",
            translation: "",
            timestamp: "0:06",
            timestampSeconds: 6.18
        ))
        precondition(spanning?.timestampSeconds == 6.18, "跨块金句取时间码最近的句块，实际 \(String(describing: spanning?.timestampSeconds))")

        // 章节起点按整秒显示值给（0:41），句块实际起点 40.6：边界放宽后仍归该章。
        let boundaryCues = [
            VideoSubtitleCue(startTime: 12.945, endTime: 26.9, text: "We find when that circuitry is not working you get apathy.\n我们发现回路不起作用时你会冷漠。"),
            VideoSubtitleCue(startTime: 27.8, endTime: 40.5, text: "So of course this is overly simplistic.\n所以当然这过于简化了。"),
            VideoSubtitleCue(startTime: 40.597, endTime: 48.0, text: "In graduating the level of motivation we have to seek particular outcomes.\n在调节我们动力水平方面以寻求特定结果。")
        ]
        let boundaryAI = DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(title: "一", timestamp: "0:00", timestampSeconds: 0, summary: "一"),
                DigestGeneratedChapter(
                    title: "二", timestamp: "0:13", timestampSeconds: 13, summary: "二",
                    quote: DigestKeyQuote(quote: "We find when that circuitry is not working you get apathy.", translation: "", timestamp: "0:13", timestampSeconds: 13)
                ),
                DigestGeneratedChapter(
                    title: "三", timestamp: "0:41", timestampSeconds: 41, summary: "三",
                    quote: DigestKeyQuote(quote: "In graduating the level of motivation we have to seek particular outcomes.", translation: "", timestamp: "0:41", timestampSeconds: 41)
                )
            ],
            keyQuotes: [
                DigestKeyQuote(quote: "So of course this is overly simplistic.", translation: "", timestamp: "0:27", timestampSeconds: 27)
            ]
        )
        let boundary = DigestTOCComposer.compose(skeleton: [], ai: boundaryAI, duration: 60, cues: boundaryCues)
        precondition(boundary.chapters[1].quote?.timestampSeconds == 12.945, "章起点 0:13 应收下 12.9 秒起的句块")
        precondition(boundary.chapters[2].quote?.timestampSeconds == 40.597, "章起点 0:41 应收下 40.6 秒起的句块")
        precondition(boundary.chapters[1].quote?.quote.hasPrefix("We find") == true, "本章自带金句优先于额外金句")

        // 编造的整句：词元重合不足，仍然丢弃。
        let invented = compose(DigestKeyQuote(
            quote: "Nothing in this video ever mentioned quantum computing at all",
            translation: "视频里完全没提量子计算",
            timestamp: "0:05",
            timestampSeconds: 5
        ))
        precondition(invented == nil, "编造金句必须丢弃")
    }

    /// 探索分支 schema 2 缓存必须作废；当前版本可读写。
    private static func checkCacheVersionInvalidation() throws {
        precondition(DigestOverviewStore.currentSchemaVersion == 4, "金句改按句块回查须递增缓存版本，作废旧目录")

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-toc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let staleID = UUID()
        let stale = DigestOverviewRecord(
            payload: DigestOverviewPayload(
                chapters: [
                    DigestGeneratedChapter(title: "旧", timestamp: "0:00", timestampSeconds: 0, summary: "旧概括")
                ],
                keyQuotes: []
            ),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-sonnet-5",
            language: "zh-Hans",
            schemaVersion: 2
        )
        try DigestOverviewStore.save(stale, itemID: staleID, folder: folder)
        precondition(DigestOverviewStore.fileExists(itemID: staleID, folder: folder))
        precondition(
            DigestOverviewStore.load(itemID: staleID, folder: folder) == nil,
            "schema 2 必须视为过期"
        )
        let staleQuoteID = UUID()
        var staleQuotes = stale
        staleQuotes.schemaVersion = 3
        try DigestOverviewStore.save(staleQuotes, itemID: staleQuoteID, folder: folder)
        precondition(
            DigestOverviewStore.load(itemID: staleQuoteID, folder: folder) == nil,
            "schema 3（按碎片配金句）必须视为过期"
        )

        let freshID = UUID()
        let composed = DigestTOCComposer.compose(
            skeleton: [VideoChapter(title: "开场", startTime: 0, endTime: nil)],
            ai: DigestOverviewPayload(
                chapters: [
                    DigestGeneratedChapter(title: "开场", timestamp: "0:00", timestampSeconds: 0, summary: "介绍")
                ],
                keyQuotes: []
            ),
            duration: 90,
            cues: []
        )
        let fresh = DigestOverviewRecord(
            payload: composed,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            model: "claude-sonnet-5"
        )
        try DigestOverviewStore.save(fresh, itemID: freshID, folder: folder)
        let loaded = DigestOverviewStore.load(itemID: freshID, folder: folder)
        precondition(loaded?.schemaVersion == 4)
        precondition(loaded?.payload.chapters.count == 1)
        precondition(loaded?.payload.chapters[0].title == "开场")
        precondition(loaded?.payload.chapters[0].summary == "介绍")
        precondition(loaded?.payload.source == .videoChapters)
        precondition(loaded?.payload.durationSeconds == 90)
    }
}
