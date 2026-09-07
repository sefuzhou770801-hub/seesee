import Foundation

@main
struct DigestAnnotationsCheck {
    static func main() throws {
        checkFileNaming()
        try checkRoundTripFields()
        try checkLoadBySentenceAnchor()
        try checkUpsertReplacesSameSentence()
        try checkDeletePersistsAcrossReload()
        try checkCollapseIsSessionOnly()
        checkCorruptAndMissing()
        checkContinueAskVisibilityAndContext()
        print("digest_annotations_check=passed")
    }

    private static func checkFileNaming() {
        let id = UUID(uuidString: "9D0A346E-068C-41CE-B3FC-938A773AADC9")!
        let folder = URL(fileURLWithPath: "/tmp/replay-media", isDirectory: true)
        let url = DigestAnnotationsStore.fileURL(itemID: id, in: folder)
        precondition(
            url.lastPathComponent == "9D0A346E-068C-41CE-B3FC-938A773AADC9.annotations.json",
            "批注 sidecar 须为 {UUID}.annotations.json"
        )
        precondition(
            url.lastPathComponent.hasPrefix(id.uuidString + "."),
            "文件名须带 UUID. 前缀，删除视频时才能被前缀扫描清掉"
        )
    }

    private static func checkRoundTripFields() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let annotation = DigestAnnotation(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            time: 75.5,
            text: "Hello world.\n大家好。",
            explanation: "这句是在打招呼。",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-sonnet-5"
        )
        try DigestAnnotationsStore.save([annotation], itemID: itemID, folder: folder)

        let loaded = DigestAnnotationsStore.load(itemID: itemID, folder: folder)
        precondition(loaded.count == 1)
        precondition(loaded[0].id == annotation.id)
        precondition(loaded[0].time == 75.5)
        precondition(loaded[0].text == "Hello world.\n大家好。")
        precondition(loaded[0].explanation == "这句是在打招呼。")
        precondition(loaded[0].createdAt.timeIntervalSince1970 == 1_700_000_000)
        precondition(loaded[0].model == "claude-sonnet-5")

