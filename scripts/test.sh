#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch_dir=$(mktemp -d)
trap 'rm -rf "$scratch_dir"' EXIT

# macOS 27 Command Line Tools SDK 缺 SwiftUI 宏插件时，改用相邻的 26 SDK。
if [[ -z "${SDKROOT:-}" ]]; then
    default_sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    default_sdk_version=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)
    compatibility_sdk="$(dirname "$default_sdk")/MacOSX26.sdk"
    if [[ "$default_sdk_version" == 27.* && -d "$compatibility_sdk" ]]; then
        export SDKROOT="$compatibility_sdk"
    fi
fi

compile_and_run() {
    local name="$1"
    shift
    swiftc "$@" -o "$scratch_dir/$name"
    "$scratch_dir/$name"
}

compile_and_run url_intake \
    "$project_dir/Sources/Replay/URLIntake.swift" \
    "$project_dir/tools/url_intake_check.swift"

compile_and_run retry_policy \
    "$project_dir/Sources/Replay/DownloadRetryPolicy.swift" \
    "$project_dir/tools/retry_policy_check.swift"

compile_and_run resume_model \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/tools/resume_model_check.swift"

compile_and_run subtitle_parser \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/tools/subtitle_parser_check.swift"

compile_and_run subtitle_presentation \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/tools/subtitle_presentation_check.swift"

compile_and_run subtitle_dispatch \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleDispatch.swift" \
    "$project_dir/tools/subtitle_dispatch_check.swift"

compile_and_run subtitle_overlay_layout \
    "$project_dir/Sources/Replay/SubtitleOverlayLayout.swift" \
    "$project_dir/tools/subtitle_overlay_layout_check.swift"

compile_and_run subtitle_rank \
    "$project_dir/Sources/Replay/SubtitleTrackRank.swift" \
    "$project_dir/tools/subtitle_rank_check.swift"

compile_and_run power_mode \
    "$project_dir/Sources/Replay/PowerModeMonitor.swift" \
    "$project_dir/tools/power_mode_check.swift"

compile_and_run playback_command \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleOverlayLayout.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/SubtitleDispatch.swift" \
    "$project_dir/Sources/Replay/LocalVideoPlayer.swift" \
    "$project_dir/tools/playback_command_check.swift"

compile_and_run activation_click \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/PlaybackKeyboardRouting.swift" \
    "$project_dir/Sources/Replay/PlaybackWindowFocusController.swift" \
    "$project_dir/Sources/Replay/VisualStyle.swift" \
    "$project_dir/tools/activation_click_check.swift"

compile_and_run openmy_chrome \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/tools/openmy_chrome_check.swift"

compile_and_run replay_migration \
    "$project_dir/Sources/Replay/ReplayMigration.swift" \
    "$project_dir/tools/replay_migration_check.swift"

compile_and_run queue_row_meta \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/QueueRowMeta.swift" \
    "$project_dir/tools/queue_row_meta_check.swift"

compile_and_run side_pane_selection \
    "$project_dir/Sources/Replay/SidePaneSelection.swift" \
    "$project_dir/tools/side_pane_selection_check.swift"

compile_and_run digest_search \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/tools/digest_search_check.swift"

compile_and_run digest_cue_display \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/tools/digest_cue_display_check.swift"

compile_and_run digest_typography_proof \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/tools/digest_typography_proof.swift"

compile_and_run digest_book_chrome_proof \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/tools/digest_book_chrome_proof.swift"

compile_and_run digest_jump \
    "$project_dir/Sources/Replay/DigestJumpPlayback.swift" \
    "$project_dir/tools/digest_jump_check.swift"

compile_and_run digest_notes \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/tools/digest_notes_check.swift"

compile_and_run digest_annotations \
    "$project_dir/Sources/Replay/DigestAnnotations.swift" \
    "$project_dir/tools/digest_annotations_check.swift"

compile_and_run digest_note_undo \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/tools/digest_note_undo_check.swift"

compile_and_run digest_highlight \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/tools/digest_highlight_check.swift"

compile_and_run digest_highlight_filter \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/tools/digest_highlight_filter_check.swift"

compile_and_run digest_highlight_notes_proof \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/Sources/Replay/DigestHighlightViews.swift" \
    "$project_dir/tools/digest_highlight_notes_proof.swift"

compile_and_run digest_highlight_comment_proof \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/Sources/Replay/DigestHighlightViews.swift" \
    "$project_dir/tools/digest_highlight_comment_proof.swift"

compile_and_run digest_highlight_jump_check \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/Sources/Replay/DigestHighlightViews.swift" \
    "$project_dir/tools/digest_highlight_jump_check.swift"

compile_and_run digest_hover \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/tools/digest_hover_check.swift"

compile_and_run digest_hover_probe \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/tools/digest_hover_probe_check.swift"

compile_and_run digest_hover_a11y \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/tools/digest_hover_a11y_check.swift"

compile_and_run digest_explain_quality \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/tools/digest_explain_quality_check.swift"

compile_and_run digest_overview \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/tools/digest_overview_check.swift"

compile_and_run digest_toc \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestTOC.swift" \
    "$project_dir/tools/digest_toc_check.swift"

compile_and_run digest_toc_proof \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestTOC.swift" \
    "$project_dir/Sources/Replay/DigestTOCViews.swift" \
    "$project_dir/tools/digest_toc_proof.swift"

compile_and_run digest_api \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/WatchQAContext.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestAPI.swift" \
    "$project_dir/tools/digest_api_check.swift"

compile_and_run digest_settings \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/WatchQAContext.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestAPI.swift" \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/Sources/Replay/DigestAnnotations.swift" \
    "$project_dir/Sources/Replay/DigestTOC.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/DigestSession.swift" \
    "$project_dir/Sources/Replay/DigestSettings.swift" \
    "$project_dir/tools/digest_settings_check.swift"

