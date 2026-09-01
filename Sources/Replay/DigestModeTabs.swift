import AppKit
import SwiftUI

enum DigestModeTabMetrics {
    static let fontSize: CGFloat = 13
    static let minHitHeight: CGFloat = 26
    static let horizontalPadding: CGFloat = 12
    static let tabSpacing: CGFloat = 4
    static let trackPadding: CGFloat = 2
    static let headerHeight: CGFloat = 56
    static let headerHorizontalPadding: CGFloat = 12
    static let headerSpacing: CGFloat = 8
    static let closeButtonSize: CGFloat = 26
    static let minPaneWidth: CGFloat = 232
    static let normalProofWidth: CGFloat = 300
}

enum DigestTabHitKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct DigestModeTabs: View {
    let selected: SidePaneMode
    let onSelect: (SidePaneMode) -> Void

    var body: some View {
        HStack(spacing: DigestModeTabMetrics.tabSpacing) {
            tab(.lyrics)
            tab(.overview)
            tab(.notes)
        }
        .padding(DigestModeTabMetrics.trackPadding)
        .background(OpenMyChrome.raise, in: Capsule())
        .overlay {
            Capsule().strokeBorder(OpenMyChrome.hair)
        }
    }

    private func tab(_ mode: SidePaneMode) -> some View {
        DigestModeTabButton(
            title: SidePaneSelection.visibleTitle(for: mode),
            mode: mode,
            isSelected: selected == mode,
            action: { onSelect(mode) }
        )
    }
}

private struct DigestModeTabButton: View {
    let title: String
    let mode: SidePaneMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DigestModeTabMetrics.fontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? OpenMyChrome.ink : OpenMyChrome.muted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, DigestModeTabMetrics.horizontalPadding)
                .frame(minHeight: DigestModeTabMetrics.minHitHeight)
                .background {
                    if isSelected {
                        Capsule().fill(OpenMyChrome.canvas)
                    } else {
                        TabHoverCapsule()
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help(title)
        .accessibilityLabel(title)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestTabHitKey.self,
                    value: [mode.rawValue: proxy.frame(in: .named("digest-side-header"))]
                )
            }
        )
    }
}

private struct TabHoverCapsule: NSViewRepresentable {
    func makeNSView(context: Context) -> TabHoverCapsuleView {
        TabHoverCapsuleView()
    }

    func updateNSView(_ nsView: TabHoverCapsuleView, context: Context) {}
}

private final class TabHoverCapsuleView: NSView {
    private var hovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        OpenMyChrome.nsRowHover.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}

struct DigestSidePaneHeader: View {
    let selected: SidePaneMode
    let onSelect: (SidePaneMode) -> Void
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: DigestModeTabMetrics.headerSpacing) {
            DigestModeTabs(selected: selected, onSelect: onSelect)
            Spacer(minLength: DigestModeTabMetrics.headerSpacing)
            Button(action: onToggle) {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: DigestModeTabMetrics.fontSize, weight: .medium))
                    .foregroundStyle(OpenMyChrome.ink)
                    .frame(
                        width: DigestModeTabMetrics.closeButtonSize,
                        height: DigestModeTabMetrics.closeButtonSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                OpenMyChrome.raise,
                in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusMd, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OpenMyChrome.radiusMd, style: .continuous)
                    .strokeBorder(OpenMyChrome.hair)
            }
            .help("隐藏侧栏")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DigestTabHitKey.self,
                        value: ["close": proxy.frame(in: .named("digest-side-header"))]
                    )
                }
            )
        }
        .padding(.horizontal, DigestModeTabMetrics.headerHorizontalPadding)
        .frame(height: DigestModeTabMetrics.headerHeight)
        .frame(maxWidth: .infinity)
        .background(OpenMyChrome.canvas)
        .coordinateSpace(name: "digest-side-header")
    }
}
