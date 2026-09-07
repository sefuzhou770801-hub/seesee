import AppKit
import SwiftUI

@main
struct DigestSettingsProof {
    static let emptyPath = "/tmp/digest-settings-empty.png"
    static let validPath = "/tmp/digest-settings-valid.png"
    static let invalidPath = "/tmp/digest-settings-invalid.png"

    @MainActor
    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        OpenMyChrome.applyAppearance()

        let suite = "digest-settings-proof-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let media = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Replay")

        let empty = DigestSettingsModel(defaults: defaults, environment: [:], mediaFolder: media, verifier: { _, _ in .valid })
        render(model: empty, path: emptyPath)

        let valid = DigestSettingsModel(defaults: defaults, environment: [:], mediaFolder: media, verifier: { _, _ in .valid })
        valid.debounce = 0
        valid.key = "AIzaSyD-example-example-example-example"
        await valid.awaitVerification()
        precondition(valid.status == DigestSettingsCopy.validStatus)
        render(model: valid, path: validPath)

        let invalid = DigestSettingsModel(defaults: defaults, environment: [:], mediaFolder: media, verifier: { _, _ in .invalid })
        invalid.debounce = 0
        invalid.key = "AIzaSyD-wrong-wrong-wrong-wrong-wrong"
        await invalid.awaitVerification()
        precondition(invalid.status == DigestSettingsCopy.invalidStatus)
        render(model: invalid, path: invalidPath)
        print("digest_settings_proof=passed")
    }

    @MainActor
    private static func render(model: DigestSettingsModel, path: String) {
        let hosting = NSHostingView(rootView: DigestSettingsView(model: model))
        hosting.appearance = NSAppearance(named: .darkAqua)
        let fitting = hosting.fittingSize
        let width = DigestSettingsView.width
        let height = max(fitting.height, 200)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fatalError("digest_settings_proof: 无法建位图") }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("digest_settings_proof: 无法编码 \(path)")
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fatalError("digest_settings_proof: 写 \(path) 失败 \(error)")
        }
        precondition(height <= 420, "设置页高度 \(height) 超出预期")
        print("digest_settings_proof size=\(Int(width))x\(Int(height)) status=\(model.status) masked=\(model.maskedKey) png=\(path)")
        window.close()
    }
}
