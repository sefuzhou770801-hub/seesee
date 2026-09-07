import AppKit
import Foundation

enum DigestSettingsCopy {
    static let windowTitle = "设置"
    static let sectionTitle = "AI 密钥"
    static let intro = "解释与目录需要一把模型密钥。密钥只保存在这台 Mac 上，只在你点「解释」或「生成目录」时把那段字幕发给模型。"
    static let providerLabel = "服务"
    static let keyLabel = "密钥"
    static let keyPlaceholder = "粘贴密钥"
    static let savedStatus = "已保存"
    static let emptyStatus = "还没有密钥"
    static let environmentStatus = "正在使用环境变量里的密钥"
    static let verifyingStatus = "正在验证…"
    static let validStatus = "密钥可用，解释与目录就绪"
    static let invalidStatus = "密钥无效，请核对后重新粘贴"
    static let quotaStatus = "这把密钥没有额度了"
    static let networkStatus = "连不上服务，稍后再试"
    static let openSettingsTitle = DigestCopy.viewConfigTitle
    static let gearTitle = "设置"
    static let dataSectionTitle = "数据位置"
    static let mediaLabel = "影片"
    static let revealTitle = "打开"

    static func serviceStatus(_ detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "服务返回错误" }
        return "服务返回错误：\(trimmed.prefix(80))"
    }

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

    /// 家目录缩写成 ~，路径给人看。
    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

enum DigestKeyVerdict: Equatable {
    case valid
    case invalid
    case quota
    case network
    case service(String)
}

enum DigestKeyVerification {
    static let probeSystem = "Reply with the single word OK."
    static let probeUser = "OK"
    static let probeMaxTokens = 32

    /// 把请求层错误归成用户能理解的四类。
    static func classify(_ error: Error) -> DigestKeyVerdict {
        if let client = error as? DigestClientError, let status = client.status {
            // 服务已接受请求（2xx），只是这次没回出文字：密钥本身没问题。
            if (200...299).contains(status) { return .valid }
            let body = (client.body ?? "").lowercased()
            let quotaWords = ["quota", "exhausted", "credit", "balance", "billing", "rate limit", "rate_limit"]
            if status == 429 || quotaWords.contains(where: { body.contains($0) }) {
                return .quota
            }
            if [400, 401, 403].contains(status) {
                return .invalid
            }
            return .service("HTTP \(status)")
        }
        if error is URLError { return .network }
        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain { return .network }
        return .service(error.localizedDescription)
    }

    static func verify(provider: DigestProviderKind, key: String) async -> DigestKeyVerdict {
        do {
            _ = try await DigestAPIClient.complete(
                system: probeSystem,
                user: probeUser,
                apiKey: key,
                maxTokens: probeMaxTokens,
                provider: provider
            )
            return .valid
        } catch {
            return classify(error)
        }
    }
}

typealias DigestKeyVerifier = @Sendable (DigestProviderKind, String) async -> DigestKeyVerdict

enum DigestSettingsTone: Equatable {
    case neutral
    case positive
    case negative
}

/// 设置窗口的状态：服务选择与该服务的密钥，改动即写入偏好并自动验证；会话经 UserDefaults 通知感知。
@MainActor
final class DigestSettingsModel: ObservableObject {
    enum Verification: Equatable {
        case idle
        case verifying
        case done(DigestKeyVerdict)
    }

    @Published var provider: DigestProviderKind {
        didSet {
            guard !isLoading, provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: DigestProvider.defaultsKey)
            reloadKey()
            scheduleVerification(delay: 0)
        }
    }
    @Published var key: String {
        didSet {
            guard !isLoading else { return }
            persistKey()
            scheduleVerification(delay: debounce)
        }
    }
    @Published private(set) var verification: Verification = .idle

    let defaults: UserDefaults
    let environment: [String: String]
    let mediaFolder: URL?
    var debounce: TimeInterval = 1.0
    private let verifier: DigestKeyVerifier
    private var isLoading = false
    private var verifyTask: Task<Void, Never>?
    private(set) var verificationCount = 0

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        mediaFolder: URL? = nil,
        verifier: @escaping DigestKeyVerifier = { await DigestKeyVerification.verify(provider: $0, key: $1) }
    ) {
        self.defaults = defaults
        self.environment = environment
        self.mediaFolder = mediaFolder
        self.verifier = verifier
        let resolved = DigestProvider.resolve(defaults: defaults, environment: environment)
        provider = resolved
        key = Self.storedKey(provider: resolved, defaults: defaults)
        scheduleVerification(delay: 0)
    }

    static func storedKey(provider: DigestProviderKind, defaults: UserDefaults) -> String {
        defaults.string(forKey: DigestSettingsCopy.defaultsKey(provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 不编辑时的显示：头四位、尾四位，中间六个圆点；太短就全遮。
    static func masked(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else {
            return String(repeating: "•", count: max(trimmed.count, 4))
        }
        return String(trimmed.prefix(4)) + "••••••" + String(trimmed.suffix(4))
    }

    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var maskedKey: String { Self.masked(key) }

    /// 实际生效的密钥：输入框里的优先，其次环境变量。
    var effectiveKey: String? {
        DigestAPIKey.resolve(provider: provider, defaults: defaults, environment: environment)
    }

    var hasKey: Bool { effectiveKey != nil }

    var status: String {
        switch verification {
        case .verifying:
            return DigestSettingsCopy.verifyingStatus
        case .done(let verdict):
            switch verdict {
            case .valid: return DigestSettingsCopy.validStatus
            case .invalid: return DigestSettingsCopy.invalidStatus
            case .quota: return DigestSettingsCopy.quotaStatus
            case .network: return DigestSettingsCopy.networkStatus
            case .service(let detail): return DigestSettingsCopy.serviceStatus(detail)
            }
        case .idle:
            if !trimmedKey.isEmpty { return DigestSettingsCopy.savedStatus }
            if hasKey { return DigestSettingsCopy.environmentStatus }
            return DigestSettingsCopy.emptyStatus
        }
    }

    var statusTone: DigestSettingsTone {
        switch verification {
        case .done(.valid): return .positive
        case .done: return .negative
        case .verifying, .idle: return .neutral
        }
    }

    var applyTitle: String { DigestSettingsCopy.applyTitle(provider) }
    var providerNote: String { DigestSettingsCopy.providerNote(provider) }
    var mediaPathText: String { mediaFolder.map(DigestSettingsCopy.displayPath) ?? "" }

    func openApplyPage() {
        NSWorkspace.shared.open(DigestSettingsCopy.applyURL(provider))
    }

    func revealMediaFolder() {
        guard let mediaFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([mediaFolder])
    }

    /// 等当前这轮验证结束（检查与证明图用）。
    func awaitVerification() async {
        await verifyTask?.value
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

    private func scheduleVerification(delay: TimeInterval) {
        verifyTask?.cancel()
        verifyTask = nil
        guard let candidate = effectiveKey else {
            verification = .idle
            return
        }
        verification = .verifying
        let provider = provider
        let verifier = verifier
        verifyTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            let verdict = await verifier(provider, candidate)
            guard !Task.isCancelled, let self else { return }
            self.verificationCount += 1
            self.verification = .done(verdict)
        }
    }
}
