import SwiftUI

struct DigestSettingsView: View {
    @StateObject private var model: DigestSettingsModel

    static let width: CGFloat = 460

    init(model: DigestSettingsModel? = nil) {
        _model = StateObject(wrappedValue: model ?? DigestSettingsModel())
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
                TextField("", text: $model.key, prompt: Text(""))
                    .overlay(alignment: .leading) {
                        if model.key.isEmpty {
                            Text(DigestSettingsCopy.keyPlaceholder)
                                .font(.system(size: 12))
                                .foregroundStyle(OpenMyChrome.faint)
                                .padding(.horizontal, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OpenMyChrome.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        OpenMyChrome.raise,
                        in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: OpenMyChrome.radiusSm, style: .continuous)
                            .strokeBorder(OpenMyChrome.fieldBorder)
                    }
                    .accessibilityLabel(DigestSettingsCopy.keyLabel)
            }

            row("") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isStatusPositive ? OpenMyChrome.success : OpenMyChrome.faint)
                        .frame(width: 6, height: 6)
                    Text(model.status)
                        .font(.system(size: 11))
                        .foregroundStyle(OpenMyChrome.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.status)
                Spacer(minLength: 8)
                Button(action: model.openApplyPage) {
                    Text(model.applyTitle)
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
                .help(model.applyTitle)
                .accessibilityLabel(model.applyTitle)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(OpenMyChrome.canvas)
        .navigationTitle(DigestSettingsCopy.windowTitle)
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
