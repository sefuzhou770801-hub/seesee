import Foundation

@main
struct QAStoreCheck {
    static func main() async throws {
        checkFileNaming()
        try await checkRoundTrip()
        try await checkAppendOrder()
        try await checkMissingEmptyAndCorrupt()
        checkTimelineInsert()
        try await checkConcurrentAppendKeepsAll()
        await checkWriteFailurePropagates()
        try await checkDeleteMarkDiscardsAppend()
        try await checkDeleteRaceInterleaving()
        await checkPersistOutcomes()
        checkShouldPersist()
        print("qa_store_check=passed")
    }

    private static func checkFileNaming() {
        let id = UUID(uuidString: "9D0A346E-068C-41CE-B3FC-938A773AADC9")!
        let folder = URL(fileURLWithPath: "/tmp/replay-media", isDirectory: true)
        let url = WatchQAStore.fileURL(itemID: id, in: folder)
        precondition(
            url.lastPathComponent == "9D0A346E-068C-41CE-B3FC-938A773AADC9.qa.json",
            "sidecar 须为 {UUID}.qa.json，与 {UUID}.zh.srt 同一前缀规则"
        )
        precondition(
            url.lastPathComponent.hasPrefix(id.uuidString + "."),
            "文件名须带 UUID. 前缀，删除本地文件时才能被现有前缀扫描清掉"
        )
        // WatchQASidecar.url 须与静态 fileURL 一致
        precondition(WatchQASidecar(itemID: id, folder: folder).url == url)
    }

    private static func checkRoundTrip() async throws {
        let store = WatchQAStore()
        let sidecar = scratch()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }

        let entry = WatchQAEntry(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            time: 75.5,
            question: "画面里是什么",
            answer: "大象站在栅栏后面。\n字幕里说 we are in front of the elephants。",
            askedAt: Date(timeIntervalSince1970: 1_700_000_000),
            model: "claude-sonnet-5"
        )
        try await store.save([entry], to: sidecar)

        let loaded = WatchQAStore.load(from: sidecar.url)
        precondition(loaded.count == 1)
        precondition(loaded[0].id == entry.id)
        precondition(loaded[0].time == 75.5)
        precondition(loaded[0].question == "画面里是什么")
        precondition(loaded[0].answer == entry.answer)
        precondition(loaded[0].askedAt.timeIntervalSince1970 == 1_700_000_000)
        precondition(loaded[0].model == "claude-sonnet-5")