compile_and_run digest_settings_proof \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/WatchQAContext.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestAPI.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestSettings.swift" \
    "$project_dir/Sources/Replay/DigestSettingsView.swift" \
    "$project_dir/tools/digest_settings_proof.swift"

compile_and_run digest_session \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/WatchQAContext.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestAPI.swift" \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/Sources/Replay/DigestAnnotations.swift" \
    "$project_dir/Sources/Replay/DigestTOC.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/DigestSession.swift" \
    "$project_dir/tools/digest_session_check.swift"

compile_and_run digest_book_narrow_proof \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestOverview.swift" \
    "$project_dir/Sources/Replay/DigestTOC.swift" \
    "$project_dir/Sources/Replay/DigestTOCViews.swift" \
    "$project_dir/Sources/Replay/DigestAnnotations.swift" \
    "$project_dir/Sources/Replay/DigestAnnotationViews.swift" \
    "$project_dir/Sources/Replay/DigestNotes.swift" \
    "$project_dir/Sources/Replay/DigestNoteUndo.swift" \
    "$project_dir/Sources/Replay/DigestHighlightFilter.swift" \
    "$project_dir/Sources/Replay/DigestHighlightViews.swift" \
    "$project_dir/tools/digest_book_narrow_proof.swift"

compile_and_run digest_book_states_proof \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/DigestExplainQuality.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestCopy.swift" \
    "$project_dir/Sources/Replay/DigestSidebarViews.swift" \
    "$project_dir/Sources/Replay/DigestSettingsOpener.swift" \
    "$project_dir/tools/digest_book_states_proof.swift"

compile_and_run digest_annotation_proof \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/Sources/Replay/DigestTranscriptSearch.swift" \
    "$project_dir/Sources/Replay/DigestCueDisplay.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/DigestBookChrome.swift" \
    "$project_dir/Sources/Replay/DigestCueRow.swift" \
    "$project_dir/Sources/Replay/DigestAnnotations.swift" \
    "$project_dir/Sources/Replay/DigestAnnotationViews.swift" \
    "$project_dir/tools/digest_annotation_proof.swift"

compile_and_run player_ready \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/PlayerReadyDecision.swift" \
    "$project_dir/tools/player_ready_check.swift"

compile_and_run keyboard_routing \
    "$project_dir/Sources/Replay/PlaybackKeyboardRouting.swift" \
    "$project_dir/Sources/Replay/PlaybackWindowFocusController.swift" \
    "$project_dir/tools/keyboard_routing_check.swift"

compile_and_run digest_keyboard \
    "$project_dir/Sources/Replay/PlaybackKeyboardRouting.swift" \
    "$project_dir/Sources/Replay/DigestKeyboardRouting.swift" \
    "$project_dir/tools/digest_keyboard_check.swift"

compile_and_run sidebar_hittest \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/SidebarQueueLayout.swift" \
    "$project_dir/tools/sidebar_hittest_check.swift"

# 窄窗滑出左栏：挂载真实 ContentView，排除带 @main 的 ReplayApp。
sidebar_slideout_sources=()
while IFS= read -r file; do
    sidebar_slideout_sources+=("$file")
done < <(find "$project_dir/Sources/Replay" -name '*.swift' ! -name 'ReplayApp.swift' | sort)
compile_and_run sidebar_slideout \
    -parse-as-library \
    "${sidebar_slideout_sources[@]}" \
    "$project_dir/tools/sidebar_slideout_check.swift"

compile_and_run subtitle_blocks \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleSentenceBlocks.swift" \
    "$project_dir/tools/subtitle_blocks_check.swift"

compile_and_run qa_context \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/WatchQAContext.swift" \
    "$project_dir/tools/qa_context_check.swift"

compile_and_run qa_store \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/WatchQAStore.swift" \
    "$project_dir/tools/qa_store_check.swift"

# 生产事件链：真实 WatchQAClient.stream（注入 mock session）与真实 WatchQASession.submit
# （截帧 + 流式 + 落盘 + onPersisted 分支）。以替身替代 LocalVideoPlayer，避免拖入其重依赖。
compile_and_run qa_session \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/OpenMyChrome.swift" \
    "$project_dir/Sources/Replay/WatchQAContext.swift" \
    "$project_dir/Sources/Replay/WatchQAStore.swift" \
    "$project_dir/Sources/Replay/WatchQASession.swift" \
    "$project_dir/tools/qa_session_check.swift"

# 删除接线：经真实生产入口 QueueStore.remove（注入隔离目录）验证 qa sidecar 一并清掉。
compile_and_run qa_remove \
    "$project_dir/Sources/Replay/WatchItem.swift" \
    "$project_dir/Sources/Replay/ChapterMetadata.swift" \
    "$project_dir/Sources/Replay/VideoSubtitles.swift" \
    "$project_dir/Sources/Replay/SubtitleTrackRank.swift" \
    "$project_dir/Sources/Replay/NetworkMonitor.swift" \
    "$project_dir/Sources/Replay/PowerModeMonitor.swift" \
    "$project_dir/Sources/Replay/ReplayMigration.swift" \
    "$project_dir/Sources/Replay/QueueRowMeta.swift" \
    "$project_dir/Sources/Replay/URLIntake.swift" \
    "$project_dir/Sources/Replay/DownloadRetryPolicy.swift" \
    "$project_dir/Sources/Replay/DownloadEngine.swift" \
    "$project_dir/Sources/Replay/WatchQAStore.swift" \
    "$project_dir/Sources/Replay/DigestAnnotations.swift" \
    "$project_dir/Sources/Replay/QueueStore.swift" \
    "$project_dir/tools/qa_remove_check.swift"
