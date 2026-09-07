import AppKit
import SwiftUI

@main
struct DigestBookNarrowProof {
    static let width = Int(DigestBookChrome.minColumnWidth)
    static let height = 420

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        let first = render(.firstOpen, path: "/tmp/digest-book-narrow-first-open.png")
        precondition(first["explain"] == nil, "首次打开不得露出解释")
        precondition(first["highlight-action"] == nil, "首次打开不得露出划线按钮")
        assertInside(first, keys: ["highlight", "toc"], state: "首次打开")
        assertNoOverlap(first, keys: ["highlight", "toc"], state: "首次打开")

        let hover = render(.hover, path: "/tmp/digest-book-narrow-hover.png")
        assertButton(hover, "explain", state: "悬停")
        assertButton(hover, "highlight-action", state: "悬停")
        assertInside(hover, keys: ["highlight", "toc", "explain", "highlight-action"], state: "悬停")
        assertNoOverlap(hover, keys: ["highlight", "toc", "explain", "highlight-action"], state: "悬停")
        if let text = hover["cue-text"], let explain = hover["explain"] {
            precondition(text.width > 100, "最窄栏正文须保持整行宽，实际 \(text.width)")
            precondition(explain.minY + 1 >= text.maxY - 8, "232 点悬停按钮须落到句子下一行")
        }

        let overlay = render(
            .hover,
            path: "/tmp/digest-book-hover-overlay.png",
            canvasWidth: 360
        )
        assertButton(overlay, "explain", state: "正常宽度悬停")
        if let text = overlay["cue-text"], let explain = overlay["explain"] {
            precondition(text.width > 140, "正常宽度悬停正文不得被压成窄列，实际 \(text.width)")
            precondition(explain.minY <= text.minY + 28, "正常宽度按钮须浮在句行右上")
        }

        let annotated = render(.annotated, path: "/tmp/digest-book-narrow-annotated.png")
        precondition(annotated["annotation-body"] != nil, "批注态须露出正文")
        assertButton(annotated, "annotation-toggle", state: "批注")
        assertButton(annotated, "annotation-delete", state: "批注")
        assertInside(
            annotated,
            keys: ["highlight", "toc", "annotation-body", "annotation-toggle", "annotation-delete"],
            state: "批注"
        )
        assertNoOverlap(
            annotated,
            keys: ["highlight", "toc", "annotation-toggle", "annotation-delete"],
            state: "批注"
        )

        let highlighted = render(.highlighted, path: "/tmp/digest-book-narrow-highlighted.png")
        precondition(highlighted["comment"] != nil, "划线态须露出批语")
        assertInside(highlighted, keys: ["highlight", "toc", "comment"], state: "划线")
        assertNoOverlap(highlighted, keys: ["highlight", "toc", "comment"], state: "划线")

        let filtered = render(.highlightsOnly, path: "/tmp/digest-book-narrow-highlights-only.png")
        precondition(filtered["toc"] == nil, "只看划线不得出现生成目录")
        precondition(filtered["collapsed-hint"] != nil, "只看划线须有收起提示")
        precondition(filtered["comment"] != nil, "只看划线须保留批语")
        assertInside(filtered, keys: ["highlight", "comment", "collapsed-hint"], state: "只看划线")
        assertNoOverlap(filtered, keys: ["highlight", "comment", "collapsed-hint"], state: "只看划线")

        let progress = render(.explaining, path: "/tmp/digest-book-narrow-explaining.png")
        precondition(progress["explain-progress"] != nil, "解释进行中必须露出稍等")
        assertInside(progress, keys: ["highlight", "toc", "explain-progress"], state: "解释进行中")
        assertNoOverlap(progress, keys: ["highlight", "toc", "explain-progress"], state: "解释进行中")

        let tocExpanded = render(.tocExpanded, path: "/tmp/digest-book-narrow-toc-expanded.png")
        precondition(tocExpanded["toc"] != nil, "展开目录标题须可点")
        precondition(
            tocExpanded.keys.contains(where: { $0.hasPrefix("toc-chapter-") }),
            "展开目录须露出章节行"
        )
        let tocKeys = tocExpanded.keys.filter { $0 == "toc" || $0.hasPrefix("toc-chapter-") || $0 == "highlight" }
        assertInside(tocExpanded, keys: Array(tocKeys), state: "目录展开")
        assertNoOverlap(tocExpanded, keys: ["highlight", "toc"], state: "目录展开")

        let missing = render(.missingKey, path: "/tmp/digest-missing-key.png", canvasWidth: 360)
        precondition(missing["missing-key"] != nil, "无密钥提示须可见")
        precondition(missing["view-config"] != nil, "须有查看配置方法按钮")
        assertButton(missing, "view-config", state: "无密钥")

        let undo = render(.undoBar, path: "/tmp/digest-annotation-undo.png", canvasWidth: 360)
        precondition(undo["undo"] != nil, "批注删除撤回条须可见")

