import Foundation

@main
struct DigestSettingsCheck {
    @MainActor
    static func main() {
        checkCopy()
        checkModelReadWrite()
        checkEnvironmentKey()
        checkSessionRefresh()
        print("digest_settings_check=passed")
    }

    private static func checkCopy() {
        precondition(DigestSettingsCopy.openSettingsTitle == "打开设置…")
        precondition(DigestCopy.viewConfigTitle == DigestSettingsCopy.openSettingsTitle, "侧栏按钮与设置文案一致")
        precondition(DigestSettingsCopy.applyURL(.gemini).host == "aistudio.google.com")
        precondition(DigestSettingsCopy.applyURL(.anthropic).host == "console.anthropic.com")
        precondition(DigestSettingsCopy.applyTitle(.gemini) == "去申请 Gemini 密钥")
        precondition(DigestSettingsCopy.providerNote(.gemini).contains("免费"))
        precondition(DigestSettingsCopy.defaultsKey(.gemini) == DigestGeminiAPIKey.defaultsKey)
        precondition(DigestSettingsCopy.defaultsKey(.anthropic) == WatchQAAPIKey.defaultsKey)
        precondition(!DigestSettingsCopy.intro.contains("defaults"), "设置文案不得再让用户去终端")
    }

    @MainActor
    private static func checkModelReadWrite() {
        let suite = "digest-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DigestSettingsModel(defaults: defaults, environment: [:])
        precondition(model.provider == .gemini, "首次打开缺省 Gemini")
        precondition(model.key.isEmpty)
        precondition(!model.hasKey)
        precondition(model.status == DigestSettingsCopy.emptyStatus)
        precondition(!model.isStatusPositive)

        model.key = "  AIza-test-key \n"
        precondition(defaults.string(forKey: DigestGeminiAPIKey.defaultsKey) == "AIza-test-key", "去掉首尾空白后写入偏好")
        precondition(DigestAPIKey.resolve(provider: .gemini, defaults: defaults, environment: [:]) == "AIza-test-key")
        precondition(model.hasKey)
        precondition(model.status == DigestSettingsCopy.savedStatus)
        precondition(model.isStatusPositive)

        model.provider = .anthropic
        precondition(defaults.string(forKey: DigestProvider.defaultsKey) == "anthropic", "切换服务写入偏好")
        precondition(model.key.isEmpty, "切到 Anthropic 后显示该服务自己的密钥（空）")
        precondition(!model.hasKey)
        precondition(defaults.string(forKey: DigestGeminiAPIKey.defaultsKey) == "AIza-test-key", "切换服务不得清掉另一家的密钥")

        model.key = "sk-ant-1"
        precondition(DigestAPIKey.resolve(provider: .anthropic, defaults: defaults, environment: [:]) == "sk-ant-1")
        precondition(DigestProvider.resolve(defaults: defaults, environment: [:]) == .anthropic)

        model.provider = .gemini
        precondition(model.key == "AIza-test-key", "切回 Gemini 带出原密钥")

        model.key = "   "
        precondition(defaults.string(forKey: DigestGeminiAPIKey.defaultsKey) == nil, "清空即删除")
        precondition(!model.hasKey)
        precondition(model.status == DigestSettingsCopy.emptyStatus)

        let reopened = DigestSettingsModel(defaults: defaults, environment: [:])
        precondition(reopened.provider == .gemini, "重开读回上次选择")
        precondition(reopened.key.isEmpty)
    }

    @MainActor
    private static func checkEnvironmentKey() {
        let suite = "digest-settings-env-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DigestSettingsModel(defaults: defaults, environment: ["GEMINI_API_KEY": "from-env"])
        precondition(model.provider == .gemini)
        precondition(model.key.isEmpty, "环境变量密钥不回填到输入框")
        precondition(model.hasKey)
        precondition(model.status == DigestSettingsCopy.environmentStatus)
        precondition(model.isStatusPositive)
    }

    @MainActor
    private static func checkSessionRefresh() {
        let suite = "digest-settings-session-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = DigestSession()
        session.apiKeyDefaults = defaults
        session.apiKeyEnvironment = [:]
        precondition(!session.hasAPIKey)

        let cues = [VideoSubtitleCue(startTime: 0, endTime: 2, text: "hello\n你好")]
        session.ensureLoaded(itemID: UUID(), folder: FileManager.default.temporaryDirectory)
        session.generateOverview(title: "t", author: "a", duration: 2, cues: cues)
        precondition(session.overviewMessage == DigestCopy.missingKeyHint, "无密钥点生成目录：提示配置")
        precondition(session.shouldAutoGenerateOverview, "无密钥时记住要生成目录，密钥填好后补做")
        session.explainMessageByCue[0] = DigestCopy.missingKeyHint
        session.explainMessage = DigestCopy.missingKeyHint

        let revisionBefore = session.apiKeyRevision
        session.refreshAPIKeyState()
        precondition(session.apiKeyRevision == revisionBefore, "密钥有无没变，不推动视图刷新")
        precondition(session.overviewMessage == DigestCopy.missingKeyHint)

        let settings = DigestSettingsModel(defaults: defaults, environment: [:])
        settings.key = "AIza-live"
        session.refreshAPIKeyState()
        precondition(session.hasAPIKey)
        precondition(session.apiKeyRevision == revisionBefore + 1, "密钥出现后推动视图刷新")
        precondition(session.overviewMessage == nil, "密钥出现后撤掉目录处的配置提示")
        precondition(session.explainMessage == nil)
        precondition(session.explainMessageByCue.isEmpty, "密钥出现后撤掉各句的配置提示")
        precondition(session.shouldAutoGenerateOverview, "待补做标记保留给视图触发")

        session.refreshAPIKeyState()
        precondition(session.apiKeyRevision == revisionBefore + 1, "重复刷新不再递增")
    }
}
