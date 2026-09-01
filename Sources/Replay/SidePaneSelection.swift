import Foundation

enum SidePaneMode: String {
    case overview
    case lyrics
    case notes

    /// 旧版把总览页存成 `chapters`，读盘时映射过来。
    static func fromPersisted(_ raw: String) -> SidePaneMode {
        switch raw {
        case overview.rawValue, "chapters":
            return .overview
        case notes.rawValue:
            return .notes
        default:
            return .lyrics
        }
    }
}

enum SidePaneSelection {
    static func openingMode(hasChapters: Bool) -> SidePaneMode {
        hasChapters ? .overview : .lyrics
    }

    static func resolvedMode(
        preferred: SidePaneMode,
        hasChapters _: Bool,
        hasSubtitles _: Bool
    ) -> SidePaneMode {
        preferred
    }

    static func recomputedMode(
        current: SidePaneMode,
        hasChapters: Bool,
        userHasManuallySwitched: Bool
    ) -> SidePaneMode {
        if userHasManuallySwitched {
            return current
        }
        return openingMode(hasChapters: hasChapters)
    }

    static func visibleTitle(for mode: SidePaneMode) -> String {
        switch mode {
        case .overview:
            return "总览"
        case .lyrics:
            return "字幕"
        case .notes:
            return "笔记"
        }
    }
}
