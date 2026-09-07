import AppKit
import SwiftUI

struct DigestSearchBar: View {
    var query: String
    var onQueryChange: (String) -> Void
    let matchCount: Int
    let activeIndex: Int?
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OpenMyChrome.muted)
            TextField("搜索字幕", text: Binding(get: { query }, set: onQueryChange))
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
                        .frame(width: DigestBookChrome.minActionHit, height: DigestBookChrome.minActionHit)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenMyChrome.ink)
                .disabled(matchCount == 0)
                .help("上一个命中")
                Button(action: { step(1) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: DigestBookChrome.minActionHit, height: DigestBookChrome.minActionHit)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenMyChrome.ink)
                .disabled(matchCount == 0)
                .help("下一个命中")
                Button(action: { onQueryChange("") }) {
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
        .onExitCommand { onQueryChange("") }
    }

    private var countLabel: String {
        guard matchCount > 0, let activeIndex else { return "0/0" }
        return "\(activeIndex + 1)/\(matchCount)"
    }
}

struct DigestBookToolbar: View {
    var query: String
    var onQueryChange: (String) -> Void
    let matchCount: Int
    let activeIndex: Int?
    let highlightCount: Int
    var isFilterActive = false
    let step: (Int) -> Void
    var onHighlightFilter: () -> Void = {}

    var body: some View {
        HStack(spacing: DigestBookChrome.toolbarSpacing) {
            DigestSearchBar(
                query: query,
                onQueryChange: onQueryChange,
                matchCount: matchCount,
                activeIndex: activeIndex,
                step: step
            )
            .frame(minWidth: 0)
            Button(action: onHighlightFilter) {
                Text(DigestBookChrome.entryTitle(highlightCount))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OpenMyChrome.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: DigestBookChrome.minActionHit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                isFilterActive ? OpenMyChrome.rowSelected : OpenMyChrome.raise,
                in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                    .strokeBorder(OpenMyChrome.hair)
            }
            .help(DigestBookChrome.entryTitle(highlightCount))
            .accessibilityLabel(DigestBookChrome.entryTitle(highlightCount))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DigestBookHitKey.self,
                        value: ["highlight": proxy.frame(in: .named("digest-book-page"))]
                    )
                }
            )
        }
        .padding(.horizontal, DigestBookChrome.headerHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct DigestTOCPlaceholder: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack {
                Text(DigestBookChrome.tocPlaceholder)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OpenMyChrome.muted)
                Spacer(minLength: 0)
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
        .accessibilityLabel(DigestBookChrome.tocPlaceholder)
    }
}

struct DigestExplainRetryBar: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(DigestExplainQuality.retryPrompt)
                .font(.system(size: 12))
                .foregroundStyle(OpenMyChrome.ink)
            Spacer(minLength: 0)
            Button(action: onRetry) {
                Text(DigestExplainQuality.retryButtonTitle)
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
        .padding(.horizontal, 10)
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
            .background(
                OpenMyChrome.raise,
                in: RoundedRectangle(cornerRadius: DigestBookChrome.annotationRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DigestBookChrome.annotationRadius, style: .continuous)
                    .strokeBorder(OpenMyChrome.hair)
            }
    }
}

struct DigestExplainProgress: View {
    var body: some View {
        Text(DigestBookChrome.explainingLabel)
            .font(.system(size: 12))
            .foregroundStyle(OpenMyChrome.muted)
            .padding(.horizontal, 10)
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
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DigestBookHitKey.self,
                        value: ["explain-progress": proxy.frame(in: .named("digest-book-page"))]
                    )
                }
            )
            .accessibilityLabel(DigestBookChrome.explainingLabel)
    }
}

struct DigestMissingKeyHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DigestCopy.missingKeyHint)
                .font(.system(size: 12))
                .foregroundStyle(OpenMyChrome.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openSetup) {
                Text(DigestCopy.viewConfigTitle)
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
            .help(DigestCopy.viewConfigTitle)
            .accessibilityLabel(DigestCopy.viewConfigTitle)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DigestBookHitKey.self,
                        value: ["view-config": proxy.frame(in: .named("digest-book-page"))]
                    )
                }
            )
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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: ["missing-key": proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
        .accessibilityLabel(DigestCopy.missingKeyHint)
    }

    private func openSetup() {
        DigestSettingsOpener.open()
    }
}

struct DigestNoteUndoBar: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("删掉了")
                .font(.system(size: 13))
                .foregroundStyle(OpenMyChrome.muted)
            Spacer(minLength: 0)
            Button("撤回", action: onUndo)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(OpenMyChrome.ink)
                .background(OpenMyChrome.canvas, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(OpenMyChrome.hair)
                }
                .contentShape(Capsule())
                .accessibilityLabel("撤回")
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: ["undo": proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
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
