import AppKit
import SwiftUI

struct DigestSearchBar: View {
    @Binding var query: String
    let matchCount: Int
    let activeIndex: Int?
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OpenMyChrome.muted)
            TextField("搜索字幕", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(OpenMyChrome.ink)
                .onSubmit { step(1) }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(countLabel)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(OpenMyChrome.muted)
                    .frame(minWidth: 28, alignment: .trailing)
                Button(action: { step(-1) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenMyChrome.ink)
                .disabled(matchCount == 0)
                .help("上一个命中")
                Button(action: { step(1) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenMyChrome.ink)
                .disabled(matchCount == 0)
                .help("下一个命中")
                Button(action: { query = "" }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenMyChrome.muted)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(OpenMyChrome.raise, in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                .strokeBorder(OpenMyChrome.hair)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onExitCommand { query = "" }
    }

    private var countLabel: String {
        guard matchCount > 0, let activeIndex else { return "0/0" }
        return "\(activeIndex + 1)/\(matchCount)"
    }
}

struct DigestSelectionBar: View {
    let canUseModel: Bool
    let isExplaining: Bool
    let onExplain: () -> Void
    let onSaveNote: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onExplain) {
                Text(isExplaining ? "解释中…" : "解释")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .watchGlassButton(prominent: true)
            .disabled(isExplaining || !canUseModel)
            Button(action: onSaveNote) {
                Text("存笔记")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .watchGlassButton()
            if !canUseModel {
                Text(DigestRequestBuilder.missingKeyHint)
                    .font(.system(size: 10))
                    .foregroundStyle(OpenMyChrome.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

struct DigestExplainBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(OpenMyChrome.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OpenMyChrome.raise, in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                    .strokeBorder(OpenMyChrome.hair)
            }
    }
}

struct DigestOverviewPage: View {
    let nativeChapters: [VideoChapter]
    let overview: DigestOverviewPayload?
    let isGenerating: Bool
    let message: String?
    let hasAPIKey: Bool
    let hasSubtitles: Bool
    let currentTime: Double
    let timeColumnWidth: CGFloat
    let generate: () -> Void
    let seek: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            if let overview, !overview.chapters.isEmpty || !overview.keyQuotes.isEmpty {
                generatedList(overview)
            } else if nativeChapters.isEmpty {
                emptyState
            } else {
                nativeList
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if !hasAPIKey {
                Text(DigestRequestBuilder.missingKeyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(OpenMyChrome.muted)
            } else if !hasSubtitles {
                Text("没有字幕，无法生成总览")
                    .font(.system(size: 11))
                    .foregroundStyle(OpenMyChrome.muted)
            } else {
                Button(action: generate) {
                    Text(isGenerating ? "正在生成…" : (overview == nil ? "生成总览" : "重新生成"))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .watchGlassButton(prominent: overview == nil)
                .disabled(isGenerating)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let message, !message.isEmpty {
            sidePaneEmptyState(title: "总览未生成", detail: message)
        } else {
            sidePaneEmptyState(
                title: "暂无总览",
                detail: hasAPIKey
                    ? "把全片字幕发给模型，生成覆盖到片尾的章节和金句。"
                    : DigestRequestBuilder.missingKeyHint
            )
        }
    }

    private var nativeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(OpenMyChrome.muted)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Text("视频自带章节")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OpenMyChrome.muted)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DigestCueDisplay.blockSpacing) {
                    ForEach(nativeChapters) { chapter in
                        digestTimeRow(
                            time: chapter.startTime,
                            title: chapter.title,
                            detail: nil,
                            isCurrent: isCurrentNative(chapter),
                            timeColumnWidth: timeColumnWidth,
                            seek: seek
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func generatedList(_ overview: DigestOverviewPayload) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DigestCueDisplay.blockSpacing) {
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(OpenMyChrome.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                sectionLabel("章节")
                ForEach(overview.chapters) { chapter in
                    digestTimeRow(
                        time: chapter.timestampSeconds,
                        title: chapter.title,
                        detail: chapter.summary.isEmpty ? nil : chapter.summary,
                        isCurrent: isCurrentGenerated(chapter, in: overview.chapters),
                        timeColumnWidth: timeColumnWidth,
                        seek: seek
                    )
                }
                if !overview.keyQuotes.isEmpty {
                    sectionLabel("金句")
                        .padding(.top, 8)
                    ForEach(overview.keyQuotes) { quote in
                        digestTimeRow(
                            time: quote.timestampSeconds,
                            title: quote.quote,
                            detail: nil,
                            isCurrent: false,
                            timeColumnWidth: timeColumnWidth,
                            seek: seek
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(OpenMyChrome.muted)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func isCurrentNative(_ chapter: VideoChapter) -> Bool {
        guard currentTime >= chapter.startTime else { return false }
        if let endTime = chapter.endTime { return currentTime < endTime }
        guard let index = nativeChapters.firstIndex(of: chapter), index + 1 < nativeChapters.count else {
            return true
        }
        return currentTime < nativeChapters[index + 1].startTime
    }

    private func isCurrentGenerated(_ chapter: DigestGeneratedChapter, in chapters: [DigestGeneratedChapter]) -> Bool {
        guard currentTime >= chapter.timestampSeconds else { return false }
        guard let index = chapters.firstIndex(of: chapter), index + 1 < chapters.count else {
            return true
        }
        return currentTime < chapters[index + 1].timestampSeconds
    }
}

struct DigestNotesPage: View {
    let notes: [DigestNote]
    let timeColumnWidth: CGFloat
    let seek: (Double) -> Void
    let delete: (UUID) -> Void

    var body: some View {
        if notes.isEmpty {
            sidePaneEmptyState(
                title: "暂无笔记",
                detail: "在字幕页选中文字，点「存笔记」。"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DigestCueDisplay.blockSpacing) {
                    ForEach(notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button {
                                seek(note.time)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(DigestTimecode.format(note.time))
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(OpenMyChrome.muted)
                                        .frame(width: timeColumnWidth, alignment: .trailing)
                                    Text(SubtitleSentenceBlocks.withCJKLatinSpacing(note.text))
                                        .font(.system(size: DigestCueDisplay.translationSize))
                                        .foregroundStyle(OpenMyChrome.ink)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("跳到笔记时刻")

                            Button {
                                delete(note.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(OpenMyChrome.muted)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("删除笔记")
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 8)
                        .padding(.vertical, DigestCueDisplay.rowVerticalPadding)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(OpenMyChrome.raise.opacity(0.88))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(OpenMyChrome.hair)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
}

func digestTimeRow(
    time: Double,
    title: String,
    detail: String?,
    isCurrent: Bool,
    timeColumnWidth: CGFloat,
    seek: @escaping (Double) -> Void
) -> some View {
    Button {
        seek(time)
    } label: {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(DigestTimecode.format(time))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(isCurrent ? OpenMyChrome.ink : OpenMyChrome.muted)
                .frame(width: timeColumnWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: DigestCueDisplay.pairSpacing) {
                Text(SubtitleSentenceBlocks.withCJKLatinSpacing(title))
                    .font(.system(size: DigestCueDisplay.translationSize, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(OpenMyChrome.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(SubtitleSentenceBlocks.withCJKLatinSpacing(detail))
                        .font(.system(size: DigestCueDisplay.originalSize))
                        .foregroundStyle(OpenMyChrome.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, DigestCueDisplay.rowVerticalPadding)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

func sidePaneEmptyState(title: String, detail: String) -> some View {
    VStack(spacing: 8) {
        Spacer(minLength: 0)
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
        Text(detail)
            .font(.system(size: 11))
            .foregroundStyle(.secondary.opacity(0.8))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