        let data = try Data(contentsOf: sidecar.url)
        let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        precondition(objects?.count == 1, "sidecar 须是对象数组")
        let object = objects?[0] ?? [:]
        precondition(object["id"] as? String == entry.id.uuidString)
        precondition((object["time"] as? NSNumber)?.doubleValue == 75.5)
        precondition(object["question"] as? String == "画面里是什么")
        precondition(object["answer"] as? String == entry.answer)
        precondition(object["model"] as? String == "claude-sonnet-5")
        precondition(object["askedAt"] as? String == "2023-11-14T22:13:20Z")
    }

    private static func checkAppendOrder() async throws {
        let store = WatchQAStore()
        let sidecar = scratch()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }

        let first = WatchQAEntry(
            id: UUID(),
            time: 40,
            question: "先问",
            answer: "先答",
            askedAt: Date(timeIntervalSince1970: 100),
            model: "claude-sonnet-5"
        )
        let second = WatchQAEntry(
            id: UUID(),
            time: 10,
            question: "后问",
            answer: "后答",
            askedAt: Date(timeIntervalSince1970: 200),
            model: "claude-sonnet-5"
        )
        try await store.append(first, to: sidecar)
        try await store.append(second, to: sidecar)
        let loaded = WatchQAStore.load(from: sidecar.url)
        precondition(loaded.map(\.question) == ["先问", "后问"], "磁盘按追加顺序，不按时间重排")
        precondition(loaded.map(\.id) == [first.id, second.id])
    }

    private static func checkMissingEmptyAndCorrupt() async throws {
        let missing = scratchURL()
        precondition(
            WatchQAStore.load(from: missing).isEmpty,
            "文件不存在视为空"
        )

        let empty = scratchURL()
        defer { try? FileManager.default.removeItem(at: empty) }
        FileManager.default.createFile(atPath: empty.path, contents: Data(), attributes: nil)
        precondition(WatchQAStore.load(from: empty).isEmpty, "空文件视为空")

        let blank = scratchURL()
        defer { try? FileManager.default.removeItem(at: blank) }
        try? Data("   \n".utf8).write(to: blank)
        precondition(WatchQAStore.load(from: blank).isEmpty, "空白文件视为空")

        let emptyArray = scratchURL()
        defer { try? FileManager.default.removeItem(at: emptyArray) }
        try? Data("[]".utf8).write(to: emptyArray)
        precondition(WatchQAStore.load(from: emptyArray).isEmpty, "空数组是合法的空问答")

        let corrupt = scratchURL()
        defer { try? FileManager.default.removeItem(at: corrupt) }
        try? Data("{not json".utf8).write(to: corrupt)
        precondition(WatchQAStore.load(from: corrupt).isEmpty, "损坏文件视为空，不得抛错")

        let notArray = scratchURL()
        defer { try? FileManager.default.removeItem(at: notArray) }
        try? Data(#"{"question":"x"}"#.utf8).write(to: notArray)
        precondition(WatchQAStore.load(from: notArray).isEmpty, "非数组视为损坏")

        // 损坏文件上追加须写成合法数组，不得把坏内容留下。
        let store = WatchQAStore()
        let recover = scratch()
        defer { try? FileManager.default.removeItem(at: recover.url) }
        try? Data("{not json".utf8).write(to: recover.url)
        try await store.append(
            WatchQAEntry(
                id: UUID(),
                time: 1,
                question: "恢复",
                answer: "新答",
                askedAt: Date(timeIntervalSince1970: 1),
                model: "claude-sonnet-5"
            ),
            to: recover
        )
        precondition(
            WatchQAStore.load(from: recover.url).map(\.question) == ["恢复"],
            "损坏文件上追加须写成合法数组，不得把坏内容留下"
        )
    }

    /// 复现脚本 replay-qa-concurrency-check：并发追加 100 条。
    /// 串行 actor 收口后必须全保留（此前实测只剩个位数）。
    private static func checkConcurrentAppendKeepsAll() async throws {
        for round in 1...5 {
            let store = WatchQAStore()
            let sidecar = scratch()
            defer { try? FileManager.default.removeItem(at: sidecar.url) }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask {
                        let entry = WatchQAEntry(
                            id: UUID(),
                            time: Double(i),
                            question: "q\(i)",
                            answer: "a",
                            askedAt: Date(timeIntervalSince1970: Double(i)),
                            model: "m"
                        )
                        _ = try await store.append(entry, to: sidecar)
                    }
                }
                try await group.waitForAll()
            }
            let count = WatchQAStore.load(from: sidecar.url).count
            precondition(count == 100, "第 \(round) 轮并发追加须全保留，实际 \(count)")
        }
    }

    /// 复现脚本 replay-qa-write-failure-check：sidecar 指向不存在的父目录。
    /// 写入必须上抛，调用方拿到失败结局（.failed），不得静默当成功。
    private static func checkWriteFailurePropagates() async {
        let store = WatchQAStore()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-missing-parent-\(UUID().uuidString)", isDirectory: true)
        let sidecar = WatchQASidecar(itemID: UUID(), folder: folder)
        let entry = WatchQAEntry(
            id: UUID(), time: 1, question: "q", answer: "a",
            askedAt: Date(timeIntervalSince1970: 1), model: "m"
        )

        var threw = false
        do {
            _ = try await store.append(entry, to: sidecar)
        } catch {
            threw = true
        }
        precondition(threw, "写入不存在的父目录必须抛错，不得吞掉")
        precondition(!FileManager.default.fileExists(atPath: sidecar.url.path), "写失败不得留下文件")
        precondition(WatchQAStore.load(from: sidecar.url).isEmpty)

        let outcome = await store.persist(entry, to: sidecar)
        precondition(outcome == .failed, "写失败落盘结局须为 .failed，界面据此不插卡")
    }

    /// 复现脚本 replay-qa-delete-race-check：删除后在途追加不得复活文件。
    /// 串行 actor 打删除标记后，后续追加一律丢弃，qa.json 不再出现。
    private static func checkDeleteMarkDiscardsAppend() async throws {
        let store = WatchQAStore()
        let sidecar = scratch()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }
        let entry = WatchQAEntry(
            id: UUID(), time: 1, question: "q", answer: "a",
            askedAt: Date(timeIntervalSince1970: 1), model: "m"
        )

        let first = try await store.append(entry, to: sidecar)
        precondition(first, "首次追加应写成功")
        precondition(FileManager.default.fileExists(atPath: sidecar.url.path))

        await store.deleteSidecar(sidecar)
        precondition(!FileManager.default.fileExists(atPath: sidecar.url.path), "删除后 qa.json 应消失")

        let second = try await store.append(entry, to: sidecar)
        precondition(second == false, "打删除标记后追加须被丢弃并返回 false")
        precondition(
            !FileManager.default.fileExists(atPath: sidecar.url.path),
            "被丢弃的追加不得复活出孤儿 qa.json"
        )
        precondition(WatchQAStore.load(from: sidecar.url).isEmpty)

        let outcome = await store.persist(entry, to: sidecar)
        precondition(outcome == .dropped, "删除后 persist 结局须为 .dropped，静默丢弃")
    }

    /// 复现 `QueueStore.remove` 的删除时序（无法直接编译 QueueStore，故按其确定序列驱动真实 actor）：
    /// 未等待的 `Task { deleteSidecar }` + 同步前缀扫描 `removeItem`，与在途 `persist` 交错。
    /// 无论交错如何，删除标记保证这是该 itemID 最后一次动盘，收敛后不残留、不复活 qa.json。
    private static func checkDeleteRaceInterleaving() async throws {
        for _ in 0..<100 {
            let store = WatchQAStore()
            let sidecar = scratch()
            let folder = sidecar.folder
            let itemID = sidecar.itemID
            let seed = WatchQAEntry(
                id: UUID(), time: 1, question: "看过", answer: "旧答",
                askedAt: Date(timeIntervalSince1970: 1), model: "m"
            )
            _ = try await store.append(seed, to: sidecar)

            let inflight = WatchQAEntry(
                id: UUID(), time: 2, question: "刚问完", answer: "在途答",
                askedAt: Date(timeIntervalSince1970: 2), model: "m"
            )
            // 在途落盘（模拟流式完成的后台 persist）与删除并发。
            async let persisted = store.persist(inflight, to: sidecar)
            let deleteTask = Task { await store.deleteSidecar(sidecar) }
            // 复刻 QueueStore.remove 的同步前缀扫描（含 qa.json），与 actor 幂等重复删除。
            prefixScanDelete(itemID: itemID, in: folder)

            _ = await persisted
            await deleteTask.value

            precondition(
                !FileManager.default.fileExists(atPath: sidecar.url.path),
                "删除与在途落盘交错后，qa.json 不得残留或被复活"
            )
            precondition(WatchQAStore.load(from: sidecar.url).isEmpty)
        }
    }

    /// 与 `QueueStore.remove` 同款前缀扫描：删除媒体目录下全部 `<uuid>.*`（含 qa.json）。
    private static func prefixScanDelete(itemID: UUID, in folder: URL) {
        let prefix = itemID.uuidString + "."
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func checkPersistOutcomes() async {
        let store = WatchQAStore()
        let sidecar = scratch()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }
        let entry = WatchQAEntry(
            id: UUID(), time: 2, question: "问", answer: "答",
            askedAt: Date(timeIntervalSince1970: 2), model: "m"
        )
        let outcome = await store.persist(entry, to: sidecar)
        precondition(outcome == .persisted, "正常落盘结局须为 .persisted")
        precondition(WatchQAStore.load(from: sidecar.url).count == 1, "成功落盘应写入一条")
    }

    private static func checkShouldPersist() {
        precondition(
            WatchQAPersistDecision.shouldPersist(completed: true, answer: "答"),
            "完成、有答案 → 落盘"
        )
        precondition(
            !WatchQAPersistDecision.shouldPersist(completed: false, answer: "答"),
            "未收到完成事件（浮层提前关闭 / 流被截断）→ 不落盘"
        )
        precondition(
            !WatchQAPersistDecision.shouldPersist(completed: true, answer: "   \n"),
            "空白答案 → 不落盘"
        )
    }

    private static func checkTimelineInsert() {
        let cues = [
            VideoSubtitleCue(startTime: 10, endTime: 18, text: "开场"),
            VideoSubtitleCue(startTime: 18, endTime: 25, text: "大象"),
            VideoSubtitleCue(startTime: 40, endTime: 50, text: "结尾")
        ]
        let before = entry(id: 1, time: 3, question: "片头前")
        let duringFirst = entry(id: 2, time: 12, question: "开场中")
        let atSecondStart = entry(id: 3, time: 18, question: "第二句起点")
        let inGap = entry(id: 4, time: 30, question: "句间空隙")
        let afterLast = entry(id: 5, time: 80, question: "片尾后")
        let sameSlotLater = entry(id: 6, time: 12.5, question: "开场中稍后")
        let nanTime = entry(id: 7, time: .nan, question: "无效时间")

        let insertions = WatchQATimeline.insertions(
            cues: cues,
            entries: [afterLast, inGap, nanTime, before, sameSlotLater, duringFirst, atSecondStart]
        )
        precondition(
            insertions.leading.map(\.question) == ["片头前"],
            "早于第一句的问答排在字幕流最前"
        )
        precondition(insertions.after.count == cues.count)
        precondition(
            insertions.after[0].map(\.question) == ["开场中", "开场中稍后"],
            "问答插在对应句块之后，同一句内按时间排"
        )
        precondition(
            insertions.after[1].map(\.question) == ["第二句起点", "句间空隙"],
            "句间空隙跟在上一句后面，排在下一句之前"
        )
        precondition(
            insertions.after[2].map(\.question) == ["片尾后"],
            "晚于最后一句的问答跟在末句后面"
        )
        precondition(
            !insertions.leading.contains(where: { $0.question == "无效时间" })
                && insertions.after.allSatisfy { $0.allSatisfy { $0.question != "无效时间" } },
            "无效时间不得进入时间轴"
        )

        let emptyCues = WatchQATimeline.insertions(
            cues: [],
            entries: [inGap, before]
        )
        precondition(
            emptyCues.leading.map(\.question) == ["片头前", "句间空隙"],
            "无字幕时问答仍按时间出现"
        )
        precondition(emptyCues.after.isEmpty)

        let emptyAll = WatchQATimeline.insertions(cues: [], entries: [])
        precondition(emptyAll.leading.isEmpty)
        precondition(emptyAll.after.isEmpty)
    }

    private static func entry(id: Int, time: Double, question: String) -> WatchQAEntry {
        WatchQAEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", id))")!,
            time: time,
            question: question,
            answer: "答",
            askedAt: Date(timeIntervalSince1970: Double(id)),
            model: "claude-sonnet-5"
        )
    }

    /// actor 写入用：随机 itemID + 临时目录的 sidecar 定位。
    private static func scratch() -> WatchQASidecar {
        WatchQASidecar(itemID: UUID(), folder: FileManager.default.temporaryDirectory)
    }

    /// 纯 load 容错用：任意路径，可写入任意字节。
    private static func scratchURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-store-\(UUID().uuidString).qa.json")
    }
}
