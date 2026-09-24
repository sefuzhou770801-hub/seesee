import Combine
import Foundation

/// 真实 `QueueStore(dataFile:mediaFolder:)` 装配：未连接不建目录、不启动下载、搬移后目录跟着变。
@main
struct MediaFolderStoreCheck {
    static func main() async throws {
        try await checkDisconnectedDoesNotCreateFolderOrStartDownload()
        try await checkRealVolumesPathStaysAbsent()
        try await checkMoveUpdatesStoreMediaFolder()
        try await checkDisconnectedSourceMoveIsRejected()
        try await checkDisconnectedDestinationMoveDoesNotCreate()
        try await checkIncompleteMarkerRefusesNewMove()
        try await checkStaleCompletedMarkerIsClearedOnLaunch()
        try await checkInterruptG_LaunchDoesNotTreatAsComplete()
        try await checkPartialDeleteDoesNotClaimSourcesRemain()
        try await checkSettingsMirrorSeesFailureAfterChange()
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

    /// 审查 1：QueueStore 默认搬移器也拒绝未连接的源片库。
    private static func checkDisconnectedSourceMoveIsRejected() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let fakeVolumes = env.root.appendingPathComponent("Volumes", isDirectory: true)
        let missing = fakeVolumes.appendingPathComponent("不存在的卷/seesee", isDirectory: true)
        try writeQueue([], to: env.dataFile)
        let dest = env.root.appendingPathComponent("new-library", isDirectory: true)

        let store = await MainActor.run {
            QueueStore(
                dataFile: env.dataFile,
                mediaFolder: missing,
                defaults: env.defaults,
                mountedVolumeURLs: [URL(fileURLWithPath: "/")],
                volumesRoot: fakeVolumes
            )
        }
        let result = await MainActor.run {
            store.moveMediaFolder(to: dest)
        }
        await MainActor.run {
            precondition(result == .failure(MediaFolderCopy.sourceDisconnected), "未连接源必须拒绝，实际 \(result)")
            precondition(store.mediaFolderMoveMessage == MediaFolderCopy.failure(MediaFolderCopy.sourceDisconnected))
            let leftover = try! JSONDecoder().decode([WatchItem].self, from: Data(contentsOf: env.dataFile))
            precondition(leftover.isEmpty, "未连接时不得改写队列条目")
            precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
            precondition(!FileManager.default.fileExists(atPath: dest.path))
        }
    }

    /// 审查 4：QueueStore 默认搬移器对未挂载目标不得建目录。
    private static func checkDisconnectedDestinationMoveDoesNotCreate() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let fakeVolumes = env.root.appendingPathComponent("Volumes", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeVolumes, withIntermediateDirectories: true)
        let dest = fakeVolumes.appendingPathComponent("不存在的卷/seesee", isDirectory: true)
        try writeQueue([], to: env.dataFile)

