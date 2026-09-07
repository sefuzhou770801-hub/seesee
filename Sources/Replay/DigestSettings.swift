import AppKit
import Foundation

enum DigestSettingsCopy {
    static let windowTitle = "设置"
    static let sectionTitle = "AI 密钥"
    static let intro = "解释与目录需要一把模型密钥。密钥只保存在这台 Mac 上，只在你点「解释」或「生成目录」时把那段字幕发给模型。"
    static let providerLabel = "服务"
    static let keyLabel = "密钥"
    static let keyPlaceholder = "粘贴密钥"
    static let savedStatus = "已保存，解释与目录可用"
    static let emptyStatus = "还没有密钥"
    static let environmentStatus = "正在使用环境变量里的密钥"
    static let openSettingsTitle = DigestCopy.viewConfigTitle

    static func providerTitle(_ provider: DigestProviderKind) -> String {
        switch provider {
        case .gemini: return "Gemini"
        case .anthropic: return "Anthropic"
        }
    }

    static func providerNote(_ provider: DigestProviderKind) -> String {
        switch provider {
        case .gemini: return "Google AI Studio 免费申请，不用绑卡。"
        case .anthropic: return "Anthropic Console 申请，按用量付费。"
        }
    }

    static func applyTitle(_ provider: DigestProviderKind) -> String {
        "去申请 \(providerTitle(provider)) 密钥"
    }

    static func applyURL(_ provider: DigestProviderKind) -> URL {
        switch provider {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }

    static func defaultsKey(_ provider: DigestProviderKind) -> String {
        switch provider {
        case .gemini: return DigestGeminiAPIKey.defaultsKey
        case .anthropic: return WatchQAAPIKey.defaultsKey
        }
    }
}

/// 设置窗口的状态：服务选择与该服务的密钥，改动即写入偏好；会话经 UserDefaults 通知感知。
@MainActor
final class DigestSettingsModel: ObservableObject {
    @Published var provider: DigestProviderKind {
        didSet {
            guard !isLoading, provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: DigestProvider.defaultsKey)
            reloadKey()
        }
    }
    @Published var key: String {
        didSet {
            guard !isLoading else { return }
            persistKey()
        }
    }

    let defaults: UserDefaults
    let environment: [String: String]
    private var isLoading = false

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.environment = environment
        let resolved = DigestProvider.resolve(defaults: defaults, environment: environment)
        provider = resolved
        key = Self.storedKey(provider: resolved, defaults: defaults)
    }

    static func storedKey(provider: DigestProviderKind, defaults: UserDefaults) -> String {
        defaults.string(forKey: DigestSettingsCopy.defaultsKey(provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasKey: Bool {
        DigestAPIKey.resolve(provider: provider, defaults: defaults, environment: environment) != nil
    }

    var status: String {
        if !trimmedKey.isEmpty { return DigestSettingsCopy.savedStatus }
        if hasKey { return DigestSettingsCopy.environmentStatus }
        return DigestSettingsCopy.emptyStatus
    }

    var isStatusPositive: Bool { hasKey }

    var applyTitle: String { DigestSettingsCopy.applyTitle(provider) }
    var providerNote: String { DigestSettingsCopy.providerNote(provider) }

    func openApplyPage() {
        NSWorkspace.shared.open(DigestSettingsCopy.applyURL(provider))
    }

    private func reloadKey() {
        isLoading = true
        key = Self.storedKey(provider: provider, defaults: defaults)
        isLoading = false
    }

    private func persistKey() {
        let value = trimmedKey
        let storageKey = DigestSettingsCopy.defaultsKey(provider)
        if value.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(value, forKey: storageKey)
        }
    }
}
