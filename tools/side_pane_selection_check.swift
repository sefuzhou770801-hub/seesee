import Foundation

@main
struct SidePaneSelectionCheck {
    static func main() {
        precondition(SidePaneSelection.openingMode(hasChapters: true) == .overview)
        precondition(SidePaneSelection.openingMode(hasChapters: false) == .lyrics)

        precondition(
            SidePaneSelection.resolvedMode(
                preferred: .overview,
                hasChapters: false,
                hasSubtitles: true
            ) == .overview,
            "无章节时点总览应停在总览空态，不得弹回字幕"
        )
        precondition(
            SidePaneSelection.resolvedMode(
                preferred: .lyrics,
                hasChapters: true,
                hasSubtitles: false
            ) == .lyrics,
            "无字幕时点字幕应停在字幕空态，不得弹回总览"
        )
        precondition(
            SidePaneSelection.resolvedMode(
                preferred: .notes,
                hasChapters: false,
                hasSubtitles: false
            ) == .notes,
            "无数据时点笔记应停在笔记空态"
        )
        precondition(
            SidePaneSelection.resolvedMode(
                preferred: .overview,
                hasChapters: true,
                hasSubtitles: true
            ) == .overview
        )

        precondition(SidePaneSelection.visibleTitle(for: .overview) == "总览")
        precondition(SidePaneSelection.visibleTitle(for: .lyrics) == "字幕")
        precondition(SidePaneSelection.visibleTitle(for: .notes) == "笔记")
        precondition(SidePaneSelection.visibleTitle(for: .lyrics) != "歌词")

        precondition(SidePaneMode.fromPersisted("chapters") == .overview, "旧 chapters 键须映射到总览")
        precondition(SidePaneMode.fromPersisted("overview") == .overview)
        precondition(SidePaneMode.fromPersisted("lyrics") == .lyrics)
        precondition(SidePaneMode.fromPersisted("notes") == .notes)
        precondition(SidePaneMode.fromPersisted("unknown") == .lyrics)

        precondition(
            SidePaneSelection.recomputedMode(
                current: .lyrics,
                hasChapters: true,
                userHasManuallySwitched: false
            ) == .overview,
            "章节落地且用户未手切页签时，必须重算到总览页"
        )
        precondition(
            SidePaneSelection.recomputedMode(
                current: .lyrics,
                hasChapters: true,
                userHasManuallySwitched: true
            ) == .lyrics,
            "用户本次会话已手切页签时，不得因章节落地被强制切走"
        )
        precondition(
            SidePaneSelection.recomputedMode(
                current: .overview,
                hasChapters: false,
                userHasManuallySwitched: false
            ) == .lyrics,
            "无章节且未手切时，按有章节优先总览页重算到字幕页"
        )
        precondition(
            SidePaneSelection.recomputedMode(
                current: .overview,
                hasChapters: false,
                userHasManuallySwitched: true
            ) == .overview,
            "用户手切到总览页后，缺章节也要停在总览空态"
        )
        precondition(
            SidePaneSelection.recomputedMode(
                current: .notes,
                hasChapters: true,
                userHasManuallySwitched: true
            ) == .notes,
            "用户手切到笔记页后，章节落地不得切走"
        )
        precondition(
            SidePaneSelection.recomputedMode(
                current: .overview,
                hasChapters: true,
                userHasManuallySwitched: false
            ) == .overview
        )

        print("side_pane_selection_check=passed")
    }
}