        print("digest_book_narrow_proof first=/tmp/digest-book-narrow-first-open.png hover=/tmp/digest-book-narrow-hover.png overlay=/tmp/digest-book-hover-overlay.png annotated=/tmp/digest-book-narrow-annotated.png highlighted=/tmp/digest-book-narrow-highlighted.png filter=/tmp/digest-book-narrow-highlights-only.png explaining=/tmp/digest-book-narrow-explaining.png toc=/tmp/digest-book-narrow-toc-expanded.png missingKey=/tmp/digest-missing-key.png undo=/tmp/digest-annotation-undo.png")
        print("digest_book_narrow_proof=passed")
    }

    @MainActor
    private static func render(
        _ state: BookState,
        path: String,
        canvasWidth: Int = DigestBookNarrowProof.width
    ) -> [String: CGRect] {
        let sink = NarrowHitSink()
        let root = DigestNarrowBookView(state: state, canvasWidth: canvasWidth, sink: sink)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let size = CGSize(width: canvasWidth, height: height)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = OneXWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = OpenMyChrome.nsCanvas
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let bounds = NSRect(origin: .zero, size: size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvasWidth,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { fatalError("digest_book_narrow_proof: 无法生成位图 \(path)") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_book_narrow_proof: 无法编码 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_book_narrow_proof: 写 \(path) 失败 \(error)")
        }
        window.close()
        return sink.hits
    }

    private static func assertButton(_ hits: [String: CGRect], _ key: String, state: String) {
        guard let rect = hits[key] else {
            fatalError("digest_book_narrow_proof: \(state) 缺少 \(key)")
        }
        precondition(
            rect.height >= DigestBookChrome.minActionHit - 0.5,
            "\(state) \(key) 高度 \(rect.height) < 22"
        )
        precondition(
            rect.width >= DigestBookChrome.minActionHit - 0.5,
            "\(state) \(key) 宽度 \(rect.width) < 22"
        )
    }

    private static func assertInside(_ hits: [String: CGRect], keys: [String], state: String) {
        let maxX = CGFloat(width)
        for key in keys {
            guard let rect = hits[key] else {
                fatalError("digest_book_narrow_proof: \(state) 缺少 \(key)")
            }
            precondition(
                rect.minX >= -0.5 && rect.maxX <= maxX + 0.5,
                "\(state) \(key) 超出最窄栏：\(rect)"
            )
            precondition(rect.minY >= -0.5, "\(state) \(key) 顶部越界：\(rect)")
            precondition(rect.width > 1 && rect.height > 1, "\(state) \(key) 不可见：\(rect)")
        }
    }

    private static func assertNoOverlap(_ hits: [String: CGRect], keys: [String], state: String) {
        for index in 0..<keys.count {
            for other in (index + 1)..<keys.count {
                guard let a = hits[keys[index]], let b = hits[keys[other]] else { continue }
                precondition(
                    !a.intersects(b),
                    "\(state) \(keys[index]) 与 \(keys[other]) 重叠：\(a) / \(b)"
                )
            }
        }
    }
}

enum BookState {
    case firstOpen
    case hover
    case annotated
    case highlighted
    case highlightsOnly
    case explaining
    case tocExpanded
    case missingKey
    case undoBar
}

final class NarrowHitSink {
    var hits: [String: CGRect] = [:]
}

private struct DigestNarrowBookView: View {
    let state: BookState
    let canvasWidth: Int
    let sink: NarrowHitSink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state == .missingKey {
                DigestMissingKeyHint()
                    .padding(12)
                Spacer(minLength: 0)
            } else if state == .undoBar {
                Spacer(minLength: 0)
                DigestNoteUndoBar(onUndo: {})
                    .padding(16)
            } else {
            DigestBookToolbar(
                query: "",
                onQueryChange: { _ in },
                matchCount: 0,
                activeIndex: nil,
                highlightCount: state == .highlightsOnly || state == .highlighted ? 1 : 0,
                isFilterActive: state == .highlightsOnly,
                step: { _ in }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: DigestCueDisplay.blockSpacing) {
                    if state == .tocExpanded {
                        DigestTOCBanner(
                            toc: DigestOverviewPayload(
                                chapters: [
                                    DigestGeneratedChapter(
                                        title: "开场",
                                        timestamp: "0:00",
                                        timestampSeconds: 0,
                                        summary: "先把问题说清楚"
                                    ),
                                    DigestGeneratedChapter(
                                        title: "方法",
                                        timestamp: "2:00",
                                        timestampSeconds: 120,
                                        summary: "一步一步做"
                                    )
                                ],
                                keyQuotes: [],
                                source: .videoChapters,
                                durationSeconds: 300
                            ),
                            isGenerating: false,
                            message: nil,
                            hasAPIKey: true,
                            isExpanded: true,
                            currentTime: 8,
                            timeColumnWidth: 52,
                            onToggleExpand: {},
                            onGenerate: {},
                            onSeek: { _ in }
                        )
                    } else if state != .highlightsOnly {
                        DigestTOCPlaceholder()
                    }
                    cueBlock
                    if state == .highlightsOnly {
                        DigestCollapsedHint(hiddenCount: 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            }
        }
        .frame(width: CGFloat(canvasWidth), height: CGFloat(DigestBookNarrowProof.height), alignment: .top)
        .background(OpenMyChrome.canvas)
        .coordinateSpace(name: "digest-book-page")
        .onPreferenceChange(DigestBookHitKey.self) { sink.hits = $0 }
    }

    private var cueBlock: some View {
        VStack(alignment: .leading, spacing: DigestCueDisplay.pairSpacing) {
            DigestCueRow(
                timeLabel: "0:06",
                cueText: "Hello world.\n大家好。",
                timeColumnWidth: 52,
                isHighlighted: state == .highlighted || state == .highlightsOnly,
                showsActions: state == .hover,
                onSeek: {},
                stacksActions: canvasWidth <= Int(DigestBookChrome.minColumnWidth)
            )
            if state == .annotated {
                DigestAnnotationCard(
                    annotation: DigestAnnotation(
                        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                        time: 6,
                        text: "Hello world.\n大家好。",
                        explanation: "这句是在打招呼，后面要进入正题。",
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        model: "claude-sonnet-5"
                    )
                )
                .padding(.leading, 62)
            }
            if state == .highlighted || state == .highlightsOnly {
                DigestHighlightCommentRow(text: "这句是关键")
                    .padding(.leading, 62)
            }
            if state == .explaining {
                DigestExplainProgress()
                    .padding(.leading, 62)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, DigestCueDisplay.rowVerticalPadding)
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}
