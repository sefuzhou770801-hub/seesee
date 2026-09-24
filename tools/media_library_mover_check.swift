import Foundation

@main
struct MediaLibraryMoverCheck {
    static func main() throws {
        checkAvailability()
        checkPreferenceDefault()
        checkLaunchArguments()
        try checkSuccessfulMove()
        try checkCorruptCopyRollsBack()
        try checkConflictAborts()
        try checkDownloadBlock()
        try checkSameFolderNoOp()
        try checkDisconnectedSourceIsNotEmptyLibrary()
        try checkMissingSourceFails()
        try checkEnumerationErrorFails()
        try checkCopyThrowLeavesNoResidueAndCanRetry()
        try checkPartialSourceDeleteCompletesWithNote()
        try checkDisconnectedDestinationDoesNotCreate()
        try checkRollbackReportsDeleteFailure()
        try checkRollbackCleanupFailureKeepsMarker()
        try checkMarkerClearFailureIsStillSuccess()
        try checkStaleCompletedMarkerAllowsNewMove()
        try checkInterruptA_BeforeStart()
        try checkInterruptB_AfterMarkerWritten()
        try checkInterruptC_DuringCopy()
        try checkInterruptD_AfterVerified()
        try checkInterruptE_AfterQueueBackup()
        try checkInterruptF_AfterQueueRemapped()
        try checkInterruptG_AfterPreferenceSaved()
        try checkInterruptH_DuringSourceDelete()
        try checkInterruptI_AfterSourcesDeleted()
        try checkInterruptJ_AfterMarkerCleared()
        print("media_library_mover_check=passed")
    }

