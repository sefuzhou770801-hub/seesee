import AppKit
import SwiftUI

@main
struct DigestNoteFullProof {
    static let outputPath = "/tmp/digest-note-full.png"

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        let hosting = NSHostingView(rootView: DigestNoteFullProofView())
        hosting.appearance = NSAppearance(named: .darkAqua)
        let size = CGSize(width: 420, height: 96)
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
        guard let rep else { fatalError("digest_note_full_proof: 无法生成位图") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_note_full_proof: 无法编码 PNG")
        }
        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            fatalError("digest_note_full_proof: 写 PNG 失败 \(error)")
        }
        print("digest_note_full_proof png=\(outputPath)")
        window.close()
        print("digest_note_full_proof=passed")
    }
}

private final class OneXWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
}

private struct DigestNoteFullProofView: View {
    var body: some View {
        ZStack {
            OpenMyChrome.canvas
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("1:08")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(OpenMyChrome.muted)
                    .frame(width: 52, alignment: .trailing)
                DigestNoteTextStack(
                    text: "This is very likely the reason.\n这很可能就是原因。"
                )
                Spacer(minLength: 0)
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
            .padding(12)
        }
        .frame(width: 420, height: 96)
    }
}
