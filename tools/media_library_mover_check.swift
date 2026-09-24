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
        try checkDeleteFailureIsNotSuccess()
        try checkDisconnectedDestinationDoesNotCreate()
        try checkRollbackReportsDeleteFailure()
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
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: env.source.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: env.source.path)
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

    /// 审查 3：删除源文件失败不得报成功，进行中标记必须留下。
    private static func checkDeleteFailureIsNotSuccess() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.root) }

        let video = env.source.appendingPathComponent("keep.mp4")
        try Data("video-bytes-one".utf8).write(to: video)
        var mover = MediaLibraryMover(defaults: env.defaults, now: { env.now })
        mover.removeItem = { url in
            if url.path.hasPrefix(env.source.path) {
                throw NSError(
                    domain: "media-folder-check",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "operation not permitted"]
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
            fatalError("删除失败不得报成功，实际 \(result)")
        }
        precondition(reason.contains("删除原文件没有完成"), "应报告删除失败，实际 \(reason)")
        precondition(reason.contains("operation not permitted"))
        precondition(FileManager.default.fileExists(atPath: video.path), "删除失败时源文件还在")
        precondition(FileManager.default.fileExists(atPath: env.destination.appendingPathComponent("keep.mp4").path))
        precondition(
            FileManager.default.fileExists(atPath: MediaFolderMoveMarker.url(beside: env.dataFile).path),
            "删除失败必须留下进行中标记"
        )
        precondition(env.defaults.string(forKey: MediaFolderPreference.key) == env.destination.standardizedFileURL.path)

        let blocked = MediaLibraryMover(defaults: env.defaults, now: { env.now }).move(
            from: env.source,
            to: env.root.appendingPathComponent("another", isDirectory: true),
            dataFile: env.dataFile,
            items: [],
            hasActiveDownload: false
        )
        precondition(blocked == .failure(MediaFolderCopy.incompleteMove), "有标记时拒绝新搬移，实际 \(blocked)")
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
