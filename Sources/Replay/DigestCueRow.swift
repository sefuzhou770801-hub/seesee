import AppKit
import SwiftUI

struct DigestNoteTextStack: View {
    let text: String

    var body: some View {
        let lines = DigestCueDisplay.lines(from: text)
        VStack(alignment: .leading, spacing: DigestCueDisplay.pairSpacing) {
            Text(lines.translation)
                .font(.system(size: DigestCueDisplay.translationSize))
                .foregroundStyle(OpenMyChrome.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let original = lines.original {
                Text(original)
                    .font(.system(size: DigestCueDisplay.originalSize))
                    .foregroundStyle(OpenMyChrome.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DigestCueRow: View {
    let timeLabel: String
    let cueText: String
    let timeColumnWidth: CGFloat
    var isCurrent = false
    var query = ""
    var onSeek: () -> Void = {}
    var onSelection: (String) -> Void = { _ in }
    var onClearSelection: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onSeek) {
                Text(timeLabel)
                    .font(.system(size: DigestCueDisplay.originalSize).monospacedDigit())
                    .foregroundStyle(isCurrent ? OpenMyChrome.ink : OpenMyChrome.muted)
                    .frame(width: timeColumnWidth, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.top] + DigestCueDisplay.timeBaselineFromTop
            }

            SelectableCueText(
                text: cueText,
                query: query,
                isCurrent: isCurrent,
                onSeek: onSeek,
                onSelection: onSelection,
                onClearSelection: onClearSelection
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.top] + DigestCueDisplay.firstLineBaselineFromTop
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SelectableCueText: NSViewRepresentable {
    var text: String
    var query: String
    var isCurrent: Bool
    var onSeek: () -> Void
    var onSelection: (String) -> Void
    var onClearSelection: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FittingTextView {
        let view = FittingTextView()
        view.delegate = context.coordinator
        view.isEditable = false
        view.isRichText = true
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.focusRingType = .none
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.allowsUndo = false
        view.font = NSFont.systemFont(ofSize: DigestCueDisplay.originalSize)
        view.layoutManager?.usesFontLeading = false
        context.coordinator.parent = self
        view.onCollapsedClick = {
            context.coordinator.parent?.onSeek()
        }
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: FittingTextView, context: Context) {
        context.coordinator.parent = self
        view.onCollapsedClick = {
            context.coordinator.parent?.onSeek()
        }
        let snapshot = text + "\u{1e}" + query + "\u{1e}" + (isCurrent ? "1" : "0")
        if context.coordinator.renderedSnapshot != snapshot {
            let selected = view.selectedRange()
            apply(to: view, coordinator: context.coordinator)
            if selected.length > 0, selected.location + selected.length <= (view.string as NSString).length {
                context.coordinator.isApplying = true
                view.setSelectedRange(selected)
                context.coordinator.isApplying = false
            }
            context.coordinator.renderedSnapshot = snapshot
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FittingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        nsView.textContainerInset = .zero
        nsView.textContainer?.lineFragmentPadding = 0
        nsView.textContainer?.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        nsView.layoutManager?.usesFontLeading = false
        nsView.layoutManager?.ensureLayout(for: nsView.textContainer!)
        let height = DigestCueDisplay.blockHeight(for: text, width: width)
        return CGSize(width: width, height: height)
    }

    private func apply(to view: FittingTextView, coordinator: Coordinator? = nil) {
        coordinator?.isApplying = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        let attributed = DigestCueDisplay.attributedString(
            text: text,
            query: query,
            isCurrent: isCurrent,
            originalColor: OpenMyChrome.nsMuted,
            translationColor: OpenMyChrome.nsInk
        )
        view.textStorage?.setAttributedString(attributed)
        coordinator?.isApplying = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableCueText?
        var renderedSnapshot = ""
        var isApplying = false

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying else { return }
            guard let view = notification.object as? FittingTextView else { return }
            let range = view.selectedRange()
            if range.length == 0 {
                parent?.onClearSelection()
                return
            }
            let piece = (view.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if piece.isEmpty {
                parent?.onClearSelection()
            } else {
                parent?.onSelection(piece)
            }
        }
    }
}

final class FittingTextView: NSTextView {
    var onCollapsedClick: (() -> Void)?

    convenience init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        manager.usesFontLeading = false
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        zeroInnerInsets()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        zeroInnerInsets()
    }

    private func zeroInnerInsets() {
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        layoutManager?.usesFontLeading = false
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(DigestCueDisplay.translationSize * DigestCueDisplay.translationLineMultiple))
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(ceil(used.height), ceil(DigestCueDisplay.translationSize * DigestCueDisplay.translationLineMultiple))
        )
    }

    override var firstBaselineOffsetFromTop: CGFloat {
        DigestCueDisplay.firstLineBaselineFromTop
    }

    override func layout() {
        super.layout()
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        if let textContainer, bounds.width > 0 {
            textContainer.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }
        invalidateIntrinsicContentSize()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if selectedRange().length == 0 {
            onCollapsedClick?()
        }
    }
}
