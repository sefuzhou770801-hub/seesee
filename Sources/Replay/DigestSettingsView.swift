import SwiftUI

struct DigestSettingsView: View {
    @StateObject private var model: DigestSettingsModel
    @FocusState private var keyFocused: Bool

    static let width: CGFloat = 460

    init(model: DigestSettingsModel? = nil, mediaFolder: URL? = nil) {
        _model = StateObject(wrappedValue: model ?? DigestSettingsModel(mediaFolder: mediaFolder))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DigestSettingsCopy.sectionTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OpenMyChrome.ink)
            Text(DigestSettingsCopy.intro)
                .font(.system(size: 12))
                .foregroundStyle(OpenMyChrome.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            row(DigestSettingsCopy.providerLabel) {
                Picker("", selection: $model.provider) {
                    Text(DigestSettingsCopy.providerTitle(.gemini)).tag(DigestProviderKind.gemini)
                    Text(DigestSettingsCopy.providerTitle(.anthropic)).tag(DigestProviderKind.anthropic)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .accessibilityLabel(DigestSettingsCopy.providerLabel)
                Spacer(minLength: 0)
            }
            row("") {
                Text(model.providerNote)
                    .font(.system(size: 11))
                    .foregroundStyle(OpenMyChrome.faint)
            }

            row(DigestSettingsCopy.keyLabel) {
                keyField
            }

            row("") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(toneColor)
                        .frame(width: 6, height: 6)
                    Text(model.status)
                        .font(.system(size: 11))
                        .foregroundStyle(OpenMyChrome.muted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.status)
                Spacer(minLength: 8)
                secondaryButton(model.applyTitle, action: model.openApplyPage)
            }

            if model.mediaFolder != nil {
                Divider()
                    .overlay(OpenMyChrome.hair)
                    .padding(.vertical, 2)
                Text(DigestSettingsCopy.dataSectionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OpenMyChrome.ink)
                row(DigestSettingsCopy.mediaLabel) {
                    Text(model.mediaPathText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OpenMyChrome.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel(model.mediaPathText)
                    Spacer(minLength: 8)
                    secondaryButton(DigestSettingsCopy.revealTitle, action: model.revealMediaFolder)
                }
                row("") {
                    Text(DigestSettingsCopy.mediaNote)
                        .font(.system(size: 11))
                        .foregroundStyle(OpenMyChrome.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(OpenMyChrome.canvas)
        .navigationTitle(DigestSettingsCopy.windowTitle)
    }

    /// 不编辑时只露头尾四位；点进去编辑才显示全文。
    private var keyField: some View {
        let showsMask = !keyFocused && !model.key.isEmpty
        return TextField("", text: $model.key, prompt: Text(""))
            .focused($keyFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(showsMask ? Color.clear : OpenMyChrome.ink)
            .overlay(alignment: .leading) {
                if model.key.isEmpty {
                    Text(DigestSettingsCopy.keyPlaceholder)
                        .font(.system(size: 12))
                        .foregroundStyle(OpenMyChrome.faint)
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                } else if showsMask {
                    Text(model.maskedKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OpenMyChrome.ink)
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                OpenMyChrome.raise,
                in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                    .strokeBorder(keyFocused ? OpenMyChrome.muted : OpenMyChrome.fieldBorder)
            }
            .accessibilityLabel(DigestSettingsCopy.keyLabel)
    }

    private var toneColor: Color {
        switch model.statusTone {
        case .positive: return OpenMyChrome.success
        case .negative: return OpenMyChrome.rec
        case .neutral: return OpenMyChrome.faint
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OpenMyChrome.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
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
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(OpenMyChrome.muted)
                .frame(width: 36, alignment: .leading)
            content()
        }
    }
}
