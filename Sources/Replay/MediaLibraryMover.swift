import CryptoKit
import Foundation
import os.log

enum MediaFolderLog {
    static let log = OSLog(subsystem: "com.mg.replay", category: "media-folder")

    static func info(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
    }

    static func error(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }
}

enum MediaLibraryMoveResult: Equatable {
    case success
    case finishedWithSourceLeftovers(String)
    case noOp
    case failure(String)
}

enum MediaFolderMoveMarker {
    static func url(beside dataFile: URL) -> URL {
        dataFile.deletingLastPathComponent().appendingPathComponent(MediaFolderCopy.inProgressMarkerName)
    }

    static func exists(beside dataFile: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url(beside: dataFile).path)
    }

    static func destination(beside dataFile: URL, fileManager: FileManager = .default) -> URL? {
        guard let text = try? String(contentsOf: url(beside: dataFile), encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("to=") else { continue }
            let path = String(line.dropFirst(3))
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    static func incompleteReason(beside dataFile: URL, fileManager: FileManager = .default) -> String {
        if let dest = destination(beside: dataFile, fileManager: fileManager) {
            return MediaFolderCopy.leftoverDestinationNeedsCleanup(dest.standardizedFileURL.path)
        }
        return MediaFolderCopy.incompleteMove
    }

    /// 偏好已经指向标记里的目标，说明上次搬移已经提交完，只是标记没清掉。
    static func isStaleCompleted(
        beside dataFile: URL,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) -> Bool {
        guard exists(beside: dataFile, fileManager: fileManager),
              let dest = destination(beside: dataFile, fileManager: fileManager),
              let saved = MediaFolderPreference.resolve(defaults: defaults) else { return false }
        return saved.standardizedFileURL.path == dest.standardizedFileURL.path
    }

    @discardableResult
    static func clearIfStaleCompleted(
        beside dataFile: URL,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isStaleCompleted(beside: dataFile, defaults: defaults, fileManager: fileManager) else {
            return false
        }
        let marker = url(beside: dataFile)
        guard fileManager.fileExists(atPath: marker.path) else { return true }
        try? fileManager.removeItem(at: marker)
        return true
    }
}

struct MediaLibraryMover {
    var fileManager: FileManager = .default
    var copyItem: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }
    var removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    var defaults: UserDefaults = .standard
    var now: () -> Date = Date.init
    var mountedVolumes: [URL] = MediaFolderAvailability.liveMountedVolumes()
    var volumesRoot: URL = MediaFolderAvailability.defaultVolumesRoot

    func move(
        from source: URL,
        to destination: URL,
        dataFile: URL,
        items: [WatchItem],
        hasActiveDownload: Bool,
        onProgress: ((MediaLibraryMoveProgress) -> Void)? = nil
    ) -> MediaLibraryMoveResult {
        if hasActiveDownload {
            return .failure(MediaFolderCopy.downloadingBlock)
        }
        if MediaFolderMoveMarker.exists(beside: dataFile, fileManager: fileManager) {
            if MediaFolderMoveMarker.clearIfStaleCompleted(
                beside: dataFile,
                defaults: defaults,
                fileManager: fileManager
            ) {
                MediaFolderLog.info("cleared stale completed move marker")
            } else {
                return .failure(MediaFolderMoveMarker.incompleteReason(beside: dataFile, fileManager: fileManager))
            }
        }
        let from = source.standardizedFileURL
        let to = destination.standardizedFileURL
        if from.path == to.path {
            return .noOp
        }
        if MediaFolderAvailability.isDisconnected(from, mountedVolumes: mountedVolumes, volumesRoot: volumesRoot) {
            return .failure(MediaFolderCopy.sourceDisconnected)
        }
        if MediaFolderAvailability.isDisconnected(to, mountedVolumes: mountedVolumes, volumesRoot: volumesRoot) {
            return .failure(MediaFolderCopy.destinationDisconnected)
        }

        do {
            switch try performMove(
                from: from,
                to: to,
                dataFile: dataFile,
                items: items,
                onProgress: onProgress
            ) {
            case .done:
                return .success
            case .doneWithSourceLeftovers(let note):
                return .finishedWithSourceLeftovers(note)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func performMove(
        from source: URL,
        to destination: URL,
        dataFile: URL,
        items: [WatchItem],
        onProgress: ((MediaLibraryMoveProgress) -> Void)?
    ) throws -> PerformOutcome {
        let marker = MediaFolderMoveMarker.url(beside: dataFile)
        try writeMarker(marker, from: source, to: destination)
        var copied: [URL] = []
        let destinationExisted = fileManager.fileExists(atPath: destination.path)
        let previousPreference = defaults.string(forKey: MediaFolderPreference.key)
        var backupURL: URL?

        do {
            let files = try listFiles(in: source)
            try assertNoConflicts(files: files, source: source, destination: destination)

            if !destinationExisted {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            }

            let total = files.count
            for (index, file) in files.enumerated() {
                let relative = relativePath(of: file, to: source)
                let destFile = destination.appendingPathComponent(relative)
                let destParent = destFile.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: destParent.path) {
                    try fileManager.createDirectory(at: destParent, withIntermediateDirectories: true)
                }
                if fileManager.fileExists(atPath: destFile.path) {
                    onProgress?(MediaLibraryMoveProgress(completed: index + 1, total: total))
                    continue
                }
                copied.append(destFile)
                try copyItem(file, destFile)
                onProgress?(MediaLibraryMoveProgress(completed: index + 1, total: total))
            }

            try verify(files: files, source: source, destination: destination)

            if fileManager.fileExists(atPath: dataFile.path) {
                let backup = backupURLForQueue(dataFile)
                try fileManager.copyItem(at: dataFile, to: backup)
                backupURL = backup
            }
            try writeRemappedQueue(items: items, from: source, to: destination, dataFile: dataFile)
            MediaFolderPreference.save(destination, defaults: defaults)

            let leftoverNames = deleteVerifiedSources(files)
            if let markerError = clearMarkerIfPossible(marker) {
                MediaFolderLog.error("move finished but marker stayed: \(markerError)")
            }
            if leftoverNames.isEmpty {
                return .done
            }
            return .doneWithSourceLeftovers(
                MediaFolderCopy.sourceLeftovers(names: leftoverNames, sourcePath: source.path)
            )
        } catch {
            var parts = [error.localizedDescription]
            if let restoreError = restoreQueue(dataFile: dataFile, backupURL: backupURL) {
                parts.append(restoreError)
            }
            restorePreference(previousPreference)
            let rollbackError = rollback(copied: copied, destination: destination, destinationExisted: destinationExisted)
            if let rollbackError {
                parts.append(rollbackError)
            }
            let destDirty = rollbackError != nil
                || copied.contains { fileManager.fileExists(atPath: $0.path) }
            if destDirty {
                throw MediaLibraryMoveFailure(
                    MediaFolderCopy.rollbackLeftResidue(
                        path: destination.path,
                        reason: parts.joined(separator: "；")
                    )
                )
            }
            if let markerError = clearMarkerIfPossible(marker) {
                parts.append(markerError)
            }
            throw MediaLibraryMoveFailure(parts.joined(separator: "；"))
        }
    }

    private func assertNoConflicts(files: [URL], source: URL, destination: URL) throws {
        for file in files {
            let destFile = destination.appendingPathComponent(relativePath(of: file, to: source))
            guard fileManager.fileExists(atPath: destFile.path) else { continue }
            if try !sameContent(file, destFile) {
                throw MediaLibraryMoveFailure(
                    "目标目录已有同名文件，内容不同，没有覆盖：\(destFile.lastPathComponent)"
                )
            }
        }
    }

    private func verify(files: [URL], source: URL, destination: URL) throws {
        for file in files {
            let destFile = destination.appendingPathComponent(relativePath(of: file, to: source))
            guard fileManager.fileExists(atPath: destFile.path) else {
                throw MediaLibraryMoveFailure("核对失败，目标缺少 \(file.lastPathComponent)")
            }
            if try !sameContent(file, destFile) {
                throw MediaLibraryMoveFailure("核对失败，\(file.lastPathComponent) 复制后内容不一致")
            }
        }
    }

    private func sameContent(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let leftSize = try fileSize(lhs)
        let rightSize = try fileSize(rhs)
        guard leftSize == rightSize else { return false }
        return try sha256(lhs) == sha256(rhs)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            return UInt64(size)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw MediaLibraryMoveFailure("读不到文件大小：\(url.lastPathComponent)")
        }
        return size.uint64Value
    }

    private func sha256(_ url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func listFiles(in root: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw MediaLibraryMoveFailure("源目录不存在，无法搬移")
        }
        guard isDirectory.boolValue else {
            throw MediaLibraryMoveFailure("源路径不是目录，无法搬移")
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            throw MediaLibraryMoveFailure("枚举源目录失败：没有读取权限")
        }
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw MediaLibraryMoveFailure("无法枚举源目录")
        }
        var files: [URL] = []
        for case let file as URL in enumerator {
            if let enumerationError {
                throw MediaLibraryMoveFailure("枚举源目录失败：\(enumerationError.localizedDescription)")
            }
            if file.lastPathComponent == ".DS_Store" { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values.isDirectory == true { continue }
            if values.isRegularFile == true {
                files.append(file.standardizedFileURL)
            }
        }
        if let enumerationError {
            throw MediaLibraryMoveFailure("枚举源目录失败：\(enumerationError.localizedDescription)")
        }
        return files
    }

    private func relativePath(of file: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return file.lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }

    private func backupURLForQueue(_ dataFile: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        return dataFile.deletingLastPathComponent()
            .appendingPathComponent("queue.json.bak-\(stamp)")
    }

    private func writeRemappedQueue(
        items: [WatchItem],
        from source: URL,
        to destination: URL,
        dataFile: URL
    ) throws {
        let remap = ReplayMigrationResult(
            applicationSupport: dataFile.deletingLastPathComponent(),
            mediaFolder: destination,
            movedFromMediaFolder: source
        )
        var remapped = items
        for index in remapped.indices {
            remapped[index].localFilePath = remap.remappedMediaPath(remapped[index].localFilePath)
            remapped[index].thumbnailFilePath = remap.remappedMediaPath(remapped[index].thumbnailFilePath)
            remapped[index].subtitleFilePath = remap.remappedMediaPath(remapped[index].subtitleFilePath)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(remapped)
        try data.write(to: dataFile, options: .atomic)
    }

    private func deleteVerifiedSources(_ files: [URL]) -> [String] {
        var leftovers: [String] = []
        for file in files {
            do {
                try removeItem(file)
            } catch {
                leftovers.append(file.lastPathComponent)
            }
        }
        return leftovers
    }

    private func rollback(copied: [URL], destination: URL, destinationExisted: Bool) -> String? {
        var failures: [String] = []
        for file in copied {
            guard fileManager.fileExists(atPath: file.path) else { continue }
            do {
                try removeItem(file)
            } catch {
                failures.append("\(file.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if !destinationExisted, fileManager.fileExists(atPath: destination.path) {
            do {
                try removeItem(destination)
            } catch {
                failures.append("目标目录：\(error.localizedDescription)")
            }
        }
        guard !failures.isEmpty else { return nil }
        return "回滚目标文件没有完成：\(failures.joined(separator: "；"))"
    }

    private func writeMarker(_ marker: URL, from source: URL, to destination: URL) throws {
        let body = "from=\(source.path)\nto=\(destination.path)\n"
        try Data(body.utf8).write(to: marker, options: .atomic)
    }

    private func clearMarker(_ marker: URL) throws {
        guard fileManager.fileExists(atPath: marker.path) else { return }
        try removeItem(marker)
    }

    private func clearMarkerIfPossible(_ marker: URL) -> String? {
        do {
            try clearMarker(marker)
            return nil
        } catch {
            return "未能清除进行中标记：\(error.localizedDescription)"
        }
    }

    private func restoreQueue(dataFile: URL, backupURL: URL?) -> String? {
        guard let backupURL, fileManager.fileExists(atPath: backupURL.path) else { return nil }
        do {
            if fileManager.fileExists(atPath: dataFile.path) {
                try removeItem(dataFile)
            }
            try fileManager.copyItem(at: backupURL, to: dataFile)
            return nil
        } catch {
            return "恢复 queue.json 没有完成：\(error.localizedDescription)"
        }
    }

    private func restorePreference(_ previous: String?) {
        if let previous {
            defaults.set(previous, forKey: MediaFolderPreference.key)
        } else {
            defaults.removeObject(forKey: MediaFolderPreference.key)
        }
    }
}

private enum PerformOutcome {
    case done
    case doneWithSourceLeftovers(String)
}

private struct MediaLibraryMoveFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
