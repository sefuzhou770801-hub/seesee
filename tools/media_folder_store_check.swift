import Foundation

/// 真实 `QueueStore(dataFile:mediaFolder:)` 装配：未连接不建目录、不启动下载、搬移后目录跟着变。
@main
struct MediaFolderStoreCheck {
    static func main() async throws {
        try await checkDisconnectedDoesNotCreateFolderOrStartDownload()
        try await checkRealVolumesPathStaysAbsent()
        try await checkMoveUpdatesStoreMediaFolder()
        print("media_folder_store_check=passed")
    }

    /// 可写的假卷根：旧代码会在这里建目录，这条检查必须失败。
    private static func checkDisconnectedDoesNotCreateFolderOrStartDownload() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let fakeVolumes = env.root.appendingPathComponent("Volumes", isDirectory: true)
        let missing = fakeVolumes.appendingPathComponent("不存在的卷/seesee", isDirectory: true)
        precondition(!FileManager.default.fileExists(atPath: missing.path))

        let id = UUID()
        try writeQueue(
            [
                queuedItem(id: id)
            ],
            to: env.dataFile
        )

        let store = await MainActor.run {
            QueueStore(
                dataFile: env.dataFile,
                mediaFolder: missing,
                defaults: env.defaults,
                mountedVolumeURLs: [URL(fileURLWithPath: "/")],
                volumesRoot: fakeVolumes
            )
        }

        await MainActor.run {
            precondition(store.isMediaFolderDisconnected, "注入空挂载列表后必须判定未连接")
            precondition(
                !FileManager.default.fileExists(atPath: missing.path),
                "未连接时不得创建片库目录"
            )
            precondition(
                !FileManager.default.fileExists(atPath: fakeVolumes.appendingPathComponent("不存在的卷").path),
                "未连接时不得在卷根留下同名空目录"
            )
            store.startDownload(for: id)
            precondition(store.items.first?.state == .queued, "未连接时不得进入下载")
            precondition(
                store.items.first?.progressLabel == MediaFolderCopy.disconnected,
                "排队状态应写成存放位置未连接"
            )
            precondition(
                !FileManager.default.fileExists(atPath: missing.path),
                "下载入口不得为了落盘而创建目录"
            )
        }
    }

    /// 任务书指定路径：`/Volumes/不存在的卷/seesee` 判未连接，且构造后该路径不存在。
    private static func checkRealVolumesPathStaysAbsent() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let missing = URL(fileURLWithPath: "/Volumes/不存在的卷/seesee", isDirectory: true)
        precondition(
            MediaFolderAvailability.isDisconnected(
                missing,
                mountedVolumes: [URL(fileURLWithPath: "/")]
            )
        )
        let store = await MainActor.run {
            QueueStore(
                dataFile: env.dataFile,
                mediaFolder: missing,
                defaults: env.defaults,
                mountedVolumeURLs: [URL(fileURLWithPath: "/")]
            )
        }
        await MainActor.run {
            precondition(store.isMediaFolderDisconnected)
            precondition(!FileManager.default.fileExists(atPath: missing.path))
            precondition(!FileManager.default.fileExists(atPath: "/Volumes/不存在的卷"))
        }
    }

    private static func checkMoveUpdatesStoreMediaFolder() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let id = UUID()
        let video = env.mediaFolder.appendingPathComponent("\(id.uuidString).mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        let item = WatchItem(
            id: id,
            urlString: "https://example.com/moved",
            title: "moved",
            author: "check",
            duration: 8,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            watchedAt: nil,
            state: .ready,
            progress: 1,
            progressLabel: "已下载",
            localFilePath: video.path,
            errorMessage: nil,
            playbackPosition: nil,
            chapters: nil,
            thumbnailFilePath: nil,
            subtitleFilePath: nil
        )
        try writeQueue([item], to: env.dataFile)

        let store = await MainActor.run {
            QueueStore(dataFile: env.dataFile, mediaFolder: env.mediaFolder, defaults: env.defaults)
        }
        let dest = env.root.appendingPathComponent("new-library", isDirectory: true)
        let result = await MainActor.run {
            store.moveMediaFolder(to: dest)
        }
        await MainActor.run {
            precondition(result == .success, "真实 QueueStore 搬移应当成功，实际 \(result)")
            precondition(
                store.mediaFolder.standardizedFileURL.path == dest.standardizedFileURL.path,
                "搬移后 store.mediaFolder 必须跟着变，视图只能读这个值"
            )
            precondition(store.items.first?.localFilePath == dest.appendingPathComponent("\(id.uuidString).mp4").path)
            precondition(!FileManager.default.fileExists(atPath: video.path))
            precondition(FileManager.default.fileExists(atPath: dest.appendingPathComponent("\(id.uuidString).mp4").path))
        }
    }

    private struct Env {
        let root: URL
        let mediaFolder: URL
        let dataFile: URL
        let defaults: UserDefaults
        let suite: String
    }

    private static func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-store-\(UUID().uuidString)", isDirectory: true)
        let mediaFolder = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        let suite = "media-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Env(
            root: root,
            mediaFolder: mediaFolder,
            dataFile: root.appendingPathComponent("queue.json"),
            defaults: defaults,
            suite: suite
        )
    }

    private static func writeQueue(_ items: [WatchItem], to dataFile: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: dataFile)
    }

    private static func queuedItem(id: UUID) -> WatchItem {
        WatchItem(
            id: id,
            urlString: "https://example.com/waiting",
            title: "waiting",
            author: "check",
            duration: nil,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            watchedAt: nil,
            state: .queued,
            progress: 0,
            progressLabel: "排队中",
            localFilePath: nil,
            errorMessage: nil,
            playbackPosition: nil,
            chapters: nil,
            thumbnailFilePath: nil,
            subtitleFilePath: nil
        )
    }
}
