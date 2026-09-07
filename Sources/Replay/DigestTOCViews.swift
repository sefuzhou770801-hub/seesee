import SwiftUI

struct DigestTOCBanner: View {
    let toc: DigestOverviewPayload?
    let isGenerating: Bool
    let message: String?
    let hasAPIKey: Bool
    let isExpanded: Bool
    let currentTime: Double
    let timeColumnWidth: CGFloat
    let onToggleExpand: () -> Void
    let onGenerate: () -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isGenerating {
                statusRow(DigestTOCCopy.generatingLabel)
            } else if let toc, !toc.chapters.isEmpty {
                collapsedRow(toc)
                if isExpanded {
                    expandedBody(toc)
                }
            } else if let message, !message.isEmpty {
                if message == DigestCopy.missingKeyHint {
                    DigestMissingKeyHint()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    failureRow(message)
                }
            } else {
                DigestTOCPlaceholder(action: onGenerate)
            }
        }
    }

    private func collapsedRow(_ toc: DigestOverviewPayload) -> some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 8) {
                Text(DigestTOCCopy.collapsedTitle(for: toc))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OpenMyChrome.ink)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OpenMyChrome.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(minHeight: DigestBookChrome.minActionHit, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: ["toc": proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
        .accessibilityLabel(DigestTOCCopy.collapsedTitle(for: toc))
        .accessibilityHint(isExpanded ? "收起目录" : "展开目录")
    }

    private func expandedBody(_ toc: DigestOverviewPayload) -> some View {
        let current = DigestTOCComposer.currentChapterIndex(at: currentTime, in: toc.chapters)
        return VStack(alignment: .leading, spacing: 8) {
            Text(DigestTOCCopy.sourceNote(toc.source))
                .font(.system(size: 11))
                .foregroundStyle(OpenMyChrome.muted)
                .padding(.horizontal, 20)
            ForEach(Array(toc.chapters.enumerated()), id: \.element.id) { index, chapter in
                chapterBlock(chapter, isCurrent: current == index)
            }
        }
        .padding(.bottom, 8)
    }

    private func chapterBlock(_ chapter: DigestGeneratedChapter, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onSeek(chapter.timestampSeconds)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(chapter.timestamp)
                        .font(.system(size: DigestCueDisplay.originalSize).monospacedDigit())
                        .foregroundStyle(isCurrent ? OpenMyChrome.ink : OpenMyChrome.muted)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.title)
                            .font(.system(size: DigestCueDisplay.translationSize, weight: isCurrent ? .semibold : .medium))
                            .foregroundStyle(OpenMyChrome.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !chapter.summary.isEmpty {
                            Text(chapter.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(OpenMyChrome.muted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("跳到这一章")

            if let quote = chapter.quote {
                Button {
                    onSeek(quote.timestampSeconds)
                } label: {
                    VStack(alignment: .leading, spacing: DigestCueDisplay.pairSpacing) {
                        Text(quote.quote)
                            .font(.system(size: DigestCueDisplay.originalSize))
                            .foregroundStyle(OpenMyChrome.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !quote.translation.isEmpty {
                            Text(quote.translation)
                                .font(.system(size: DigestCueDisplay.translationSize))
                                .foregroundStyle(OpenMyChrome.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, timeColumnWidth + 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到这句")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: ["toc-chapter-\(chapter.id)": proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
    }

    private func statusRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OpenMyChrome.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(minHeight: DigestBookChrome.minActionHit, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: ["toc": proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
        .accessibilityLabel(text)
    }

    private func failureRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(OpenMyChrome.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if hasAPIKey {
                Button(action: onGenerate) {
                    Text(DigestTOCCopy.retryButtonTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OpenMyChrome.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: DigestBookChrome.minActionHit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    OpenMyChrome.canvas,
                    in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                        .strokeBorder(OpenMyChrome.hair)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            OpenMyChrome.raise,
            in: RoundedRectangle(cornerRadius: DigestBookChrome.annotationRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DigestBookChrome.annotationRadius, style: .continuous)
                .strokeBorder(OpenMyChrome.hair)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: ["toc": proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
        .accessibilityLabel(message)
    }
}
