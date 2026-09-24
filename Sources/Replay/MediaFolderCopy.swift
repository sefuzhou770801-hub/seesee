import Foundation

enum MediaFolderCopy {
    static let disconnected = "存放位置未连接"
    static let changeButton = "更改…"
    static let downloadingBlock = "有视频正在下载，下载完成后再更改存放位置"

    static func progress(completed: Int, total: Int) -> String {
        "正在搬移视频（已完成 \(completed) / \(total)）"
    }

    static func failure(_ reason: String) -> String {
        "搬移没有完成，原来的视频都还在：\(reason)"
    }
}

struct MediaLibraryMoveProgress: Equatable {
    var completed: Int
    var total: Int

    var text: String {
        MediaFolderCopy.progress(completed: completed, total: total)
    }
}
