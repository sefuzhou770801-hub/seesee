import Foundation

enum DigestCopy {
    static let missingKeyHint = "还没有配置 AI 密钥，配置后即可使用解释与目录。"
    static let viewConfigTitle = "打开设置…"
    static let noSubtitles = "这段没有字幕"
    static let writeFailed = "这次没写成"
    static let requestFailed = "暂时没拿到结果，请重试"
    static let saveFailed = "这次没存上，请再试一次"
    static let fileCorrupt = "这份记录损坏了，没有覆盖原文件"
    static let tocIncomplete = "目录没生成完整，请重试"
    static let missingSummaryPlaceholder = "（本章暂无概括）"
    static let emptyTitle = "暂无字幕"
    static let emptyLoadingDetail = "字幕仍在加载，或文件无法解析。"
    static let emptyUnavailableDetail = "当前视频没有可用字幕。"

    static func emptyDetail(hasSubtitleSource: Bool) -> String {
        hasSubtitleSource ? emptyLoadingDetail : emptyUnavailableDetail
    }

    static func showsBook(cueCount: Int, qaCount: Int) -> Bool {
        cueCount > 0 || qaCount > 0
    }

    static func showsDigestActions(cueCount: Int) -> Bool {
        cueCount > 0
    }
}