        let data = try Data(contentsOf: DigestAnnotationsStore.fileURL(itemID: itemID, in: folder))
        let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        precondition(objects?.count == 1, "sidecar 须是对象数组")
        let object = objects?[0] ?? [:]
        precondition(object["id"] as? String == annotation.id.uuidString)
        precondition((object["time"] as? NSNumber)?.doubleValue == 75.5)
        precondition(object["text"] as? String == annotation.text)
        precondition(object["explanation"] as? String == annotation.explanation)
        precondition(object["model"] as? String == "claude-sonnet-5")
        precondition(object["createdAt"] as? String == "2023-11-14T22:13:20Z")
        precondition(object["collapsed"] == nil, "收起不得写入 sidecar")
    }

    private static func checkLoadBySentenceAnchor() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let hello = DigestAnnotation(
            id: UUID(),
            time: 6.0,
            text: "Hello world.\n大家好。",
            explanation: "打招呼",
            createdAt: Date(timeIntervalSince1970: 100),
            model: "claude-sonnet-5"
        )
        let later = DigestAnnotation(
            id: UUID(),
            time: 12.0,
            text: "Next sentence.\n下一句。",
            explanation: "接着说",
            createdAt: Date(timeIntervalSince1970: 200),
            model: "claude-sonnet-5"
        )
        try DigestAnnotationsStore.save([hello, later], itemID: itemID, folder: folder)
        let loaded = DigestAnnotationsStore.load(itemID: itemID, folder: folder)

        let hit = DigestAnnotationAnchor.matching(
            time: 6.004,
            text: "Hello world.\n大家好。",
            in: loaded
        )
        precondition(hit?.id == hello.id, "须按句起始时间码加原文命中")
        precondition(
            DigestAnnotationAnchor.matching(
                time: 6.0,
                text: "Next sentence.\n下一句。",
                in: loaded
            ) == nil,
            "时间相同但原文不同不得命中"
        )
        precondition(
            DigestAnnotationAnchor.matching(
                time: 12.5,
                text: "Hello world.\n大家好。",
                in: loaded
            ) == nil,
            "原文相同但时间差过大不得命中"
        )
    }

    private static func checkUpsertReplacesSameSentence() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let first = DigestAnnotation(
            id: UUID(),
            time: 6.0,
            text: "Hello world.\n大家好。",
            explanation: "第一版",
            createdAt: Date(timeIntervalSince1970: 100),
            model: "claude-sonnet-5"
        )
        let second = DigestAnnotation(
            id: UUID(),
            time: 6.002,
            text: "Hello world.\n大家好。",
            explanation: "第二版，写得更清楚。",
            createdAt: Date(timeIntervalSince1970: 200),
            model: "gemini-3.7-flash"
        )
        let other = DigestAnnotation(
            id: UUID(),
            time: 20.0,
            text: "Another cue.\n另一句。",
            explanation: "别的句子",
            createdAt: Date(timeIntervalSince1970: 150),
            model: "claude-sonnet-5"
        )

        let replaced = DigestAnnotationUpsert.applying(second, to: [first, other])
        precondition(replaced.count == 2, "同一句不得产生第二条批注")
        let kept = DigestAnnotationAnchor.matching(
            time: 6.0,
            text: "Hello world.\n大家好。",
            in: replaced
        )
        precondition(kept?.explanation == "第二版，写得更清楚。")
        precondition(kept?.model == "gemini-3.7-flash")
        precondition(
            DigestAnnotationAnchor.matching(
                time: 20.0,
                text: "Another cue.\n另一句。",
                in: replaced
            )?.explanation == "别的句子",
            "其他句的批注须保留"
        )

        try DigestAnnotationsStore.save(replaced, itemID: itemID, folder: folder)
        let loaded = DigestAnnotationsStore.load(itemID: itemID, folder: folder)
        precondition(loaded.count == 2, "落盘后同一句仍只有一条")
        precondition(
            DigestAnnotationAnchor.matching(
                time: 6.0,
                text: "Hello world.\n大家好。",
                in: loaded
            )?.explanation == "第二版，写得更清楚。"
        )
    }

    private static func checkDeletePersistsAcrossReload() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let keep = DigestAnnotation(
            id: UUID(),
            time: 4.0,
            text: "Keep me.\n留下。",
            explanation: "还要",
            createdAt: Date(timeIntervalSince1970: 10),
            model: "claude-sonnet-5"
        )
        let gone = DigestAnnotation(
            id: UUID(),
            time: 8.0,
            text: "Delete me.\n删掉。",
            explanation: "不要了",
            createdAt: Date(timeIntervalSince1970: 20),
            model: "claude-sonnet-5"
        )
        try DigestAnnotationsStore.save([keep, gone], itemID: itemID, folder: folder)
        let remaining = DigestAnnotationsStore.load(itemID: itemID, folder: folder)
            .filter { $0.id != gone.id }
        try DigestAnnotationsStore.save(remaining, itemID: itemID, folder: folder)

        let reloaded = DigestAnnotationsStore.load(itemID: itemID, folder: folder)
        precondition(reloaded.count == 1)
        precondition(reloaded[0].id == keep.id, "删除后重启只剩未删的批注")
        precondition(
            DigestAnnotationAnchor.matching(
                time: 8.0,
                text: "Delete me.\n删掉。",
                in: reloaded
            ) == nil
        )
    }

    private static func checkCollapseIsSessionOnly() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let annotation = DigestAnnotation(
            id: UUID(),
            time: 6.0,
            text: "Hello world.\n大家好。",
            explanation: "打招呼",
            createdAt: Date(timeIntervalSince1970: 100),
            model: "claude-sonnet-5"
        )
        try DigestAnnotationsStore.save([annotation], itemID: itemID, folder: folder)

        var collapsed: Set<UUID> = []
        collapsed = DigestAnnotationCollapse.toggling(annotation.id, in: collapsed)
        precondition(DigestAnnotationCollapse.isCollapsed(annotation.id, in: collapsed))
        collapsed = DigestAnnotationCollapse.toggling(annotation.id, in: collapsed)
        precondition(!DigestAnnotationCollapse.isCollapsed(annotation.id, in: collapsed))
        collapsed = DigestAnnotationCollapse.toggling(annotation.id, in: collapsed)
        precondition(DigestAnnotationCollapse.isCollapsed(annotation.id, in: collapsed))

        let data = try Data(contentsOf: DigestAnnotationsStore.fileURL(itemID: itemID, in: folder))
        let json = String(data: data, encoding: .utf8) ?? ""
        precondition(!json.contains("collapsed"), "收起状态不得出现在 sidecar 文本里")

        let reloaded = DigestAnnotationsStore.load(itemID: itemID, folder: folder)
        precondition(
            DigestAnnotationCollapse.isCollapsed(reloaded[0].id, in: []) == false,
            "重新打开须视为展开，收起不跨会话"
        )
    }

    private static func checkCorruptAndMissing() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).annotations.json")
        precondition(DigestAnnotationsStore.read(from: missing) == .missing)
        precondition(DigestAnnotationsStore.load(from: missing).isEmpty, "文件不存在视为空")

        let folder = FileManager.default.temporaryDirectory
        let corrupt = folder.appendingPathComponent("digest-annotations-corrupt-\(UUID().uuidString).json")
        try? "not-json".write(to: corrupt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        precondition(DigestAnnotationsStore.read(from: corrupt) == .corrupt, "损坏文件必须标为 corrupt")
        let before = try? String(contentsOf: corrupt, encoding: .utf8)
        _ = DigestAnnotationsStore.load(from: corrupt)
        let after = try? String(contentsOf: corrupt, encoding: .utf8)
        precondition(before == after, "读取损坏文件不得覆盖原件")

        let empty = folder.appendingPathComponent("digest-annotations-empty-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: empty.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: empty) }
        precondition(DigestAnnotationsStore.load(from: empty).isEmpty, "空文件视为空")
    }

    private static func checkContinueAskVisibilityAndContext() {
        precondition(DigestContinueAsk.title == "继续问")
        precondition(DigestContinueAsk.isVisible(watchQAEnabled: false) == false)
        precondition(DigestContinueAsk.isVisible(watchQAEnabled: true) == true)

        let question = DigestContinueAsk.question(
            sourceText: "Hello world.\n大家好。",
            explanation: "这句是在打招呼。"
        )
        precondition(question.contains("Hello world.\n大家好。"), "继续问须带上来源句")
        precondition(question.contains("这句是在打招呼。"), "继续问须带上解释")
        precondition(question.contains("来源句"), "继续问上下文须标明来源句")
        precondition(question.contains("解释"), "继续问上下文须标明解释")
        precondition(question.contains("我想继续问："), "继续问须留出追问位置")
    }

    private static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-annotations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
