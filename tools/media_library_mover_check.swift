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
