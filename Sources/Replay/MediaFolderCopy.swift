import Foundation

enum MediaFolderCopy {
    static let disconnected = "存放位置未连接"
    static let changeButton = "更改…"
    static let downloadingBlock = "有视频正在下载，下载完成后再更改存放位置"
    static let sourceDisconnected = "片库存放位置未连接，无法搬移"
    static let destinationDisconnected = "目标存放位置未连接"
    static let incompleteMove = "上次搬移未完成"
    static let inProgressMarkerName = "media-folder-move.inprogress"
    static let needsManualCleanup = "需要手动清理"

    static func progress(completed: Int, total: Int) -> String {
        "正在搬移视频（已完成 \(completed) / \(total)）"
    }

    static func failure(_ reason: String) -> String {
        "搬移没有完成，原来的视频都还在：\(reason)"
    }

    static func leftoverDestinationNeedsCleanup(_ path: String) -> String {
        "上次搬移未完成，目标目录可能留有未清理的残余文件，\(needsManualCleanup) \(path) 才能重试"
    }

    static func rollbackLeftResidue(path: String, reason: String) -> String {
        "\(reason)。目标目录可能留有未清理的残余文件，\(needsManualCleanup) \(path) 才能重试"
    }

    static func sourceLeftovers(names: [String], sourcePath: String) -> String {
        "搬移已经完成，但有 \(names.count) 个原文件没能自动清除（\(names.joined(separator: "、"))），可以手动删除 \(sourcePath)"
    }
}

struct MediaLibraryMoveProgress: Equatable {
    var completed: Int
    var total: Int

    var text: String {
        MediaFolderCopy.progress(completed: completed, total: total)
    }
}