        let store = await MainActor.run {
            QueueStore(
                dataFile: env.dataFile,
                mediaFolder: env.mediaFolder,
                defaults: env.defaults,
                mountedVolumeURLs: [URL(fileURLWithPath: "/")],
                volumesRoot: fakeVolumes
            )
        }
        let result = await MainActor.run {
            store.moveMediaFolder(to: dest)
        }
        await MainActor.run {
            precondition(
                result == .failure(MediaFolderCopy.destinationDisconnected),
                "目标未连接必须拒绝，实际 \(result)"
            )
            precondition(store.mediaFolderMoveMessage == MediaFolderCopy.failure(MediaFolderCopy.destinationDisconnected))
            precondition(!FileManager.default.fileExists(atPath: dest.path))
            precondition(!FileManager.default.fileExists(atPath: fakeVolumes.appendingPathComponent("不存在的卷").path))
        }
    }

    /// 审查 3：启动时发现进行中标记，拒绝新搬移并提示上次未完成。
    private static func checkIncompleteMarkerRefusesNewMove() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        try Data("from=/old\nto=/new\n".utf8).write(to: MediaFolderMoveMarker.url(beside: env.dataFile))
        let video = env.mediaFolder.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        try writeQueue([], to: env.dataFile)

        let store = await MainActor.run {
            QueueStore(dataFile: env.dataFile, mediaFolder: env.mediaFolder, defaults: env.defaults)
        }
        let expected = MediaFolderCopy.leftoverDestinationNeedsCleanup(
            URL(fileURLWithPath: "/new", isDirectory: true).standardizedFileURL.path
        )
        await MainActor.run {
            precondition(store.mediaFolderMoveMessage == expected, "启动时必须提示目标可能有残余、需要手动清理")
        }
        let dest = env.root.appendingPathComponent("new-library", isDirectory: true)
        let result = await MainActor.run {
            store.moveMediaFolder(to: dest)
        }
        await MainActor.run {
            precondition(result == .failure(expected), "有标记时拒绝新搬移，实际 \(result)")
            precondition(store.mediaFolderMoveMessage == expected)
            precondition(FileManager.default.fileExists(atPath: video.path))
            precondition(!FileManager.default.fileExists(atPath: dest.path))
        }
    }

    /// 审查第 3 轮-1：源已删完、队列和偏好都已切走，只剩标记时，启动应清掉标记。
    private static func checkStaleCompletedMarkerIsClearedOnLaunch() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let destination = env.root.appendingPathComponent("to", isDirectory: true)
        let library = try seedStoreLibrary(env)
        var mover = MediaLibraryMover(defaults: env.defaults)
        mover.interruptAfter = .afterSourcesDeleted
        _ = mover.move(
            from: env.mediaFolder,
            to: destination,
            dataFile: env.dataFile,
            items: library,
            hasActiveDownload: false
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .completedMarkerLeft)

        let store = await MainActor.run {
            QueueStore(
                dataFile: env.dataFile,
                mediaFolder: destination,
                defaults: env.defaults
            )
        }
        await MainActor.run {
            precondition(store.mediaFolderMoveMessage == nil, "已完成的过期标记不得提示未完成")
            if let message = store.mediaFolderMoveMessage {
                precondition(!message.contains(MediaFolderCopy.needsManualCleanup), "不得要求手动清理，实际 \(message)")
                precondition(!message.contains("原来的视频都还在"), "不得谎称原文件还在，实际 \(message)")
            }
            precondition(
                !FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
                "过期标记应被自动清掉"
            )
        }
    }

    /// 状态表 g：启动时队列和偏好已切、源文件还在，不得当成完成并清标记。
    private static func checkInterruptG_LaunchDoesNotTreatAsComplete() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let destination = env.root.appendingPathComponent("to", isDirectory: true)
        let library = try seedStoreLibrary(env)
        var mover = MediaLibraryMover(defaults: env.defaults)
        mover.interruptAfter = .afterPreferenceSaved
        _ = mover.move(
            from: env.mediaFolder,
            to: destination,
            dataFile: env.dataFile,
            items: library,
            hasActiveDownload: false
        )
        precondition(
            MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .committedNeedsCleanup,
            "启动前必须识别为收尾未完"
        )
        for item in library {
            let name = URL(fileURLWithPath: item.localFilePath!).lastPathComponent
            precondition(FileManager.default.fileExists(atPath: env.mediaFolder.appendingPathComponent(name).path))
        }

        let store = await MainActor.run {
            QueueStore(
                dataFile: env.dataFile,
                mediaFolder: destination,
                defaults: env.defaults
            )
        }
        await MainActor.run {
            if let message = store.mediaFolderMoveMessage {
                precondition(!message.contains(MediaFolderCopy.needsManualCleanup), "不得要求手动清理目标，实际 \(message)")
                precondition(!message.contains("原来的视频都还在"), "不得谎称原文件还在，实际 \(message)")
            }
            for item in library {
                let name = URL(fileURLWithPath: item.localFilePath!).lastPathComponent
                precondition(
                    !FileManager.default.fileExists(atPath: env.mediaFolder.appendingPathComponent(name).path),
                    "启动收尾应补删源文件 \(name)"
                )
                precondition(FileManager.default.fileExists(atPath: destination.appendingPathComponent(name).path))
            }
            precondition(
                MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .idle
                    || !MediaFolderMoveMarker.exists(beside: env.dataFile)
            )
        }
    }

    private static func seedStoreLibrary(_ env: Env) throws -> [WatchItem] {
        var items: [WatchItem] = []
        for index in 0..<2 {
            let id = UUID()
            let video = env.mediaFolder.appendingPathComponent("\(id.uuidString).mp4")
            try Data("store-video-\(index)".utf8).write(to: video)
            items.append(
                WatchItem(
                    id: id,
                    urlString: "https://example.com/\(id.uuidString)",
                    title: "store-\(index)",
                    author: "check",
                    duration: 12,
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
            )
        }
        try writeQueue(items, to: env.dataFile)
        return items
    }

    /// 审查第 2 轮-2：QueueStore 对部分删除用告知文案，不用「原来的视频都还在」。
    private static func checkPartialDeleteDoesNotClaimSourcesRemain() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let first = env.mediaFolder.appendingPathComponent("one.mp4")
        let second = env.mediaFolder.appendingPathComponent("two.mp4")
        try Data("video-bytes-one".utf8).write(to: first)
        try Data("video-bytes-two".utf8).write(to: second)
        try writeQueue([], to: env.dataFile)
        var sourceDeletes = 0
        var mover = MediaLibraryMover(defaults: env.defaults)
        mover.removeItem = { url in
            if url.path.hasPrefix(env.mediaFolder.path) {
                sourceDeletes += 1
                if sourceDeletes == 2 {
                    throw NSError(
                        domain: "media-folder-check",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "operation not permitted"]
                    )
                }
            }
            try FileManager.default.removeItem(at: url)
        }
        let injected = mover
        let dest = env.root.appendingPathComponent("new-library", isDirectory: true)
        let observed = await MainActor.run { () -> (MediaLibraryMoveResult, String?, URL) in
            let store = QueueStore(dataFile: env.dataFile, mediaFolder: env.mediaFolder, defaults: env.defaults)
            let result = store.moveMediaFolder(to: dest, mover: injected)
            return (result, store.mediaFolderMoveMessage, store.mediaFolder)
        }
        guard case .finishedWithSourceLeftovers(let note) = observed.0 else {
            fatalError("部分删除应是搬移已完成，实际 \(observed.0)")
        }
        precondition(observed.1 == note)
        precondition(!note.contains("原来的视频都还在"))
        precondition(note.contains("搬移已经完成"))
        precondition(observed.2.standardizedFileURL.path == dest.standardizedFileURL.path)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == dest.standardizedFileURL.path)
    }

    /// 审查 5：设置页订赋值后的发布，看到的失败文案与 store 最终值一致。
    private static func checkSettingsMirrorSeesFailureAfterChange() async throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let id = UUID()
        let name = "\(id.uuidString).mp4"
        let video = env.mediaFolder.appendingPathComponent(name)
        try Data("video-bytes-one".utf8).write(to: video)
        try writeQueue([
            WatchItem(
                id: id,
                urlString: "https://example.com/conflict",
                title: "conflict",
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
        ], to: env.dataFile)

        let dest = env.root.appendingPathComponent("existing", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("different-existing".utf8).write(to: dest.appendingPathComponent(name))

        let observed = await MainActor.run { () -> (MediaLibraryMoveResult, String?, String?) in
            let store = QueueStore(dataFile: env.dataFile, mediaFolder: env.mediaFolder, defaults: env.defaults)
            let mirror = SettingsPageMirror()
            mirror.bind(store)
            let result = store.moveMediaFolder(to: dest)
            return (result, store.mediaFolderMoveMessage, mirror.failure)
        }
        guard case .failure(let reason) = observed.0 else {
            fatalError("冲突必须失败，实际 \(observed.0)")
        }
        let expected = MediaFolderCopy.failure(reason)
        precondition(observed.1 == expected, "store 最终失败文案必须是包装后的原因")
        precondition(
            observed.2 == expected,
            "设置页订赋值后发布，必须拿到与 store 一致的失败文案，实际 \(String(describing: observed.2))"
        )
        precondition(observed.1 == observed.2)
    }

    /// 与 `DigestSettingsLiveView` 相同：订 `$published`，不订 `objectWillChange`。
    @MainActor
    private final class SettingsPageMirror {
        var failure: String?
        var folder: URL?
        private var bag = Set<AnyCancellable>()

        func bind(_ store: QueueStore) {
            store.$mediaFolderMoveMessage
                .sink { [weak self] in self?.failure = $0 }
                .store(in: &bag)
            store.$mediaFolder
                .sink { [weak self] in self?.folder = $0 }
                .store(in: &bag)
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
