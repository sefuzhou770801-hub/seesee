import AppKit
import SwiftUI

@main
struct DigestAnnotationProof {
    static let expandedPath = "/tmp/digest-annotation-expanded.png"
    static let collapsedPath = "/tmp/digest-annotation-collapsed.png"
    static let continueAskPath = "/tmp/digest-annotation-continue-ask.png"
    static let canvasWidth = 360
    static let canvasHeight = 240

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        let expanded = render(collapsed: false, showsContinueAsk: false, path: expandedPath)
        precondition(expanded["annotation-body"] != nil, "展开态须露出批注正文")
        precondition(expanded["continue-ask"] == nil, "看时问答关闭时不得露出继续问")
        precondition(expanded["annotation-toggle"] != nil, "展开态须有收起入口")
        precondition(expanded["annotation-delete"] != nil, "展开态须有删除入口")

        let collapsed = render(collapsed: true, showsContinueAsk: false, path: collapsedPath)
        precondition(collapsed["annotation-body"] == nil, "收起态不得露出批注正文")
        precondition(collapsed["annotation-toggle"] != nil, "收起态须有展开入口")
        precondition(collapsed["annotation-delete"] != nil, "收起后仍可删除")
        precondition(collapsed["continue-ask"] == nil, "看时问答关闭时收起态也不得露出继续问")

        let continueAsk = render(collapsed: false, showsContinueAsk: true, path: continueAskPath)
        guard let ask = continueAsk["continue-ask"] else {
            fatalError("digest_annotation_proof: 开启看时问答时缺少继续问入口")
        }
        precondition(
            ask.height >= DigestBookChrome.minActionHit - 0.5,
            "继续问命中高度 \(ask.height)pt < 22pt"
        )
        precondition(
            ask.width >= DigestBookChrome.minActionHit - 0.5,
            "继续问命中宽度 \(ask.width)pt < 22pt"
        )
        precondition(continueAsk["annotation-body"] != nil, "含继续问的展开态须露出正文")

        print("digest_annotation_proof expanded=\(expandedPath) collapsed=\(collapsedPath) continueAsk=\(continueAskPath)")
        print("digest_annotation_proof=passed")
    }

    @MainActor
    private static func render(collapsed: Bool, showsContinueAsk: Bool, path: String) -> [String: CGRect] {
        let sink = AnnotationHitSink()
        let root = DigestAnnotationProofView(
            collapsed: collapsed,
            showsContinueAsk: showsContinueAsk,
            sink: sink
        )
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
        guard let rep else { fatalError("digest_annotation_proof: 无法生成位图 \(path)") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_annotation_proof: 无法编码 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_annotation_proof: 写 \(path) 失败 \(error)")
        }
        window.close()
        return sink.hits
    }
}

final class AnnotationHitSink {
    var hits: [String: CGRect] = [:]
}

private struct DigestAnnotationProofView: View {
    let collapsed: Bool
    let showsContinueAsk: Bool
    let sink: AnnotationHitSink

    var body: some View {
        VStack(alignment: .leading, spacing: DigestCueDisplay.pairSpacing) {
            DigestCueRow(
                timeLabel: "0:06",
                cueText: "Hello world.\n大家好。",
                timeColumnWidth: 52
            )
            DigestAnnotationCard(
                annotation: DigestAnnotation(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    time: 6,
                    text: "Hello world.\n大家好。",
                    explanation: "这句是在打招呼，后面要进入正题。",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    model: "claude-sonnet-5"
                ),
                isCollapsed: collapsed,
                showsContinueAsk: showsContinueAsk
            )
            .padding(.leading, 62)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, DigestCueDisplay.rowVerticalPadding)
        .frame(width: CGFloat(DigestAnnotationProof.canvasWidth), height: CGFloat(DigestAnnotationProof.canvasHeight), alignment: .top)
        .background(OpenMyChrome.canvas)
        .coordinateSpace(name: "digest-book-page")
        .onPreferenceChange(DigestBookHitKey.self) { sink.hits = $0 }
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}
