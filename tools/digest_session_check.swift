import Foundation

@main
struct DigestSessionCheck {
    static func main() async throws {
        checkEmptySurface()
        checkCopyIsProductVoice()
        try await MainActor.run {
            try checkLaunchSelectionLoadsSidecars()
            try checkSwitchThreeVideosIsolated()
            checkMissingKeyHints()
            try checkAnnotationDeferredDelete()
            try checkSaveFailureReverts()
            try checkCorruptLoadDoesNotOverwrite()
            try checkCommentCancelKeepsOriginal()
        }
        try await checkExplainProgressVisibleWithDelay()
        print("digest_session_check=passed")
    }

    private static func checkEmptySurface() {
        precondition(DigestCopy.emptyTitle == "暂无字幕")
        precondition(DigestCopy.emptyDetail(hasSubtitleSource: false) == DigestCopy.emptyUnavailableDetail)
        precondition(DigestCopy.emptyDetail(hasSubtitleSource: true) == DigestCopy.emptyLoadingDetail)
        precondition(!DigestCopy.showsBook(cueCount: 0, qaCount: 0))
        precondition(DigestCopy.showsBook(cueCount: 0, qaCount: 1), "仅有看时问答时仍显示侧栏内容")
        precondition(DigestCopy.showsBook(cueCount: 1, qaCount: 0))
        precondition(!DigestCopy.showsDigestActions(cueCount: 0), "无字幕不得出现生成目录与划线入口")
        precondition(DigestCopy.showsDigestActions(cueCount: 1))
    }

    private static func checkCopyIsProductVoice() {
        let banned = ["验收", "任务书", "实现者", "ticket", "spec"]
        let phrases = [
            DigestCopy.missingKeyHint,
            DigestCopy.viewConfigTitle,
            DigestCopy.requestFailed,
            DigestCopy.saveFailed,
            DigestCopy.fileCorrupt,
            DigestCopy.tocIncomplete,
            DigestCopy.noSubtitles,
            DigestCopy.writeFailed,
            DigestCopy.emptyTitle,
            DigestCopy.emptyLoadingDetail,
            DigestCopy.emptyUnavailableDetail,
            DigestRequestBuilder.missingKeyHint,
            DigestTOCCopy.missingKeyHint,
            DigestTOCCopy.generatingLabel,
            "稍等…",
            DigestExplainQuality.retryPrompt
        ]
        for phrase in phrases {
            for word in banned {
                precondition(!phrase.contains(word), "状态文案不得含任务描述措辞「\(word)」：\(phrase)")
            }
        }
        precondition(DigestRequestBuilder.missingKeyHint == DigestCopy.missingKeyHint)
        precondition(DigestTOCCopy.missingKeyHint == DigestCopy.missingKeyHint)
        precondition(DigestCopy.missingKeyHint.contains("密钥"))
        precondition(!DigestCopy.missingKeyHint.contains("defaults"))
        precondition(!DigestCopy.missingKeyHint.contains("AnthropicAPIKey"))
        precondition(!DigestCopy.missingKeyHint.contains("GeminiAPIKey"))
        precondition(DigestCopy.viewConfigTitle == "打开设置…")
    }

    @MainActor
    private static func checkLaunchSelectionLoadsSidecars() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let note = DigestNote(id: UUID(), time: 6, text: "Hello world.\n大家好。", createdAt: Date(), comment: "启动批语")
        let annotation = DigestAnnotation(
            id: UUID(),
            time: 6,
            text: "Hello world.\n大家好。",
            explanation: "启动批注",
            createdAt: Date(),
            model: "m"
        )
        try DigestNotesStore.save([note], itemID: itemID, folder: folder)
        try DigestAnnotationsStore.save([annotation], itemID: itemID, folder: folder)
        try DigestOverviewStore.save(
            DigestOverviewRecord(
                payload: DigestOverviewPayload(
                    chapters: [
                        DigestGeneratedChapter(
                            title: "开场",
                            timestamp: "0:00",
                            timestampSeconds: 0,
                            summary: "启动时就该看见"
                        )
                    ],
                    keyQuotes: [],
                    source: .videoChapters,
                    durationSeconds: 19
                ),
                generatedAt: Date(),
                model: "m"
            ),
            itemID: itemID,
            folder: folder
        )

