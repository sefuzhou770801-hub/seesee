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
    case noOp
    case failure(String)
}

struct MediaLibraryMover {
    var fileManager: FileManager = .default
    var copyItem: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }
    var defaults: UserDefaults = .standard
    var now: () -> Date = Date.init

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
        let from = source.standardizedFileURL
        let to = destination.standardizedFileURL
        if from.path == to.path {
            return .noOp
        }

        do {
            try performMove(
                from: from,
                to: to,
                dataFile: dataFile,
                items: items,
                onProgress: onProgress
            )
            return .success
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
    ) throws {
        let files = try listFiles(in: source)
        try assertNoConflicts(files: files, source: source, destination: destination)

        let destinationExisted = fileManager.fileExists(atPath: destination.path)
        var copied: [URL] = []
        var committed = false
        defer {
            if !committed {
                rollback(copied: copied, destination: destination, destinationExisted: destinationExisted)
            }
        }

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
            try copyItem(file, destFile)
            copied.append(destFile)
            onProgress?(MediaLibraryMoveProgress(completed: index + 1, total: total))
        }

        try verify(files: files, source: source, destination: destination)

        var backupURL: URL?
        if fileManager.fileExists(atPath: dataFile.path) {
            let backup = backupURLForQueue(dataFile)
            try fileManager.copyItem(at: dataFile, to: backup)
            backupURL = backup
        }

        do {
            try writeRemappedQueue(items: items, from: source, to: destination, dataFile: dataFile)
            MediaFolderPreference.save(destination, defaults: defaults)
        } catch {
            if let backupURL {
                try? fileManager.removeItem(at: dataFile)
                try? fileManager.copyItem(at: backupURL, to: dataFile)
            }
            throw error
        }

        committed = true
        deleteVerifiedSources(files)
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
            return []
        }
        guard isDirectory.boolValue else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }
        var files: [URL] = []
        for case let file as URL in enumerator {
            if file.lastPathComponent == ".DS_Store" { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values.isDirectory == true { continue }
            if values.isRegularFile == true {
                files.append(file.standardizedFileURL)
            }
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

    private func deleteVerifiedSources(_ files: [URL]) {
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private func rollback(copied: [URL], destination: URL, destinationExisted: Bool) {
        for file in copied {
            try? fileManager.removeItem(at: file)
        }
        if !destinationExisted {
            try? fileManager.removeItem(at: destination)
        }
    }
}

private struct MediaLibraryMoveFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
