import AppKit
import SwiftUI

struct DigestAnnotationCard: View {
    let annotation: DigestAnnotation
    var isCollapsed = false
    var showsContinueAsk = false
    var onToggle: () -> Void = {}
    var onDelete: () -> Void = {}
    var onContinueAsk: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !isCollapsed {
                Text(annotation.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(OpenMyChrome.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DigestBookHitKey.self,
                                value: ["annotation-body": proxy.frame(in: .named("digest-book-page"))]
                            )
                        }
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            OpenMyChrome.raise,
            in: RoundedRectangle(cornerRadius: DigestBookChrome.annotationRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DigestBookChrome.annotationRadius, style: .continuous)
                .strokeBorder(OpenMyChrome.hair)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if showsContinueAsk {
                headerButton(
                    title: DigestContinueAsk.title,
                    action: onContinueAsk,
                    hitKey: "continue-ask"
                )
            }
            Spacer(minLength: 0)
            toggleButton
            deleteButton
        }
    }

    private var toggleButton: some View {
        headerButton(
            title: isCollapsed ? DigestAnnotationChrome.expandTitle : DigestAnnotationChrome.collapseTitle,
            action: onToggle,
            hitKey: "annotation-toggle"
        )
    }

    private var deleteButton: some View {
        headerButton(
            title: DigestAnnotationChrome.deleteTitle,
            action: onDelete,
            hitKey: "annotation-delete"
        )
    }

    private func headerButton(
        title: String,
        action: @escaping () -> Void,
        hitKey: String
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OpenMyChrome.ink)
                .padding(.horizontal, 8)
                .frame(minWidth: DigestBookChrome.minActionHit, minHeight: DigestBookChrome.minActionHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            OpenMyChrome.canvas,
            in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                .strokeBorder(OpenMyChrome.hair)
        }
        .help(title)
        .accessibilityLabel(title)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DigestBookHitKey.self,
                    value: [hitKey: proxy.frame(in: .named("digest-book-page"))]
                )
            }
        )
    }
}
