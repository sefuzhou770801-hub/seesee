import AppKit
import SwiftUI

@main
struct DigestFix2Proof {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()
        render(UndoProofView(), size: CGSize(width: 360, height: 64), path: "/tmp/digest-fix2-undo.png")
        render(SavedProofView(), size: CGSize(width: 360, height: 56), path: "/tmp/digest-fix2-saved.png")
        render(ChaptersProofView(), size: CGSize(width: 360, height: 220), path: "/tmp/digest-fix2-chapters.png")
        print("digest_fix2_proof=passed")
    }

    @MainActor
    private static func render<V: View>(_ root: V, size: CGSize, path: String) {
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
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
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { fatalError("digest_fix2_proof: 无法生成位图 \(path)") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_fix2_proof: 无法编码 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_fix2_proof: 写 \(path) 失败 \(error)")
        }
        print("digest_fix2_proof wrote \(path)")
        window.close()
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}

private struct UndoProofView: View {
    var body: some View {
        ZStack {
            OpenMyChrome.canvas
            HStack(spacing: 8) {
                Text("删掉了")
                    .font(.system(size: 13))
                    .foregroundStyle(OpenMyChrome.muted)
                Spacer(minLength: 0)
                Text("撤回")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OpenMyChrome.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OpenMyChrome.canvas, in: Capsule())
                    .overlay { Capsule().strokeBorder(OpenMyChrome.hair) }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OpenMyChrome.raise.opacity(0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OpenMyChrome.hair)
            }
            .padding(12)
        }
        .frame(width: 360, height: 64)
    }
}

private struct SavedProofView: View {
    var body: some View {
        ZStack {
            OpenMyChrome.canvas
            HStack(spacing: 6) {
                Text("解释")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OpenMyChrome.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OpenMyChrome.canvas, in: Capsule())
                    .overlay { Capsule().strokeBorder(OpenMyChrome.hair) }
                Text("记下了")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OpenMyChrome.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OpenMyChrome.raise, in: Capsule())
                    .overlay { Capsule().strokeBorder(OpenMyChrome.hair) }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: 360, height: 56)
    }
}

private struct ChaptersProofView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            OpenMyChrome.canvas
            VStack(alignment: .leading, spacing: 6) {
                Text("视频自带章节")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OpenMyChrome.muted)
                Text("0:00  开场")
                    .font(.system(size: 13))
                    .foregroundStyle(OpenMyChrome.ink)
                Text("5:00  方法")
                    .font(.system(size: 13))
                    .foregroundStyle(OpenMyChrome.ink)
                Text("AI 章节")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OpenMyChrome.muted)
                    .padding(.top, 8)
                Text("0:12  问题从何而来")
                    .font(.system(size: 13))
                    .foregroundStyle(OpenMyChrome.ink)
                Text("8:40  收束")
                    .font(.system(size: 13))
                    .foregroundStyle(OpenMyChrome.ink)
            }
            .padding(16)
        }
        .frame(width: 360, height: 220, alignment: .topLeading)
    }
}
