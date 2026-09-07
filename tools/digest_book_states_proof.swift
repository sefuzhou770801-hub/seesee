import AppKit
import SwiftUI

@main
struct DigestBookStatesProof {
    static let firstOpenPath = "/tmp/digest-book-first-open.png"
    static let hoverPath = "/tmp/digest-book-hover.png"
    static let canvasWidth = 360
    static let canvasHeight = 220

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        let firstHits = render(forceHover: false, path: firstOpenPath)
        precondition(firstHits["explain"] == nil, "首次打开不得露出解释按钮")
        precondition(firstHits["highlight-action"] == nil, "首次打开不得露出划线按钮")
        precondition(firstHits["highlight"] != nil, "首次打开须有划线计数入口")
        precondition(firstHits["toc"] != nil, "首次打开须有生成目录占位")

        let hoverHits = render(forceHover: true, path: hoverPath)
        guard let explain = hoverHits["explain"] else {
            fatalError("digest_book_states_proof: 悬停态缺少解释按钮")
        }
        guard let highlight = hoverHits["highlight-action"] else {
            fatalError("digest_book_states_proof: 悬停态缺少划线按钮")
        }
        precondition(
            explain.height >= DigestBookChrome.minActionHit - 0.5,
            "解释命中高度 \(explain.height)pt < 22pt"
        )
        precondition(
            explain.width >= DigestBookChrome.minActionHit - 0.5,
            "解释命中宽度 \(explain.width)pt < 22pt"
        )
        precondition(
            highlight.height >= DigestBookChrome.minActionHit - 0.5,
            "划线命中高度 \(highlight.height)pt < 22pt"
        )
        precondition(
            highlight.width >= DigestBookChrome.minActionHit - 0.5,
            "划线命中宽度 \(highlight.width)pt < 22pt"
        )
        print("digest_book_states_proof first=\(firstOpenPath) hover=\(hoverPath)")
        print("digest_book_states_proof=passed")
    }

    @MainActor
    private static func render(forceHover: Bool, path: String) -> [String: CGRect] {
        let sink = BookHitSink()
        let root = DigestBookStateView(forceHover: forceHover, sink: sink)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let size = CGSize(width: canvasWidth, height: canvasHeight)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let bounds = NSRect(origin: .zero, size: size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvasWidth,
            pixelsHigh: canvasHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { fatalError("digest_book_states_proof: 无法生成位图 \(path)") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_book_states_proof: 无法编码 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_book_states_proof: 写 \(path) 失败 \(error)")
        }
        window.close()
        return sink.hits
    }
}

final class BookHitSink {
    var hits: [String: CGRect] = [:]
}

private struct DigestBookStateView: View {
    let forceHover: Bool
    let sink: BookHitSink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DigestBookToolbar(
                query: "",
                onQueryChange: { _ in },
                matchCount: 0,
                activeIndex: nil,
                highlightCount: 0,
                step: { _ in }
            )
            DigestTOCPlaceholder()
            DigestCueRow(
                timeLabel: "0:06",
                cueText: "Hello world.\n大家好。",
                timeColumnWidth: 52,
                showsActions: forceHover
            )
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, DigestCueDisplay.rowVerticalPadding)
            Spacer(minLength: 0)
        }
        .frame(width: CGFloat(DigestBookStatesProof.canvasWidth), height: CGFloat(DigestBookStatesProof.canvasHeight), alignment: .top)
        .background(OpenMyChrome.canvas)
        .coordinateSpace(name: "digest-book-page")
        .onPreferenceChange(DigestBookHitKey.self) { sink.hits = $0 }
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}
