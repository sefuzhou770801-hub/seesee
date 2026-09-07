import Foundation

struct WatchQAEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var time: Double
    var question: String
    var answer: String
    var askedAt: Date
    var model: String
}

/// 一段视频问答 sidecar 的定位：itemID 与媒体目录，文件路径由二者推出。
/// 追加、覆盖、删除、落盘四个写入入口都以它为参数，避免 (itemID, folder) 到处成对散落。
struct WatchQASidecar: Equatable {
    let itemID: UUID
    let folder: URL

    var url: URL { WatchQAStore.fileURL(itemID: itemID, in: folder) }
}

/// 落盘结局，交回界面决定后续动作。
enum WatchQAPersistOutcome: Equatable {
    case persisted // 写成功，界面可插卡
    case dropped   // 视频已删除，静默丢弃，不插卡不提示
    case failed    // 写失败，提示「回答没有存上」，显示保留
}

/// 一条回答本身是否够格落盘的纯判断，独立出来便于测试竞态口径。
/// （有没有落盘目标由调用点解包 sidecar 决定，不掺进这里。）
enum WatchQAPersistDecision {
    /// 仅当收到完成事件、且答案非空时才落盘。
    /// 关闭浮层导致回答未完成（completed == false）时一律不落盘。
    static func shouldPersist(completed: Bool, answer: String) -> Bool {
        guard completed else { return false }
        return !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// sidecar 留存的串行收口。
///
/// 所有写盘（追加、覆盖、删除）都经这一个 actor 实例串行执行，读改写不可分割：
/// 并发追加不会互相覆盖，删除与在途追加不会竞争复活文件。
/// 读取（load）是容错纯函数，与原子写并发安全，不必进 actor。
actor WatchQAStore {
    static let shared = WatchQAStore()
    static let sidecarSuffix = "qa.json"

    /// 本进程内已删除的视频 itemID。打标记后到达的追加直接丢弃，
    /// 保证删除后不再被在途的后台追加复活出孤儿 qa.json。itemID 是每次入队新生成的 UUID，不复用。
    private var removedItems: Set<UUID> = []

    // MARK: - 纯路径与读取（无需串行）

    nonisolated static func fileURL(itemID: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent("\(itemID.uuidString).\(sidecarSuffix)")
    }

    /// 容错读取：文件缺失、空、空白、坏 JSON、非数组一律按空返回，不抛错。
    /// 原子写保证读到的要么是旧的完整文件、要么是新的完整文件，可与写入并发。
    nonisolated static func load(from url: URL) -> [WatchQAEntry] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchQAEntry].self, from: data)) ?? []
    }

    // MARK: - 串行写入入口（actor 隔离）

    /// 读改写不可分割：载入现有、追加一条、原子写回。写失败上抛，调用方据此决定是否提示。
    /// 视频已被标记删除时直接丢弃并返回 false，不复活文件、不算失败。
    @discardableResult
    func append(_ entry: WatchQAEntry, to sidecar: WatchQASidecar) throws -> Bool {
        guard !removedItems.contains(sidecar.itemID) else { return false }
        var entries = Self.load(from: sidecar.url)
        entries.append(entry)
        try Self.write(entries, to: sidecar.url)
        return true
    }

    /// 覆盖写整份记录，写失败上抛。视频已删除时丢弃。
    func save(_ entries: [WatchQAEntry], to sidecar: WatchQASidecar) throws {
        guard !removedItems.contains(sidecar.itemID) else { return }
        try Self.write(entries, to: sidecar.url)
    }

    /// 删除协调：先打进程内删除标记（此后追加一律丢弃），再删 sidecar 文件。
    /// 与追加走同一串行执行器，保证在途追加不会复活文件；调用方另有同步前缀扫描负责即时清理。
    func deleteSidecar(_ sidecar: WatchQASidecar) {
        removedItems.insert(sidecar.itemID)
        try? FileManager.default.removeItem(at: sidecar.url)
    }

    /// 流式回答完成后的落盘编排，返回结局供界面决定插卡 / 提示 / 丢弃。
    func persist(_ entry: WatchQAEntry, to sidecar: WatchQASidecar) -> WatchQAPersistOutcome {
        do {
            let stored = try append(entry, to: sidecar)
            return stored ? .persisted : .dropped
        } catch {
            return .failed
        }
    }

    /// 原子写原语，写失败上抛。仅 actor 内部调用，故写与写不会并发。
    private nonisolated static func write(_ entries: [WatchQAEntry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }
}

enum WatchQATimeline {
    struct Insertions: Equatable {
        var leading: [WatchQAEntry]
        var after: [[WatchQAEntry]]
    }

    static func insertions(cues: [VideoSubtitleCue], entries: [WatchQAEntry]) -> Insertions {
        let sorted = entries
            .filter { $0.time.isFinite }
            .sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time < rhs.time }
                if lhs.askedAt != rhs.askedAt { return lhs.askedAt < rhs.askedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        guard !cues.isEmpty else {
            return Insertions(leading: sorted, after: [])
        }

        var leading: [WatchQAEntry] = []
        var after = Array(repeating: [WatchQAEntry](), count: cues.count)
        var cueIndex = 0
        for entry in sorted {
            while cueIndex + 1 < cues.count, cues[cueIndex + 1].startTime <= entry.time {
                cueIndex += 1
            }
            if cues[cueIndex].startTime <= entry.time {
                after[cueIndex].append(entry)
            } else {
                leading.append(entry)
            }
        }
        return Insertions(leading: leading, after: after)
    }
}