    private static func checkAvailability() {
        let root = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let missing = URL(fileURLWithPath: "/Volumes/不存在的卷/seesee", isDirectory: true)
        let mounted = [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Volumes/移动ssd")]
        precondition(
            MediaFolderAvailability.isDisconnected(missing, mountedVolumes: mounted, volumesRoot: root),
            "未挂载的 /Volumes/不存在的卷 必须判为未连接"
        )

        let connected = URL(fileURLWithPath: "/Volumes/移动ssd/seesee", isDirectory: true)
        precondition(
            !MediaFolderAvailability.isDisconnected(connected, mountedVolumes: mounted, volumesRoot: root),
            "已挂载卷上的目录不得判为未连接"
        )

        let movies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Replay", isDirectory: true)
        precondition(
            !MediaFolderAvailability.isDisconnected(movies, mountedVolumes: mounted),
            "家目录片库不是未连接"
        )

        let fakeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-avail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fakeRoot) }
        let fakeVolumes = fakeRoot.appendingPathComponent("Volumes", isDirectory: true)
        let fakeMissing = fakeVolumes.appendingPathComponent("不存在的卷/seesee", isDirectory: true)
        precondition(
            MediaFolderAvailability.isDisconnected(
                fakeMissing,
                mountedVolumes: [URL(fileURLWithPath: "/")],
                volumesRoot: fakeVolumes
            ),
            "注入挂载列表后，假卷根下的缺失卷也是未连接"
        )
    }

    private static func checkPreferenceDefault() {
        let suite = "media-folder-pref-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(MediaFolderPreference.resolve(defaults: defaults) == nil, "没设过时没有自定义路径")
        let dest = URL(fileURLWithPath: "/tmp/seesee-library", isDirectory: true)
        MediaFolderPreference.save(dest, defaults: defaults)
        precondition(defaults.string(forKey: "MediaFolderPath") == dest.standardizedFileURL.path)
        precondition(MediaFolderPreference.resolve(defaults: defaults)?.path == dest.standardizedFileURL.path)
    }

    private static func checkLaunchArguments() {
        let dest = MediaFolderLaunchArguments.moveDestination(
            from: ["Replay", "--move-media-folder", "/tmp/seesee-dest"]
        )
        precondition(dest?.path == URL(fileURLWithPath: "/tmp/seesee-dest", isDirectory: true).path)
        precondition(MediaFolderLaunchArguments.moveDestination(from: ["Replay"]) == nil)
        precondition(
            MediaFolderLaunchArguments.moveDestination(from: ["Replay", "--move-media-folder"]) == nil,
            "缺目标路径时不搬"
        )
    }

    private static func checkSuccessfulMove() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let id = UUID()
        let video = env.source.appendingPathComponent("\(id.uuidString).mp4")
        let thumb = env.source.appendingPathComponent("\(id.uuidString).jpg")
        let subtitle = env.source.appendingPathComponent("\(id.uuidString).zh.srt")
        let nested = env.source.appendingPathComponent("notes/readme.txt")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("video-bytes-one".utf8).write(to: video)
        try Data("thumb-bytes".utf8).write(to: thumb)
        try Data("subtitle-line".utf8).write(to: subtitle)
        try Data("nested-note".utf8).write(to: nested)
        try Data("skip-me".utf8).write(to: env.source.appendingPathComponent(".DS_Store"))

        let item = sampleItem(
            id: id,
            local: video.path,
            thumbnail: thumb.path,
            subtitle: subtitle.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([item]).write(to: env.dataFile)
        let originalQueue = try Data(contentsOf: env.dataFile)
        var progressEvents: [MediaLibraryMoveProgress] = []
        let mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [item],
            hasActiveDownload: false
        ) { progressEvents.append($0) }

        precondition(result == .success, "搬移应当成功，实际 \(result)")
        precondition(progressEvents.last?.completed == 4 && progressEvents.last?.total == 4)

        let destVideo = env.destination.appendingPathComponent("\(id.uuidString).mp4")
        let destThumb = env.destination.appendingPathComponent("\(id.uuidString).jpg")
        let destSubtitle = env.destination.appendingPathComponent("\(id.uuidString).zh.srt")
        let destNested = env.destination.appendingPathComponent("notes/readme.txt")
        precondition(shasum(destVideo) == "0d8922b124788400f3434cc34fe299fe5f47647137509322c21f643218ca1f06")
        precondition(shasum(destThumb) == "efe392e3d421b75aa5a88ee0658a5aede0a481a8fe84bf80334fdf654d1f1dc1")
        precondition(shasum(destSubtitle) == "9f207d5c3bf7d9ff515a7e6e74f64583f52f8f4f148131eadf1d8d7654e0e9e1")
        precondition(shasum(destNested) == "b3022315d8380a5fa78b4b47d7903ce1ef59b813ba3bcefb846766c64c139e05")
        precondition(!FileManager.default.fileExists(atPath: video.path), "原视频应已删除")
        precondition(!FileManager.default.fileExists(atPath: thumb.path))
        precondition(!FileManager.default.fileExists(atPath: subtitle.path))
        precondition(!FileManager.default.fileExists(atPath: nested.path))
        precondition(
            FileManager.default.fileExists(atPath: env.source.path),
            "原目录本身保留"
        )
        precondition(!FileManager.default.fileExists(atPath: env.destination.appendingPathComponent(".DS_Store").path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rewritten = try decoder.decode([WatchItem].self, from: Data(contentsOf: env.dataFile))
        precondition(rewritten[0].localFilePath == destVideo.path)
        precondition(rewritten[0].thumbnailFilePath == destThumb.path)
        precondition(rewritten[0].subtitleFilePath == destSubtitle.path)

        let stamp = backupStamp(env.now)
        let backup = env.support.appendingPathComponent("queue.json.bak-\(stamp)")
        precondition(FileManager.default.fileExists(atPath: backup.path), "必须留下 queue.json 备份 queue.json.bak-\(stamp)")
        let backupData = try Data(contentsOf: backup)
        precondition(backupData == originalQueue, "备份必须是改写前的内容")
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == env.destination.standardizedFileURL.path)
        precondition(
            !FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
            "成功后必须清掉进行中标记"
        )
    }

    private static func checkCorruptCopyRollsBack() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let id = UUID()
        let video = env.source.appendingPathComponent("\(id.uuidString).mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        let originalQueue = try Data(contentsOf: env.dataFile)
        let item = sampleItem(id: id, local: video.path, thumbnail: nil, subtitle: nil)

        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.copyItem = { from, to in
            try FileManager.default.copyItem(at: from, to: to)
            try Data("corrupted-after-copy".utf8).write(to: to)
        }
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [item],
            hasActiveDownload: false
        )
        guard case .failure = result else {
            fatalError("复制后内容被改坏必须失败，实际 \(result)")
        }
        precondition(FileManager.default.fileExists(atPath: video.path), "失败后原文件必须还在")
        let leftoverVideo = try Data(contentsOf: video)
        let leftoverQueue = try Data(contentsOf: env.dataFile)
        precondition(leftoverVideo == Data("video-bytes-one".utf8))
        precondition(leftoverQueue == originalQueue, "失败后 queue.json 不得改")
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil, "失败后设置不得改")
        precondition(
            !FileManager.default.fileExists(atPath: env.destination.path),
            "失败后目标不得残留"
        )
        let backups = try FileManager.default.contentsOfDirectory(atPath: env.support.path)
            .filter { $0.hasPrefix("queue.json.bak-") }
        precondition(backups.isEmpty, "核对失败时不应留下备份")
    }

    private static func checkConflictAborts() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let id = UUID()
        let name = "\(id.uuidString).mp4"
        let video = env.source.appendingPathComponent(name)
        try Data("video-bytes-one".utf8).write(to: video)
        try FileManager.default.createDirectory(at: env.destination, withIntermediateDirectories: true)
        try Data("different-existing".utf8).write(to: env.destination.appendingPathComponent(name))
        let originalQueue = try Data(contentsOf: env.dataFile)
        let destBefore = try Data(contentsOf: env.destination.appendingPathComponent(name))

        let mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [sampleItem(id: id, local: video.path, thumbnail: nil, subtitle: nil)],
            hasActiveDownload: false
        )
        guard case .failure = result else {
            fatalError("同名不同内容必须中止，实际 \(result)")
        }
        let leftoverSource = try Data(contentsOf: video)
        let leftoverDest = try Data(contentsOf: env.destination.appendingPathComponent(name))
        let leftoverQueue = try Data(contentsOf: env.dataFile)
        precondition(leftoverSource == Data("video-bytes-one".utf8))
        precondition(leftoverDest == destBefore, "不得覆盖目标已有文件")
        precondition(leftoverQueue == originalQueue)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
    }

    private static func checkDownloadBlock() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let mover = MediaLibraryMover(defaults: env.defaults)
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: true
        )
        precondition(result == .failure(MediaFolderCopy.downloadingBlock))
        precondition(!FileManager.default.fileExists(atPath: env.destination.path))
    }

    private static func checkSameFolderNoOp() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let video = env.source.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        let mover = MediaLibraryMover(defaults: env.defaults)
        let result = mover.move(
            from: env.source,
            to: env.source,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        precondition(result == .noOp)
        precondition(FileManager.default.fileExists(atPath: video.path))
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
    }

    /// 审查 1：未挂载源卷不得当空片库成功搬移。
    private static func checkDisconnectedSourceIsNotEmptyLibrary() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let fakeVolumes = env.root.appendingPathComponent("Volumes", isDirectory: true)
        let missing = fakeVolumes.appendingPathComponent("不存在的卷/seesee", isDirectory: true)
        let originalQueue = try Data(contentsOf: env.dataFile)
        let mover = MediaLibraryMover(
            defaults: env.defaults,
            now: { env.now },
            mountedVolumes: [URL(fileURLWithPath: "/")],
            volumesRoot: fakeVolumes
        )
        let result = mover.move(
            from: missing,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        precondition(result == .failure(MediaFolderCopy.sourceDisconnected), "未连接源必须拒绝，实际 \(result)")
        let leftoverDisconnected = try Data(contentsOf: env.dataFile)
        precondition(leftoverDisconnected == originalQueue, "未连接时不得改 queue.json")
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
        precondition(!FileManager.default.fileExists(atPath: env.destination.path))
        precondition(!FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path))
    }

    /// 审查 1：源目录不存在也不能当空列表成功。
    private static func checkMissingSourceFails() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let missing = env.root.appendingPathComponent("no-such-library", isDirectory: true)
        let originalQueue = try Data(contentsOf: env.dataFile)
        let mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        let result = mover.move(
            from: missing,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let reason) = result else {
            fatalError("源目录不存在必须失败，实际 \(result)")
        }
        precondition(reason.contains("源目录不存在"), "失败原因应说明源不存在，实际 \(reason)")
        let leftoverMissing = try Data(contentsOf: env.dataFile)
        precondition(leftoverMissing == originalQueue)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
        precondition(!FileManager.default.fileExists(atPath: env.destination.path))
    }

    /// 审查 1：枚举子目录出错必须整次失败，不能只搬走看得见的文件。
    private static func checkEnumerationErrorFails() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let visible = env.source.appendingPathComponent("visible.mp4")
        try Data("visible-bytes".utf8).write(to: visible)
        let locked = env.source.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("hidden-bytes".utf8).write(to: locked.appendingPathComponent("hidden.mp4"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }

        let originalQueue = try Data(contentsOf: env.dataFile)
        let mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let reason) = result else {
            fatalError("枚举出错必须失败，实际 \(result)")
        }
        precondition(reason.contains("枚举"), "失败原因应提到枚举，实际 \(reason)")
        let leftoverEnum = try Data(contentsOf: env.dataFile)
        precondition(leftoverEnum == originalQueue)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
        precondition(!FileManager.default.fileExists(atPath: env.destination.path))
    }

    /// 审查 2：copyItem 写出目标后抛错，半成品必须清掉，同一目标可以重试。
    private static func checkCopyThrowLeavesNoResidueAndCanRetry() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let first = env.source.appendingPathComponent("one.mp4")
        let second = env.source.appendingPathComponent("two.mp4")
        try Data("video-bytes-one".utf8).write(to: first)
        try Data("video-bytes-two".utf8).write(to: second)
        try FileManager.default.createDirectory(at: env.destination, withIntermediateDirectories: true)
        let originalQueue = try Data(contentsOf: env.dataFile)

        var attempts = 0
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.copyItem = { from, to in
            attempts += 1
            try FileManager.default.copyItem(at: from, to: to)
            if attempts == 2 {
                throw NSError(
                    domain: "media-folder-check",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "disk full"]
                )
            }
        }
        let failed = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let reason) = failed else {
            fatalError("复制中途抛错必须失败，实际 \(failed)")
        }
        precondition(reason.contains("disk full"), "失败原因应带上复制器错误，实际 \(reason)")
        precondition(FileManager.default.fileExists(atPath: first.path))
        precondition(FileManager.default.fileExists(atPath: second.path))
        let leftoverCopy = try Data(contentsOf: env.dataFile)
        precondition(leftoverCopy == originalQueue)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
        precondition(
            !FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("one.mp4").path),
            "已复制的第一份也必须回滚"
        )
        precondition(
            !FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("two.mp4").path),
            "抛错前落地的半成品必须回滚"
        )
        precondition(!FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path))

        let retry = MediaLibraryMover(defaults: env.defaults, now: { env.now }).move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        precondition(retry == .success, "清干净后重试同一目标应当成功，实际 \(retry)")
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("one.mp4").path))
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("two.mp4").path))
        precondition(!FileManager.default.fileExists(atPath: first.path))
        precondition(!FileManager.default.fileExists(atPath: second.path))
    }

    /// 审查第 2 轮-2：提交后部分删除失败算搬移已完成，不能说原来的视频都还在。
    private static func checkPartialSourceDeleteCompletesWithNote() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let first = env.source.appendingPathComponent("one.mp4")
        let second = env.source.appendingPathComponent("two.mp4")
        try Data("video-bytes-one".utf8).write(to: first)
        try Data("video-bytes-two".utf8).write(to: second)
        let id = UUID()
        let item = sampleItem(id: id, local: first.path, thumbnail: nil, subtitle: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([item]).write(to: env.dataFile)
        var sourceDeletes = 0
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.removeItem = { url in
            if url.path.hasPrefix(env.source.path) {
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
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [item],
            hasActiveDownload: false
        )
        guard case .finishedWithSourceLeftovers(let note) = result else {
            fatalError("部分删除失败应是搬移已完成，实际 \(result)")
        }
        precondition(!note.contains("原来的视频都还在"), "不得再说原来的视频都还在，实际 \(note)")
        precondition(note.contains("搬移已经完成"), "应说明搬移已经完成，实际 \(note)")
        precondition(note.contains(env.source.path), "应给出源目录路径，实际 \(note)")
        let remaining = [first, second].filter { FileManager.default.fileExists(atPath: $0.path) }
        precondition(remaining.count == 1, "应恰好留下一个没删掉的原文件")
        precondition(note.contains(remaining[0].lastPathComponent), "应点出没删掉的文件，实际 \(note)")
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("one.mp4").path))
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("two.mp4").path))
        precondition(
            !FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
            "搬移已完成后不得留下进行中标记"
        )
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == env.destination.standardizedFileURL.path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rewritten = try decoder.decode([WatchItem].self, from: Data(contentsOf: env.dataFile))
        precondition(rewritten[0].localFilePath == env.destination.appendingPathComponent("one.mp4").path)
    }

    /// 审查 4：目标卷未挂载时不得 createDirectory。
    private static func checkDisconnectedDestinationDoesNotCreate() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let video = env.source.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        let fakeVolumes = env.root.appendingPathComponent("Volumes", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeVolumes, withIntermediateDirectories: true)
        let dest = fakeVolumes.appendingPathComponent("不存在的卷/seesee", isDirectory: true)
        let originalQueue = try Data(contentsOf: env.dataFile)
        let mover = MediaLibraryMover(
            defaults: env.defaults,
            now: { env.now },
            mountedVolumes: [URL(fileURLWithPath: "/")],
            volumesRoot: fakeVolumes
        )
        let result = mover.move(
            from: env.source,
            to: dest,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        precondition(result == .failure(MediaFolderCopy.destinationDisconnected), "目标未连接必须拒绝，实际 \(result)")
        precondition(FileManager.default.fileExists(atPath: video.path))
        let leftoverDest = try Data(contentsOf: env.dataFile)
        precondition(leftoverDest == originalQueue)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
        precondition(!FileManager.default.fileExists(atPath: dest.path), "不得创建目标目录")
        precondition(
            !FileManager.default.fileExists(atPath: fakeVolumes.appendingPathComponent("不存在的卷").path),
            "不得在卷根留下同名空目录"
        )
    }

    /// Standards：回滚删除失败必须写进错误，不能 try? 吞掉。
    private static func checkRollbackReportsDeleteFailure() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let video = env.source.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.copyItem = { from, to in
            try FileManager.default.copyItem(at: from, to: to)
            throw NSError(
                domain: "media-folder-check",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "verify interrupt"]
            )
        }
        mover.removeItem = { url in
            throw NSError(
                domain: "media-folder-check",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "cannot unlink leftover"]
            )
        }
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let reason) = result else {
            fatalError("回滚删除失败必须反映为失败，实际 \(result)")
        }
        precondition(reason.contains("verify interrupt"))
        precondition(reason.contains("回滚目标文件没有完成"), "应报告回滚失败，实际 \(reason)")
        precondition(reason.contains("cannot unlink leftover"))
        precondition(reason.contains(MediaFolderCopy.needsManualCleanup), "回滚清理失败应要求手动清理，实际 \(reason)")
        precondition(reason.contains(env.destination.path), "应给出目标目录路径，实际 \(reason)")
        precondition(
            FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
            "回滚清理失败必须留下进行中标记"
        )
    }

    /// 审查第 2 轮-1：已有目标目录、复制后抛错且回滚删除也失败时，标记必须留下。
    private static func checkRollbackCleanupFailureKeepsMarker() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        try FileManager.default.createDirectory(at: env.destination, withIntermediateDirectories: true)
        let video = env.source.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        let originalQueue = try Data(contentsOf: env.dataFile)
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.copyItem = { from, to in
            try FileManager.default.copyItem(at: from, to: to)
            throw NSError(
                domain: "media-folder-check",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "disk full"]
            )
        }
        mover.removeItem = { url in
            if url.path.hasPrefix(env.destination.path) {
                throw NSError(
                    domain: "media-folder-check",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "destination volume read-only"]
                )
            }
            try FileManager.default.removeItem(at: url)
        }
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let reason) = result else {
            fatalError("回滚清理失败必须失败，实际 \(result)")
        }
        precondition(reason.contains("disk full"))
        precondition(reason.contains(env.destination.path), "应给出目标目录路径，实际 \(reason)")
        precondition(reason.contains(MediaFolderCopy.needsManualCleanup), "应说明需要手动清理，实际 \(reason)")
        precondition(!reason.contains("可以重试") || reason.contains(MediaFolderCopy.needsManualCleanup))
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("keep.mp4").path))
        let leftoverQueue = try Data(contentsOf: env.dataFile)
        precondition(leftoverQueue == originalQueue)
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == nil)
        precondition(
            FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
            "回滚清理失败后标记必须还在"
        )

        let blocked = MediaLibraryMover(defaults: env.defaults, now: { env.now }).move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let blockedReason) = blocked else {
            fatalError("有残余标记时不得放行重试，实际 \(blocked)")
        }
        precondition(blockedReason.contains(MediaFolderCopy.needsManualCleanup))
        precondition(blockedReason.contains(env.destination.path))
    }

    /// 审查第 3 轮-1：源文件已删、队列和偏好已切走，只是清标记失败，仍算成功。
    private static func checkMarkerClearFailureIsStillSuccess() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let video = env.source.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.removeItem = { url in
            if url.lastPathComponent == MediaFolderCopy.inProgressMarkerName {
                throw NSError(
                    domain: "media-folder-check",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "marker locked"]
                )
            }
            try FileManager.default.removeItem(at: url)
        }
        let result = mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        precondition(result == .success, "清标记失败仍应报告成功，实际 \(result)")
        if case .failure(let reason) = result {
            fatalError("不得报失败：\(reason)")
        }
        precondition(!FileManager.default.fileExists(atPath: video.path))
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("keep.mp4").path))
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == env.destination.standardizedFileURL.path)
        precondition(
            FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
            "这条路径下标记可以留下"
        )
    }

    /// 审查第 3 轮-1：源已删完、队列和偏好都已切走，只剩标记时，下次搬移应清掉标记并继续。
    private static func checkStaleCompletedMarkerAllowsNewMove() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let library = try seedLibrary(env)
        _ = interruptMove(env, items: library.items, after: .afterSourcesDeleted)
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .completedMarkerLeft)

        let next = env.root.appendingPathComponent("next", isDirectory: true)
        let later = env.now.addingTimeInterval(2)
        let result = MediaLibraryMover(defaults: env.defaults, now: { later }).move(
            from: env.destination,
            to: next,
            dataFile: env.dataFile,
            items: remappedItems(library.items, from: env.source, to: env.destination),
            hasActiveDownload: false
        )
        precondition(result == .success, "真正完成后的过期标记不得挡住新搬移，实际 \(result)")
        precondition(!FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path))
        for file in library.sourceFiles {
            precondition(!FileManager.default.fileExists(atPath: file.path))
            precondition(FileManager.default.fileExists(atPath: next.appendingPathComponent(file.lastPathComponent).path))
        }
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == next.standardizedFileURL.path)
    }

    /// 状态表 a：还没写标记，重启后无恢复动作。
    private static func checkInterruptA_BeforeStart() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .idle)
        precondition(!MediaFolderMoveMarker.exists(beside: env.dataFile))
        for file in library.sourceFiles {
            precondition(FileManager.default.fileExists(atPath: file.path))
        }
        let after = MediaFolderMoveRecovery.apply(beside: env.dataFile, defaults: env.defaults)
        precondition(after == .idle)
        precondition(!MediaFolderMoveMarker.exists(beside: env.dataFile))
    }

    /// 状态表 b：已写标记、复制未开始。
    private static func checkInterruptB_AfterMarkerWritten() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterMarkerWritten)
        precondition(result == .failure("搬移中断"))
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: false,
            preferenceAtDestination: false,
            destinationComplete: false,
            leftoverSourceCount: 2
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .incomplete)
        applyKeepsIncompleteMarker(env)
    }

    /// 状态表 c：复制进行中。
    private static func checkInterruptC_DuringCopy() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterCopyProgress(completed: 1))
        precondition(result == .failure("搬移中断"))
        let destCount = destRegularFileCount(env.destination)
        precondition(destCount == 1, "复制中断后目标应只有部分文件，实际 \(destCount)")
        precondition(sourceRegularFileCount(env.source) == 2)
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: false,
            preferenceAtDestination: false,
            destinationComplete: false,
            leftoverSourceCount: 2
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .incomplete)
        applyKeepsIncompleteMarker(env)
    }

    /// 状态表 d：核对通过，还没备份队列。
    private static func checkInterruptD_AfterVerified() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterVerified)
        precondition(result == .failure("搬移中断"))
        precondition(queueBackupCount(env) == 0)
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: false,
            preferenceAtDestination: false,
            destinationComplete: true,
            leftoverSourceCount: 2
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .incomplete)
        applyKeepsIncompleteMarker(env)
    }

    /// 状态表 e：已备份队列，还没改写。
    private static func checkInterruptE_AfterQueueBackup() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterQueueBackedUp)
        precondition(result == .failure("搬移中断"))
        precondition(queueBackupCount(env) == 1)
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: false,
            preferenceAtDestination: false,
            destinationComplete: true,
            leftoverSourceCount: 2
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .incomplete)
        applyKeepsIncompleteMarker(env)
    }

    /// 状态表 f：队列已改写，偏好未写。
    private static func checkInterruptF_AfterQueueRemapped() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterQueueRemapped)
        precondition(result == .failure("搬移中断"))
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: true,
            preferenceAtDestination: false,
            destinationComplete: true,
            leftoverSourceCount: 2
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .incomplete)
        applyKeepsIncompleteMarker(env)
    }

    /// 状态表 g：队列和偏好已切走，源文件还没删。第 4 轮审查复现场景。
    private static func checkInterruptG_AfterPreferenceSaved() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterPreferenceSaved)
        precondition(result == .failure("搬移中断"))
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: true,
            preferenceAtDestination: true,
            destinationComplete: true,
            leftoverSourceCount: 2
        )
        precondition(
            MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .committedNeedsCleanup,
            "源文件未删不得判成已完成"
        )
        precondition(MediaFolderMoveMarker.exists(beside: env.dataFile))

        let later = env.now.addingTimeInterval(2)
        let refused = MediaLibraryMover(defaults: env.defaults, now: { later }).move(
            from: env.destination,
            to: env.root.appendingPathComponent("next", isDirectory: true),
            dataFile: env.dataFile,
            items: remappedItems(library.items, from: env.source, to: env.destination),
            hasActiveDownload: false
        )
        if case .failure(let reason) = refused {
            fatalError("收尾应先补删源文件，不得报失败：\(reason)")
        }
        for file in library.sourceFiles {
            precondition(!FileManager.default.fileExists(atPath: file.path), "收尾后源文件应被补删")
        }
    }

    /// 状态表 h：部分源文件已删。
    private static func checkInterruptH_DuringSourceDelete() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterSourceDeleteProgress(deleted: 1))
        precondition(result == .failure("搬移中断"))
        precondition(sourceRegularFileCount(env.source) == 1, "删源中断后应剩 1 个源文件")
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: true,
            preferenceAtDestination: true,
            destinationComplete: true,
            leftoverSourceCount: 1
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .committedNeedsCleanup)
        let after = MediaFolderMoveRecovery.apply(beside: env.dataFile, defaults: env.defaults)
        precondition(after == .idle || after == .completedMarkerLeft)
        precondition(sourceRegularFileCount(env.source) == 0)
        if after == .idle {
            precondition(!MediaFolderMoveMarker.exists(beside: env.dataFile))
        }
    }

    /// 状态表 i：源已删完，标记还在。
    private static func checkInterruptI_AfterSourcesDeleted() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = interruptMove(env, items: library.items, after: .afterSourcesDeleted)
        precondition(result == .failure("搬移中断"))
        assertInterruptedFacts(
            env,
            library: library,
            queueAtDestination: true,
            preferenceAtDestination: true,
            destinationComplete: true,
            leftoverSourceCount: 0
        )
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .completedMarkerLeft)
        let after = MediaFolderMoveRecovery.apply(beside: env.dataFile, defaults: env.defaults)
        precondition(after == .idle)
        precondition(!MediaFolderMoveMarker.exists(beside: env.dataFile))
        for file in library.sourceFiles {
            precondition(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    /// 状态表 j：标记已清，正常完成。
    private static func checkInterruptJ_AfterMarkerCleared() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }
        let library = try seedLibrary(env)
        let result = MediaLibraryMover(defaults: env.defaults, now: { env.now }).move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: library.items,
            hasActiveDownload: false
        )
        precondition(result == .success)
        precondition(!MediaFolderMoveMarker.exists(beside: env.dataFile))
        precondition(MediaFolderMoveRecovery.inspect(beside: env.dataFile, defaults: env.defaults) == .idle)
        precondition(MediaFolderMoveRecovery.apply(beside: env.dataFile, defaults: env.defaults) == .idle)
        for file in library.sourceFiles {
            precondition(!FileManager.default.fileExists(atPath: file.path))
            precondition(
                FileManager.default.fileExists(atPath: env.destination.appendingPathComponent(file.lastPathComponent).path)
            )
        }
    }

    private struct SeededLibrary {
        let items: [WatchItem]
        let sourceFiles: [URL]
    }

    private static func seedLibrary(_ env: Env) throws -> SeededLibrary {
        var items: [WatchItem] = []
        var files: [URL] = []
        for index in 0..<2 {
            let id = UUID()
            let video = env.source.appendingPathComponent("\(id.uuidString).mp4")
            try Data("video-bytes-\(index)".utf8).write(to: video)
            files.append(video)
            items.append(sampleItem(id: id, local: video.path, thumbnail: nil, subtitle: nil))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: env.dataFile)
        return SeededLibrary(items: items, sourceFiles: files)
    }

    private static func interruptMove(
        _ env: Env,
        items: [WatchItem],
        after: MediaLibraryMoveInterrupt
    ) -> MediaLibraryMoveResult {
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.interruptAfter = after
        return mover.move(
            from: env.source,
            to: env.destination,
            dataFile: env.dataFile,
            items: items,
            hasActiveDownload: false
        )
    }

    private static func remappedItems(
        _ items: [WatchItem],
        from source: URL,
        to destination: URL
    ) -> [WatchItem] {
        let remap = ReplayMigrationResult(
            applicationSupport: destination,
            mediaFolder: destination,
            movedFromMediaFolder: source
        )
        var copy = items
        for index in copy.indices {
            copy[index].localFilePath = remap.remappedMediaPath(copy[index].localFilePath)
            copy[index].thumbnailFilePath = remap.remappedMediaPath(copy[index].thumbnailFilePath)
            copy[index].subtitleFilePath = remap.remappedMediaPath(copy[index].subtitleFilePath)
        }
        return copy
    }

    private static func loadItems(_ env: Env) throws -> [WatchItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([WatchItem].self, from: Data(contentsOf: env.dataFile))
    }

    private static func regularFileCount(_ root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return 0 }
        var count = 0
        for case let file as URL in enumerator {
            if file.lastPathComponent == ".DS_Store" { continue }
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    private static func destRegularFileCount(_ root: URL) -> Int { regularFileCount(root) }
    private static func sourceRegularFileCount(_ root: URL) -> Int { regularFileCount(root) }

    private static func queueBackupCount(_ env: Env) -> Int {
        let parent = env.dataFile.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        return names.filter { $0.hasPrefix("queue.json.bak-") }.count
    }

    private static func applyKeepsIncompleteMarker(_ env: Env) {
        let after = MediaFolderMoveRecovery.apply(beside: env.dataFile, defaults: env.defaults)
        precondition(after == .incomplete, "未完成节点不得自动放行，实际 \(after)")
        precondition(MediaFolderMoveMarker.exists(beside: env.dataFile))
        let next = env.root.appendingPathComponent("retry-\(UUID().uuidString)", isDirectory: true)
        let result = MediaLibraryMover(defaults: env.defaults, now: { env.now }).move(
            from: env.source,
            to: next,
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        guard case .failure(let reason) = result else {
            fatalError("未完成必须拒绝新搬移，实际 \(result)")
        }
        precondition(
            reason.contains(MediaFolderCopy.needsManualCleanup) || reason.contains(MediaFolderCopy.incompleteMove),
            "拒绝文案应说明未完成，实际 \(reason)"
        )
        precondition(MediaFolderMoveMarker.exists(beside: env.dataFile))
    }

    private static func assertInterruptedFacts(
        _ env: Env,
        library: SeededLibrary,
        queueAtDestination: Bool,
        preferenceAtDestination: Bool,
        destinationComplete: Bool,
        leftoverSourceCount: Int
    ) {
        precondition(MediaFolderMoveMarker.exists(beside: env.dataFile), "中断后必须留下进行中标记")
        let markedDest = MediaFolderMoveMarker.destination(beside: env.dataFile)
        let markedSource = MediaFolderMoveMarker.source(beside: env.dataFile)
        precondition(markedDest?.standardizedFileURL.path == env.destination.standardizedFileURL.path)
        precondition(markedSource?.standardizedFileURL.path == env.source.standardizedFileURL.path)

        let items = (try? loadItems(env)) ?? []
        precondition(items.count == library.items.count)
        let destPrefix = env.destination.standardizedFileURL.path
        let sourcePrefix = env.source.standardizedFileURL.path
        for item in items {
            guard let path = item.localFilePath else { continue }
            if queueAtDestination {
                precondition(path.hasPrefix(destPrefix), "队列应已指向目标：\(path)")
            } else {
                precondition(path.hasPrefix(sourcePrefix), "队列应仍指向源：\(path)")
            }
        }

        let pref = env.defaults.string(forKey: MediaFolderPreference.key)
        if preferenceAtDestination {
            precondition(pref == env.destination.standardizedFileURL.path, "偏好应已指向目标，实际 \(pref ?? "nil")")
        } else {
            precondition(pref == nil || pref == env.source.standardizedFileURL.path, "偏好不得提前指向目标，实际 \(pref ?? "nil")")
        }

        precondition(
            sourceRegularFileCount(env.source) == leftoverSourceCount,
            "源文件残留数不对，实际 \(sourceRegularFileCount(env.source))"
        )
        if destinationComplete {
            precondition(destRegularFileCount(env.destination) == library.sourceFiles.count)
            for file in library.sourceFiles {
                let destFile = env.destination.appendingPathComponent(file.lastPathComponent)
                precondition(FileManager.default.fileExists(atPath: destFile.path), "目标缺少 \(file.lastPathComponent)")
                if FileManager.default.fileExists(atPath: file.path) {
                    precondition(shasum(destFile) == shasum(file), "目标与源内容不一致：\(file.lastPathComponent)")
                }
            }
        }
    }

    private struct Env {
        let root: URL
        let source: URL
        let destination: URL
        let support: URL
        let dataFile: URL
        let defaults: UserDefaults
        let suite: String
        let now = Date(timeIntervalSince1970: 1_790_226_900)
    }

    private static func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-mover-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("from", isDirectory: true)
        let destination = root.appendingPathComponent("to", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let dataFile = support.appendingPathComponent("queue.json")
        try Data("[]".utf8).write(to: dataFile)
        let suite = "media-mover-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Env(
            root: root,
            source: source,
            destination: destination,
            support: support,
            dataFile: dataFile,
            defaults: defaults,
            suite: suite
        )
    }

    private static func sampleItem(
        id: UUID,
        local: String?,
        thumbnail: String?,
        subtitle: String?
    ) -> WatchItem {
        WatchItem(
            id: id,
            urlString: "https://example.com/\(id.uuidString)",
            title: "sample",
            author: "check",
            duration: 12,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            watchedAt: nil,
            state: .ready,
            progress: 1,
            progressLabel: "已下载",
            localFilePath: local,
            errorMessage: nil,
            playbackPosition: nil,
            chapters: nil,
            thumbnailFilePath: thumbnail,
            subtitleFilePath: subtitle
        )
    }

    private static func backupStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func shasum(_ url: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            fatalError("无法运行 shasum：\(error)")
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let hash = String(output.prefix(64))
        precondition(hash.count == 64, "shasum 输出异常：\(output)")
        return hash
    }
}