        let session = DigestSession()
        session.apiKeyEnvironment = [:]
        session.ensureLoaded(itemID: itemID, folder: folder)
        precondition(session.notes.first?.comment == "启动批语", "启动首选条目必须加载划线")
        precondition(session.annotations.first?.explanation == "启动批注", "启动首选条目必须加载批注")
        precondition(session.overview?.chapters.first?.title == "开场", "启动首选条目必须加载目录")
        session.ensureLoaded(itemID: itemID, folder: folder)
        precondition(session.notes.first?.comment == "启动批语", "同一条目再次确保加载不得清空")
    }

    @MainActor
    private static func checkSwitchThreeVideosIsolated() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let ids = [UUID(), UUID(), UUID()]
        let notes = [
            DigestNote(id: UUID(), time: 1, text: "视频甲", createdAt: Date(), comment: "甲批语"),
            DigestNote(id: UUID(), time: 2, text: "视频乙", createdAt: Date(), comment: "乙批语"),
            DigestNote(id: UUID(), time: 3, text: "视频丙", createdAt: Date(), comment: "丙批语")
        ]
        let annotations = [
            DigestAnnotation(id: UUID(), time: 1, text: "视频甲", explanation: "甲解释", createdAt: Date(), model: "m"),
            DigestAnnotation(id: UUID(), time: 2, text: "视频乙", explanation: "乙解释", createdAt: Date(), model: "m"),
            DigestAnnotation(id: UUID(), time: 3, text: "视频丙", explanation: "丙解释", createdAt: Date(), model: "m")
        ]
        for index in 0..<3 {
            try DigestNotesStore.save([notes[index]], itemID: ids[index], folder: folder)
            try DigestAnnotationsStore.save([annotations[index]], itemID: ids[index], folder: folder)
            try DigestOverviewStore.save(
                DigestOverviewRecord(
                    payload: DigestOverviewPayload(
                        chapters: [
                            DigestGeneratedChapter(
                                title: "第\(index + 1)章",
                                timestamp: "0:00",
                                timestampSeconds: 0,
                                summary: "属于视频\(index)"
                            )
                        ],
                        keyQuotes: [],
                        source: .generated,
                        durationSeconds: 60
                    ),
                    generatedAt: Date(),
                    model: "m"
                ),
                itemID: ids[index],
                folder: folder
            )
        }

        let session = DigestSession()
        session.apiKeyEnvironment = [:]
        session.load(itemID: ids[0], folder: folder)
        session.showsHighlightsOnly = true
        precondition(session.notes.first?.text == "视频甲")
        precondition(session.annotations.first?.explanation == "甲解释")
        precondition(session.overview?.chapters.first?.summary == "属于视频0")
        precondition(session.showsHighlightsOnly)

        session.load(itemID: ids[1], folder: folder)
        precondition(!session.showsHighlightsOnly, "换视频必须退出只看划线")
        precondition(session.notes.first?.text == "视频乙", "乙的划线不得被甲污染")
        precondition(session.annotations.first?.explanation == "乙解释")
        precondition(session.overview?.chapters.first?.title == "第2章")
        precondition(session.notes.first?.text != "视频甲")

        session.load(itemID: ids[2], folder: folder)
        precondition(session.notes.first?.comment == "丙批语")
        precondition(session.annotations.first?.explanation == "丙解释")
        precondition(session.overview?.chapters.first?.summary == "属于视频2")

        session.showsHighlightsOnly = true
        session.load(itemID: ids[0], folder: folder)
        precondition(!session.showsHighlightsOnly)
        precondition(session.notes.first?.text == "视频甲", "切回甲时痕迹必须还在")
        precondition(session.annotations.first?.explanation == "甲解释")
    }

    @MainActor
    private static func checkMissingKeyHints() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-nokey-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = DigestSession()
        session.apiKeyDefaults = UserDefaults(suiteName: "digest-nokey-\(UUID().uuidString)")!
        session.apiKeyEnvironment = [:]
        session.load(itemID: UUID(), folder: folder)

        let cue = VideoSubtitleCue(startTime: 1, endTime: 2, text: "Hello world.\n大家好。")
        session.explainCue(index: 0, title: "Demo", cues: [cue])
        precondition(!session.isExplaining, "无密钥不得进入解释进行中")
        precondition(
            session.explainMessage(for: 0) == DigestCopy.missingKeyHint,
            "解释无密钥必须给出引导。实际：\(session.explainMessage(for: 0) ?? "nil")"
        )

        session.generateOverview(title: "Demo", author: "A", duration: 10, cues: [cue], chapters: [])
        precondition(!session.isGeneratingOverview)
        precondition(
            session.overviewMessage == DigestCopy.missingKeyHint,
            "生成目录无密钥必须给出引导。实际：\(session.overviewMessage ?? "nil")"
        )
    }

    @MainActor
    private static func checkAnnotationDeferredDelete() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-ann-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let cue = VideoSubtitleCue(startTime: 6, endTime: 8, text: "Hello world.\n大家好。")
        let annotation = DigestAnnotation(
            id: UUID(),
            time: 6,
            text: cue.text,
            explanation: "这句是在打招呼。",
            createdAt: Date(),
            model: "m"
        )
        try DigestAnnotationsStore.save([annotation], itemID: itemID, folder: folder)
        let session = DigestSession()
        session.apiKeyEnvironment = [:]
        session.load(itemID: itemID, folder: folder)
        precondition(session.annotation(for: cue) != nil)
        session.deleteAnnotation(annotation.id)
        precondition(session.annotation(for: cue) == nil, "删除后短时应从画面消失")
        precondition(session.latestPendingDeletion == .annotation(annotation.id))
        session.undoDeleteAnnotation(annotation.id)
        precondition(session.annotation(for: cue) != nil, "撤回后批注须回来")
        precondition(DigestAnnotationsStore.load(itemID: itemID, folder: folder).count == 1, "撤回不得落盘删除")
    }

    @MainActor
    private static func checkSaveFailureReverts() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-save-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let session = DigestSession()
        session.apiKeyEnvironment = [:]
        session.load(itemID: itemID, folder: folder)
        let sidecar = DigestNotesStore.fileURL(itemID: itemID, in: folder)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let cue = VideoSubtitleCue(startTime: 1, endTime: 2, text: "Hello world.\n大家好。")
        _ = session.toggleHighlight(cue: cue)
        precondition(session.persistMessage == DigestCopy.saveFailed, "保存失败须提示")
        precondition(session.notes.isEmpty, "保存失败须回退内存")
    }

    @MainActor
    private static func checkCorruptLoadDoesNotOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let url = DigestNotesStore.fileURL(itemID: itemID, in: folder)
        try "not-json".write(to: url, atomically: true, encoding: .utf8)
        let session = DigestSession()
        session.apiKeyEnvironment = [:]
        session.load(itemID: itemID, folder: folder)
        precondition(session.persistMessage == DigestCopy.fileCorrupt)
        let after = try String(contentsOf: url, encoding: .utf8)
        precondition(after == "not-json", "损坏文件不得被覆盖")
    }

    @MainActor
    private static func checkCommentCancelKeepsOriginal() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-comment-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let session = DigestSession()
        session.apiKeyEnvironment = [:]
        session.load(itemID: itemID, folder: folder)
        let cue = VideoSubtitleCue(startTime: 6, endTime: 8, text: "Hello world.\n大家好。")
        _ = session.toggleHighlight(cue: cue)
        let id = session.notes[0].id
        precondition(session.editingCommentNoteID == id, "划线后须进入批语编辑")
        session.updateComment(noteID: id, comment: "留下")
        precondition(session.notes[0].comment == "留下")
        session.beginEditComment(noteID: id)
        precondition(session.commentDraft == "留下", "重新打开须带出原文")
        session.commentDraft = "改了又取消"
        session.cancelEditComment()
        precondition(session.editingCommentNoteID == nil, "取消后须退出编辑")
        precondition(session.notes[0].comment == "留下", "取消不得改批语")
        session.beginEditComment(noteID: id)
        session.commentDraft = "新稿"
        session.commitCommentDraft()
        precondition(session.notes[0].comment == "新稿", "回车语义须保存草稿")
        session.beginEditComment(noteID: id)
        session.updateComment(noteID: id, comment: "   ")
        precondition(session.notes[0].comment == nil, "空批语不得保存")
        precondition(session.editingCommentNoteID == nil)
    }

    @MainActor
    private static func checkExplainProgressVisibleWithDelay() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-delay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = DigestSession()
        let defaults = UserDefaults(suiteName: "digest-delay-\(UUID().uuidString)")!
        defaults.set("sk-test", forKey: WatchQAAPIKey.defaultsKey)
        session.apiKeyDefaults = defaults
        session.apiKeyEnvironment = [:]
        session.load(itemID: UUID(), folder: folder)

        session.completeFn = { _, _, _, _, _, _ in
            try await Task.sleep(nanoseconds: 250_000_000)
            return "attention 在这里指把注意力放在这句话上。"
        }

        let cue = VideoSubtitleCue(startTime: 1, endTime: 3, text: "Pay attention.\n请注意。")
        session.explainCue(index: 0, title: "Demo", cues: [cue])
        precondition(session.isExplaining, "慢网下解释开始后必须进入进行中")
        precondition(session.explainingCueIndex == 0)
        precondition(session.isExplainingCue(0))

        try await Task.sleep(nanoseconds: 80_000_000)
        precondition(session.isExplaining, "延迟未结束时进行中反馈必须仍在")

        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(!session.isExplaining, "结束后不得停在进行中")
        precondition(session.annotation(for: cue)?.explanation.contains("注意力") == true)
    }
}


