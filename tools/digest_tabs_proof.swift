import AppKit
import SwiftUI

@main
struct DigestTabsProof {
    static let normalPath = "/tmp/digest-tabs-proof-normal.png"
    static let narrowPath = "/tmp/digest-tabs-proof-narrow.png"

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        precondition(DigestModeTabMetrics.fontSize == 13, "字号须升到 13")
        precondition(DigestModeTabMetrics.minHitHeight >= 26)
        precondition(DigestModeTabMetrics.horizontalPadding >= 12)

        render(
            width: DigestModeTabMetrics.normalProofWidth,
            path: normalPath,
            allowOverflow: false
        )
        render(
            width: DigestModeTabMetrics.minPaneWidth,
            path: narrowPath,
            allowOverflow: false
        )
        print("digest_tabs_proof=passed")
    }

    @MainActor
    private static func render(width: CGFloat, path: String, allowOverflow: Bool) {
        let sink = HitSink()
        let root = DigestTabsProofView(width: width, sink: sink)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let height = DigestModeTabMetrics.headerHeight
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

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

        guard let rep = makeBitmap(hosting: hosting, width: Int(width), height: Int(height)),
              let png = rep.representation(using: .png, properties: [:])
        else {
            fatalError("digest_tabs_proof: 无法生成 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_tabs_proof: 写 \(path) 失败 \(error)")
        }

        let hits = sink.hits
        let modes = ["lyrics", "overview", "notes"]
        for mode in modes {
            guard let frame = hits[mode] else {
                fatalError("digest_tabs_proof: 缺少页签 \(mode) 命中区 width=\(width)")
            }
            precondition(
                frame.height >= DigestModeTabMetrics.minHitHeight - 0.5,
                "页签 \(mode) 命中高度 \(frame.height)pt < 26pt（width=\(width)）"
            )
            precondition(
                frame.width >= DigestModeTabMetrics.horizontalPadding * 2 + 20,
                "页签 \(mode) 过窄 \(frame.width)pt，可能被截断（width=\(width)）"
            )
            if !allowOverflow {
                precondition(
                    frame.maxX <= width + 0.5 && frame.minX >= -0.5,
                    "页签 \(mode) 超出栏宽 \(width)：\(frame)"
                )
            }
        }
        guard let first = hits[modes[0]] else {
            fatalError("digest_tabs_proof: 无页签帧")
        }
        for mode in modes.dropFirst() {
            let frame = hits[mode]!
            precondition(
                abs(frame.minY - first.minY) < 4,
                "页签换行了：\(mode) minY=\(frame.minY) vs \(first.minY)（width=\(width)）"
            )
        }
        if let close = hits["close"] {
            precondition(
                abs(close.midY - first.midY) < 8,
                "关闭钮与页签不在同一行（width=\(width)）"
            )
            precondition(
                close.maxX <= width + 0.5,
                "关闭钮超出栏宽 \(width)：\(close)"
            )
        }
        print(
            "digest_tabs_proof width=\(Int(width)) hits=\(modes.map { "\($0)=\(Int(hits[$0]?.height ?? 0))h/\(Int(hits[$0]?.width ?? 0))w" }.joined(separator: " ")) png=\(path)"
        )
        window.close()
    }

    private static func makeBitmap(
        hosting: NSView,
        width: Int,
        height: Int
    ) -> NSBitmapImageRep? {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        return rep
    }
}

final class HitSink {
    var hits: [String: CGRect] = [:]
}

private struct DigestTabsProofView: View {
    let width: CGFloat
    let sink: HitSink

    var body: some View {
        DigestSidePaneHeader(selected: .lyrics, onSelect: { _ in })
            .frame(width: width, height: DigestModeTabMetrics.headerHeight)
            .onPreferenceChange(DigestTabHitKey.self) { sink.hits = $0 }
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}
