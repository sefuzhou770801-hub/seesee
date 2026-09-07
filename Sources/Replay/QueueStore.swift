import AppKit
import Foundation

private final class QueuePersistenceWriter {
    private let dataFile: URL
    private let queue = DispatchQueue(label: "com.mg.replay.persistence", qos: .utility)
    private var pendingItems: [WatchItem]?
    private var pendingWork: DispatchWorkItem?

    init(dataFile: URL) {
        self.dataFile = dataFile
    }

    func schedule(_ items: [WatchItem]) {
        queue.async { [weak self] in
            guard let self else { return }
            pendingItems = items
            pendingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.writePendingItems()
            }
            pendingWork = work
            queue.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    func flush(_ items: [WatchItem]) {
        queue.sync {
            pendingWork?.cancel()
            pendingWork = nil
            pendingItems = items
            writePendingItems()
        }
    }

    private func writePendingItems() {
        guard let items = pendingItems else { return }
        pendingItems = nil
        pendingWork = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: dataFile, options: .atomic)
    }
}

@MainActor
final class QueueStore: ObservableObject {
    private enum AddDisposition {
        case added
        case existing
    }

    struct IntakeNotice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let detail: String
        let systemImage: String
    }

    @Published private(set) var items: [WatchItem] = []
    @Published var selection: UUID?
    @Published var lastIntakeError: String?
    @Published private(set) var intakeNotice: IntakeNotice?

    private let downloader = DownloadEngine()
    private let networkMonitor = NetworkMonitor()
    private let powerMonitor = PowerModeMonitor()
    private let maximumConcurrentDownloads = 3
    private let dataFile: URL
    private let persistenceWriter: QueuePersistenceWriter
    private var metadataRefreshes: Set<UUID> = []
    private var thumbnailRefreshes: Set<UUID> = []
    private var subtitleRefreshes: Set<UUID> = []
    private var noticeDismissal: Task<Void, Never>?
    private var retryAttempts: [UUID: Int] = [:]
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var waitingForNetwork: Set<UUID> = []
    private var waitingForPower: Set<UUID> = []
    private var powerCancellationIDs: Set<UUID> = []
    let mediaFolder: URL

    init() {
        let fileManager = FileManager.default
        let applicationSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let moviesRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
        let migration = ReplayMigration.migrateDirectories(
            fileManager: fileManager,
            applicationSupportRoot: applicationSupportRoot,
            moviesRoot: moviesRoot
        )
        ReplayMigration.migratePreferences()

        let applicationSupport = migration.applicationSupport
        dataFile = applicationSupport.appendingPathComponent("queue.json")
        persistenceWriter = QueuePersistenceWriter(dataFile: dataFile)
        mediaFolder = migration.mediaFolder
        try? fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        load()
        migrateQueueToNewestFirstIfNeeded()

        if migration.didMoveMediaFolder {
            for index in items.indices {
                items[index].localFilePath = migration.remappedMediaPath(items[index].localFilePath)
                items[index].thumbnailFilePath = migration.remappedMediaPath(items[index].thumbnailFilePath)
                items[index].subtitleFilePath = migration.remappedMediaPath(items[index].subtitleFilePath)
            }
        }

        for index in items.indices where items[index].state == .downloading {
            items[index].state = .queued
            items[index].progressLabel = "等待恢复"
        }
        save()
        selection = queueItems.first?.id ?? archivedItems.first?.id

        wireMonitors()
    }

    /// 测试用最小注入初始化：直接指定数据文件与媒体目录，跳过目录迁移与监控接线，
    /// 便于在隔离目录里通过真实 `remove()` 验证删除接线。生产一律走无参 `init()`。
    init(dataFile: URL, mediaFolder: URL) {
        self.dataFile = dataFile
        self.persistenceWriter = QueuePersistenceWriter(dataFile: dataFile)
        self.mediaFolder = mediaFolder
        try? FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        load()
    }

    private func wireMonitors() {
        networkMonitor.onBecameOnline = { [weak self] in
            self?.resumeWaitingDownloads()
        }
        networkMonitor.start()
        powerMonitor.onChange = { [weak self] enabled in
            if enabled {
                self?.pauseDownloadsForLowPowerMode()
            } else {
                self?.resumePowerPausedDownloads()
            }
        }
        powerMonitor.start()

        let resumable = items.filter { $0.state == .queued }.map(\.id)
        let missingChapterMetadata = items.filter { $0.state == .ready && $0.chapters == nil }.map(\.id)
        let missingThumbnails = items.filter { $0.state == .ready && $0.thumbnailFilePath == nil }.map(\.id)
        let missingSubtitles = items.filter { $0.state == .ready && $0.subtitleFilePath == nil }.map(\.id)
        DispatchQueue.main.async { [weak self] in
            resumable.forEach { self?.startDownload(for: $0) }
            missingChapterMetadata.forEach { self?.refreshChapterMetadata(for: $0) }
            missingThumbnails.forEach { self?.refreshThumbnail(for: $0) }
            missingSubtitles.forEach { self?.refreshSubtitle(for: $0) }
        }
    }

    var queueItems: [WatchItem] {
        items.filter { !$0.isWatched }
    }

    var archivedItems: [WatchItem] {
        items
            .filter(\.isWatched)
            .sorted { ($0.watchedAt ?? $0.addedAt) > ($1.watchedAt ?? $1.addedAt) }
    }

    var selectedItem: WatchItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    func accept(_ incoming: URL) {
        guard let webURL = URLIntake.resolve(incoming) else {
            lastIntakeError = "拖入的内容里没有网页链接。"
            return
        }
        add(webURL)
    }

    func accept(rawValue: String) {
        let urls = URLIntake.webURLs(from: rawValue)
        guard !urls.isEmpty else {
            lastIntakeError = "这段文字里没有找到 HTTP 或 HTTPS 链接。"
            return
        }
        guard urls.count > 1 else {
            add(urls[0])
            return
        }

        var addedCount = 0
        var existingCount = 0
        for url in urls {
            switch add(url, showsNotice: false, activatesApp: false) {
            case .added: addedCount += 1
            case .existing: existingCount += 1
            }
        }
        lastIntakeError = nil

        if addedCount > 0 {
            let duplicateDetail = existingCount > 0 ? " · \(existingCount) 个已在待播清单中" : ""
            let detail: String
            let systemImage: String
            if powerMonitor.isLowPowerModeEnabled {
                detail = "已排队，等低电量模式关闭后开始\(duplicateDetail)"
                systemImage = "battery.25"
            } else if networkMonitor.isOnline {
                detail = "已加入下载队列\(duplicateDetail)"
                systemImage = "arrow.down.circle.fill"
            } else {
                detail = "等待网络连接\(duplicateDetail)"
                systemImage = "wifi.slash"
            }
            showIntakeNotice(
                title: "已加入 \(addedCount) 个视频",
                detail: detail,
                systemImage: systemImage
            )
        } else {
            showIntakeNotice(
                title: "已在队列中",
                detail: "粘贴的 \(existingCount) 个链接都已在待播清单中",
                systemImage: "checkmark.circle.fill"
            )
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    private func add(
        _ url: URL,
        showsNotice: Bool = true,
        activatesApp: Bool = true
    ) -> AddDisposition {
        let canonical = URLIntake.canonicalString(for: url)
        if let existing = items.first(where: { $0.urlString == canonical }) {
            selection = existing.id
            if existing.state == .failed || existing.state == .queued { startDownload(for: existing.id) }
            if showsNotice {
                let detail = existing.state == .failed || existing.state == .queued
                    ? "正在重试 \(existing.title)"
                    : "\(existing.title) 已经保存过了"
                showIntakeNotice(
                    title: "已在队列中",
                    detail: detail,
                    systemImage: "checkmark.circle.fill"
                )
            }
            if activatesApp { NSApp.activate(ignoringOtherApps: true) }
            return .existing
        }

        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "视频"
        let item = WatchItem(
            id: UUID(),
            urlString: canonical,
            title: host,
            author: "",
            duration: nil,
            addedAt: Date(),
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
        items.insert(item, at: 0)
        selection = item.id
        lastIntakeError = nil
        save()
        startDownload(for: item.id)
        let current = self.item(with: item.id)
        let isPowerPaused = current?.progressLabel == "低电量模式已暂停"
        let isOnline = networkMonitor.isOnline
        if showsNotice {
            showIntakeNotice(
                title: "已加入队列",
                detail: isPowerPaused
                    ? "低电量模式开启中，已暂停"
                    : (isOnline ? "正在下载 \(item.title)" : "等待网络连接"),
                systemImage: isPowerPaused ? "battery.25" : (isOnline ? "arrow.down.circle.fill" : "wifi.slash")
            )
        }
        if activatesApp { NSApp.activate(ignoringOtherApps: true) }
        return .added
    }

    func dismissIntakeNotice() {
        noticeDismissal?.cancel()
        noticeDismissal = nil
        intakeNotice = nil
    }

    func startDownload(for id: UUID) {
        guard let item = item(with: id), item.state != .downloading else { return }
        retryTasks[id]?.cancel()
        retryTasks[id] = nil
        retryAttempts[id] = 0
        waitingForNetwork.remove(id)
        waitingForPower.remove(id)
        guard !powerMonitor.isLowPowerModeEnabled else {
            waitForPower(id)
            return
        }
        guard networkMonitor.isOnline else {
            waitForConnection(id, message: item.errorMessage)
            return
        }
        let isRetry = item.progress > 0 || item.errorMessage != nil || item.progressLabel != "排队中"
        beginDownload(for: id, isRetry: isRetry)
    }

    private func beginDownload(for id: UUID, isRetry: Bool) {
        if powerMonitor.isLowPowerModeEnabled {
            waitForPower(id)
            return
        }
        guard let item = item(with: id), item.state != .downloading,
              let url = URL(string: item.urlString) else { return }
        guard activeDownloadCount < maximumConcurrentDownloads else {
            update(id) {
                $0.state = .queued
                $0.progressLabel = "等待下载槽位"
            }
            save()
            return
        }
        update(id) {
            $0.state = .downloading
            $0.progressLabel = isRetry ? "继续下载…" : "准备下载…"
            $0.errorMessage = nil
        }
        save()

        downloader.start(
            itemID: id,
            sourceURL: url,
            destination: mediaFolder,
            onEvent: { [weak self] event in
                DispatchQueue.main.async { self?.handle(event, for: id) }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async { self?.finish(result, for: id) }
            }
        )
    }

    func toggleWatched(_ id: UUID) {
        update(id) {
            $0.watchedAt = $0.isWatched ? nil : Date()
            if $0.isWatched { $0.playbackPosition = nil }
        }
        save()
    }

    func markWatched(_ id: UUID) {
        update(id) {
            if $0.watchedAt == nil { $0.watchedAt = Date() }
            $0.playbackPosition = nil
        }
        save()
    }

    func updatePlaybackPosition(_ seconds: Double, for id: UUID) {
        guard seconds.isFinite, seconds >= 0, let existing = item(with: id) else { return }
        let position = seconds < 3 ? nil : seconds
        if abs((existing.playbackPosition ?? 0) - (position ?? 0)) < 1 { return }
        update(id) { $0.playbackPosition = position }
        save()
    }

    func rename(_ id: UUID, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, item(with: id)?.title != title else { return }
        update(id) { $0.title = title }
        save()
    }

    func reorderQueueItem(_ draggedID: UUID, relativeTo targetID: UUID, insertAfter: Bool) {
        var reorderedQueue = queueItems
        guard draggedID != targetID,
              let sourceIndex = reorderedQueue.firstIndex(where: { $0.id == draggedID }),
              reorderedQueue.contains(where: { $0.id == targetID }) else { return }
        let originalOrder = reorderedQueue.map(\.id)

        let draggedItem = reorderedQueue.remove(at: sourceIndex)
        guard let targetIndex = reorderedQueue.firstIndex(where: { $0.id == targetID }) else { return }
        let insertionIndex = min(targetIndex + (insertAfter ? 1 : 0), reorderedQueue.endIndex)
        reorderedQueue.insert(draggedItem, at: insertionIndex)
        guard reorderedQueue.map(\.id) != originalOrder else { return }

        var reorderedIterator = reorderedQueue.makeIterator()
        items = items.map { item in
            guard !item.isWatched else { return item }
            return reorderedIterator.next() ?? item
        }
        save()
    }

    func refreshChapterMetadata(for id: UUID) {
        guard !metadataRefreshes.contains(id),
              let existing = item(with: id),
              existing.state == .ready,
              existing.chapters == nil,
              let url = URL(string: existing.urlString) else { return }
        metadataRefreshes.insert(id)
        downloader.fetchMetadata(sourceURL: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.metadataRefreshes.remove(id)
                guard case .success(let metadata) = result else { return }
                self.update(id) {
                    if !metadata.title.isEmpty { $0.title = metadata.title }
                    $0.author = metadata.author
                    $0.duration = metadata.duration
                    $0.chapters = metadata.chapters
                }
                self.save()
            }
        }
    }

    func refreshThumbnail(for id: UUID) {
        guard !thumbnailRefreshes.contains(id),
              let existing = item(with: id),
              existing.state == .ready,
              existing.thumbnailFilePath == nil,
              let url = URL(string: existing.urlString) else { return }
        thumbnailRefreshes.insert(id)
        downloader.fetchThumbnail(
            itemID: id,
            sourceURL: url,
            destination: mediaFolder
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.thumbnailRefreshes.remove(id)
                guard case .success(let thumbnailURL) = result else { return }
                self.update(id) { $0.thumbnailFilePath = thumbnailURL?.path ?? "" }
                self.save()
            }
        }
    }

    func refreshSubtitle(for id: UUID) {
        guard !subtitleRefreshes.contains(id),
              let existing = item(with: id),
              existing.state == .ready,
              existing.subtitleFilePath == nil,
              let url = URL(string: existing.urlString) else { return }
        subtitleRefreshes.insert(id)
        downloader.fetchSubtitle(
            itemID: id,
            sourceURL: url,
            destination: mediaFolder
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.subtitleRefreshes.remove(id)
                guard case .success(let subtitleURL) = result else { return }
                self.update(id) { $0.subtitleFilePath = subtitleURL?.path ?? "" }
                self.save()
            }
        }
    }

    /// 播放时重扫本地字幕：发现 agent 后补的高 rank 文件并热切换。
    /// 不 guard subtitleFilePath == nil（该字段无字幕时写 ""，nil 判断永不命中）。
    /// 扫描结果与现值相同则不写不 save（幂等）。找不到字幕写 ""，严禁回写 nil。
    /// - Parameter completion: 主线程回调扫描后的有效路径（含幂等未变时），供当前界面立即重载字幕。
    func rescanLocalSubtitle(for id: UUID, completion: ((String) -> Void)? = nil) {
        guard let existing = item(with: id) else { return }
        guard existing.state == .ready else {
            completion?(existing.subtitleFilePath ?? "")
            return
        }
        downloader.discoverLocalSubtitle(itemID: id, in: mediaFolder) { [weak self] subtitleURL in
            DispatchQueue.main.async {
                guard let self else { return }
                // 与 refreshSubtitle / 下载完成路径一致：找不到写空字符串，不写 nil
                let newPath = subtitleURL?.path ?? ""
                if let current = self.item(with: id), current.subtitleFilePath != newPath {
                    self.update(id) { $0.subtitleFilePath = newPath }
                    self.save()
                }
                // 无论是否落盘，都把扫描结果交给 UI，避免依赖 onChange（item 值可能未刷新）
                completion?(newPath)
            }
        }
    }

    func remove(_ id: UUID, deleteMedia: Bool = true) {
        cancelRecovery(for: id)
        downloader.cancel(itemID: id)
        if deleteMedia {
            deleteLocalFiles(for: id)
        }
        items.removeAll { $0.id == id }
        save()
        if selection == id {
            selection = queueItems.first?.id ?? archivedItems.first?.id
        }
    }

    /// 删除该视频的全部本地文件（视频、字幕、缩略图、qa sidecar、批注 sidecar、目录 sidecar）。删除协调分两手：
    /// (1) 串行 actor 打进程内删除标记并删 qa.json，丢弃流式完成的在途/后续追加，防止复活成孤儿；
    /// (2) 同步前缀扫描立即删除全部 <uuid>.* 文件（含 qa.json），保证进程即使随后退出也不留孤儿。
    /// 两者对 qa.json 是幂等重复删除；标记保证追加不会在删除之后再复活文件。
    private func deleteLocalFiles(for id: UUID) {
        let folder = mediaFolder
        Task { await WatchQAStore.shared.deleteSidecar(WatchQASidecar(itemID: id, folder: folder)) }
        let prefix = id.uuidString + "."
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func openOriginal(_ id: UUID) {
        guard let value = item(with: id)?.urlString, let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealMediaFolder() {
        NSWorkspace.shared.open(mediaFolder)
    }

    func revealLocalFile(_ id: UUID) {
        guard let path = QueueRowMeta.localFileToReveal(
            path: item(with: id)?.localFilePath,
            exists: { FileManager.default.fileExists(atPath: $0) }
        ) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func migrateQueueToNewestFirstIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: QueueOrderPolicy.versionDefaultsKey) < QueueOrderPolicy.currentVersion else {
            return
        }
        items = QueueOrderPolicy.newestFirst(items)
        defaults.set(QueueOrderPolicy.currentVersion, forKey: QueueOrderPolicy.versionDefaultsKey)
    }

    private func handle(_ event: DownloadEngine.Event, for id: UUID) {
        switch event {
        case .metadata(let metadata):
            update(id) {
                $0.title = metadata.title.isEmpty ? $0.title : metadata.title
                $0.author = metadata.author
                $0.duration = metadata.duration
                $0.chapters = metadata.chapters
            }
            save()
        case .progress(let progress, let label):
            update(id) {
                $0.progress = progress
                $0.progressLabel = label.isEmpty ? "下载中…" : label
            }
        }
    }

    private func finish(_ result: Result<DownloadEngine.Result, Error>, for id: UUID) {
        defer { startWaitingDownloadsIfPossible() }
        switch result {
        case .success(let downloaded):
            cancelRecovery(for: id)
            update(id) {
                $0.title = downloaded.metadata.title.isEmpty ? $0.title : downloaded.metadata.title
                $0.author = downloaded.metadata.author
                $0.duration = downloaded.metadata.duration
                $0.chapters = downloaded.metadata.chapters
                $0.localFilePath = downloaded.fileURL.path
                $0.thumbnailFilePath = downloaded.thumbnailFileURL?.path ?? ""
                $0.subtitleFilePath = downloaded.subtitleFileURL?.path ?? ""
                $0.state = .ready
                $0.progress = 1
                $0.progressLabel = "已下载"
                $0.errorMessage = nil
            }
            save()
        case .failure(let error):
            if powerCancellationIDs.remove(id) != nil {
                if powerMonitor.isLowPowerModeEnabled {
                    waitForPower(id, showNotice: false)
                } else if networkMonitor.isOnline {
                    waitingForPower.remove(id)
                    retryAttempts[id] = 0
                    beginDownload(for: id, isRetry: true)
                } else {
                    waitingForPower.remove(id)
                    waitForConnection(id, message: error.localizedDescription)
                }
                return
            }
            handleDownloadFailure(error, for: id)
        }
    }

    private func handleDownloadFailure(_ error: Error, for id: UUID) {
        guard item(with: id) != nil else { return }
        let message = error.localizedDescription
        let networkFailure = DownloadRetryPolicy.isNetworkFailure(
            message: message,
            isOnline: networkMonitor.isOnline
        )
        if networkFailure && !networkMonitor.isOnline {
            waitForConnection(id, message: message)
            return
        }
        scheduleRetry(for: id, message: message)
    }

    private func scheduleRetry(for id: UUID, message: String) {
        let usedRetries = retryAttempts[id] ?? 0
        guard usedRetries < DownloadRetryPolicy.maximumRetries else {
            update(id) {
                $0.state = .failed
                $0.progressLabel = "重试 3 次后失败"
                $0.errorMessage = message
            }
            save()
            return
        }

        let attempt = usedRetries + 1
        let delay = DownloadRetryPolicy.delaySeconds(forRetry: attempt)
        retryAttempts[id] = attempt
        update(id) {
            $0.state = .queued
            $0.progressLabel = "第 \(attempt)/\(DownloadRetryPolicy.maximumRetries) 次重试，\(delay) 秒后"
            $0.errorMessage = message
        }
        save()

        retryTasks[id]?.cancel()
        retryTasks[id] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.retryTasks[id] = nil
            guard !self.powerMonitor.isLowPowerModeEnabled else {
                self.waitForPower(id)
                return
            }
            guard self.networkMonitor.isOnline else {
                self.waitForConnection(id, message: message)
                return
            }
            self.beginDownload(for: id, isRetry: true)
        }
    }

    private func waitForConnection(_ id: UUID, message: String?) {
        guard item(with: id) != nil else { return }
        let wasWaiting = waitingForNetwork.contains(id)
        retryTasks[id]?.cancel()
        retryTasks[id] = nil
        waitingForNetwork.insert(id)
        update(id) {
            $0.state = .queued
            $0.progressLabel = "等待网络连接"
            $0.errorMessage = message
        }
        save()
        if !wasWaiting {
            showIntakeNotice(
                title: "下载已暂停",
                detail: "等待网络连接",
                systemImage: "wifi.slash"
            )
        }
    }

    private func resumeWaitingDownloads() {
        let persisted = items
            .filter { $0.state == .queued && $0.progressLabel == "等待网络连接" }
            .map(\.id)
        let ids = waitingForNetwork.union(persisted)
        guard !ids.isEmpty else { return }

        if powerMonitor.isLowPowerModeEnabled {
            for id in ids {
                waitingForNetwork.remove(id)
                retryAttempts[id] = 0
                waitForPower(id, showNotice: false)
            }
            showIntakeNotice(
                title: "网络已恢复",
                detail: "低电量模式下下载仍保持暂停",
                systemImage: "battery.25"
            )
            return
        }

        showIntakeNotice(
            title: "网络已恢复",
            detail: ids.count == 1 ? "继续下载" : "继续下载 \(ids.count) 个视频",
            systemImage: "wifi"
        )
        for id in ids {
            waitingForNetwork.remove(id)
            retryAttempts[id] = 0
            beginDownload(for: id, isRetry: true)
        }
    }

    private func waitForPower(_ id: UUID, showNotice: Bool = true) {
        guard item(with: id) != nil else { return }
        let wasWaiting = waitingForPower.contains(id)
        retryTasks[id]?.cancel()
        retryTasks[id] = nil
        waitingForPower.insert(id)
        update(id) {
            $0.state = .queued
            $0.progressLabel = "低电量模式已暂停"
        }
        save()
        if showNotice && !wasWaiting {
            showIntakeNotice(
                title: "下载已暂停",
                detail: "低电量模式已开启",
                systemImage: "battery.25"
            )
        }
    }

    private func pauseDownloadsForLowPowerMode() {
        let activeIDs = items.filter { $0.state == .downloading }.map(\.id)
        let retryIDs = Set(retryTasks.keys)
        let affected = Set(activeIDs).union(retryIDs)
        guard !affected.isEmpty else { return }

        for id in activeIDs {
            powerCancellationIDs.insert(id)
            waitForPower(id, showNotice: false)
            downloader.cancel(itemID: id)
        }
        for id in retryIDs where !activeIDs.contains(id) {
            waitForPower(id, showNotice: false)
        }
        showIntakeNotice(
            title: "下载已暂停",
            detail: "低电量模式已开启",
            systemImage: "battery.25"
        )
    }

    private func resumePowerPausedDownloads() {
        let persisted = items
            .filter { $0.state == .queued && $0.progressLabel == "低电量模式已暂停" }
            .map(\.id)
        let ids = waitingForPower.union(persisted)
        guard !ids.isEmpty else { return }

        if networkMonitor.isOnline {
            showIntakeNotice(
                title: "低电量模式已关闭",
                detail: ids.count == 1 ? "继续下载" : "继续下载 \(ids.count) 个视频",
                systemImage: "bolt.fill"
            )
            for id in ids {
                guard !powerCancellationIDs.contains(id) else { continue }
                waitingForPower.remove(id)
                retryAttempts[id] = 0
                beginDownload(for: id, isRetry: true)
            }
        } else {
            for id in ids {
                waitingForPower.remove(id)
                waitForConnection(id, message: item(with: id)?.errorMessage)
            }
        }
    }

    private func cancelRecovery(for id: UUID) {
        retryTasks[id]?.cancel()
        retryTasks[id] = nil
        retryAttempts.removeValue(forKey: id)
        waitingForNetwork.remove(id)
        waitingForPower.remove(id)
        powerCancellationIDs.remove(id)
    }

    private var activeDownloadCount: Int {
        items.lazy.filter { $0.state == .downloading }.count
    }

    private func startWaitingDownloadsIfPossible() {
        guard networkMonitor.isOnline, !powerMonitor.isLowPowerModeEnabled else { return }
        let availableSlots = maximumConcurrentDownloads - activeDownloadCount
        guard availableSlots > 0 else { return }

        let waiting = items
            .filter { $0.state == .queued && $0.progressLabel == "等待下载槽位" }
            .sorted { $0.addedAt < $1.addedAt }
            .prefix(availableSlots)
        for item in waiting {
            let isRetry = item.progress > 0 || item.errorMessage != nil
            beginDownload(for: item.id, isRetry: isRetry)
        }
    }

    private func item(with id: UUID) -> WatchItem? {
        items.first { $0.id == id }
    }

    private func update(_ id: UUID, change: (inout WatchItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func showIntakeNotice(title: String, detail: String, systemImage: String) {
        noticeDismissal?.cancel()
        let notice = IntakeNotice(title: title, detail: detail, systemImage: systemImage)
        intakeNotice = notice
        noticeDismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, self?.intakeNotice?.id == notice.id else { return }
            self?.intakeNotice = nil
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([WatchItem].self, from: data)) ?? []
    }

    private func save() {
        persistenceWriter.schedule(items)
    }

    func flushPendingSaves() {
        persistenceWriter.flush(items)
    }
}
