import AppKit
import SwiftUI

@main
struct DigestTOCProof {
    static let idlePath = "/tmp/digest-toc-idle.png"
    static let collapsedPath = "/tmp/digest-toc-collapsed.png"
    static let expandedPath = "/tmp/digest-toc-expanded.png"
    static let canvasWidth = 360
    static let idleHeight = 72
    static let collapsedHeight = 72
    static let expandedHeight = 280

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        let idleHits = render(mode: .idle, path: idlePath, height: idleHeight)
        precondition(idleHits["toc"] != nil, "生成目录行须可命中")

        let collapsedHits = render(mode: .collapsed, path: collapsedPath, height: collapsedHeight)
        precondition(collapsedHits["toc"] != nil, "折叠目录行须可命中")

        let expandedHits = render(mode: .expanded, path: expandedPath, height: expandedHeight)
        precondition(expandedHits["toc"] != nil, "展开态目录标题须可命中")
        precondition(
            expandedHits.keys.contains(where: { $0.hasPrefix("toc-chapter-") }),
            "展开态须渲染章节行"
        )

        print("digest_toc_proof idle=\(idlePath) collapsed=\(collapsedPath) expanded=\(expandedPath)")
        print("digest_toc_proof=passed")
    }

    fileprivate enum Mode {
        case idle
        case collapsed
        case expanded
    }

    @MainActor
    private static func render(mode: Mode, path: String, height: Int) -> [String: CGRect] {
        let sink = TOCHitSink()
        let root = DigestTOCProofView(mode: mode, sink: sink)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
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
        guard let rep else { fatalError("digest_toc_proof: 无法生成位图 \(path)") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_toc_proof: 无法编码 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_toc_proof: 写 \(path) 失败 \(error)")
        }
        window.close()
        return sink.hits
    }
}

final class TOCHitSink {
    var hits: [String: CGRect] = [:]
}

private struct DigestTOCProofView: View {
    let mode: DigestTOCProof.Mode
    let sink: TOCHitSink

    private var sample: DigestOverviewPayload {
        DigestOverviewPayload(
            chapters: [
                DigestGeneratedChapter(
                    title: "开场",
                    timestamp: "0:00",
                    timestampSeconds: 0,
                    summary: "介绍问题从哪来",
                    quote: DigestKeyQuote(
                        quote: "think outside the box",
                        translation: "跳出框框来想",
                        timestamp: "0:15",
                        timestampSeconds: 15
                    )
                ),
                DigestGeneratedChapter(
                    title: "方法",
                    timestamp: "2:00",
                    timestampSeconds: 120,
                    summary: "把做法讲清楚"
                )
            ],
            keyQuotes: [],
            source: .videoChapters,
            durationSeconds: 420
        )
    }

    var body: some View {
        let toc: DigestOverviewPayload? = mode == .idle ? nil : sample
        return DigestTOCBanner(
            toc: toc,
            isGenerating: false,
            message: nil,
            hasAPIKey: true,
            isExpanded: mode == .expanded,
            currentTime: 130,
            timeColumnWidth: 52,
            onToggleExpand: {},
            onGenerate: {},
            onSeek: { _ in }
        )
        .frame(
            width: CGFloat(DigestTOCProof.canvasWidth),
            height: CGFloat(mode == .expanded ? DigestTOCProof.expandedHeight : DigestTOCProof.idleHeight),
            alignment: .top
        )
        .background(OpenMyChrome.canvas)
        .coordinateSpace(name: "digest-book-page")
        .onPreferenceChange(DigestBookHitKey.self) { sink.hits = $0 }
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}
