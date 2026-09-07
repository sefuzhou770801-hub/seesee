import Foundation

@main
struct DigestSettingsCheck {
    @MainActor
    static func main() async {
        checkCopy()
        checkMasking()
        checkVerdictClassification()
        await checkModelReadWrite()
        await checkAutoVerification()
        await checkEnvironmentKey()
        await checkSessionRefresh()
        print("digest_settings_check=passed")
    }

    private static func checkCopy() {
        precondition(DigestSettingsCopy.openSettingsTitle == "打开设置…")
        precondition(DigestCopy.viewConfigTitle == DigestSettingsCopy.openSettingsTitle, "侧栏按钮与设置文案一致")
        precondition(DigestSettingsCopy.gearTitle == "设置")
        precondition(DigestSettingsCopy.applyURL(.gemini).host == "aistudio.google.com")
        precondition(DigestSettingsCopy.applyURL(.anthropic).host == "console.anthropic.com")
        precondition(DigestSettingsCopy.applyTitle(.gemini) == "去申请 Gemini 密钥")
        precondition(DigestSettingsCopy.providerNote(.gemini).contains("免费"))
        precondition(DigestSettingsCopy.defaultsKey(.gemini) == DigestGeminiAPIKey.defaultsKey)
        precondition(DigestSettingsCopy.defaultsKey(.anthropic) == WatchQAAPIKey.defaultsKey)
        precondition(!DigestSettingsCopy.intro.contains("defaults"), "设置文案不得再让用户去终端")
        let home = FileManager.default.homeDirectoryForCurrentUser
        precondition(DigestSettingsCopy.displayPath(home.appendingPathComponent("Movies/Replay")) == "~/Movies/Replay")
        precondition(DigestSettingsCopy.displayPath(URL(fileURLWithPath: "/Volumes/X/Replay")) == "/Volumes/X/Replay")
        precondition(DigestSettingsCopy.serviceStatus("  ") == "服务返回错误")
        precondition(DigestSettingsCopy.serviceStatus("HTTP 500") == "服务返回错误：HTTP 500")
    }

    @MainActor
    private static func checkMasking() {
        precondition(DigestSettingsModel.masked("AIzaSyCIseds1p7m5KScZjGKhMIEAin7G7mQgmg") == "AIza••••••Qgmg", "头四位尾四位中间六点")
        precondition(DigestSettingsModel.masked("  sk-ant-api03-abcdefgh  ") == "sk-a••••••efgh", "先去首尾空白")
        precondition(DigestSettingsModel.masked("short") == "•••••", "短密钥全遮")
        precondition(DigestSettingsModel.masked("ab") == "••••", "至少四个点")
        precondition(DigestSettingsModel.masked("123456789012") == "••••••••••••", "12 位及以下全遮")
    }

    private static func checkVerdictClassification() {
        precondition(DigestKeyVerification.classify(DigestClientError(message: "x", status: 401, body: "authentication_error")) == .invalid)
        precondition(DigestKeyVerification.classify(DigestClientError(message: "x", status: 400, body: "API key not valid")) == .invalid)
        precondition(DigestKeyVerification.classify(DigestClientError(message: "x", status: 403, body: "")) == .invalid)
        precondition(DigestKeyVerification.classify(DigestClientError(message: "x", status: 429, body: "RESOURCE_EXHAUSTED")) == .quota)
        precondition(
            DigestKeyVerification.classify(DigestClientError(message: "x", status: 400, body: "Your credit balance is too low")) == .quota,
            "Anthropic 余额不足是 400，按额度归类"
        )
        precondition(DigestKeyVerification.classify(DigestClientError(message: "x", status: 500, body: "")) == .service("HTTP 500"))
        precondition(DigestKeyVerification.classify(URLError(.notConnectedToInternet)) == .network)
        precondition(DigestKeyVerification.classify(URLError(.timedOut)) == .network)
        precondition(DigestKeyVerification.classify(DigestClientError(message: "这次没写成")) == .service("这次没写成"), "没有状态码的本地错误归服务错误")
        precondition(
            DigestKeyVerification.classify(DigestClientError(message: "这次没写成", status: 200, body: "{}")) == .valid,
            "服务接受了请求只是没回文字，密钥算可用"
        )
        precondition(DigestKeyVerification.probeMaxTokens <= 64, "验证请求要小")
    }

    @MainActor
    private static func checkModelReadWrite() async {
        let suite = "digest-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = DigestSettingsModel(defaults: defaults, environment: [:], verifier: { _, _ in .valid })
        model.debounce = 0
        precondition(model.provider == .gemini, "首次打开缺省 Gemini")
        precondition(model.key.isEmpty)
        precondition(!model.hasKey)
        precondition(model.verification == .idle, "没有密钥不验证")
        precondition(model.status == DigestSettingsCopy.emptyStatus)
        precondition(model.statusTone == .neutral)

        model.key = "  AIza-test-key-12345 \n"
        precondition(defaults.string(forKey: DigestGeminiAPIKey.defaultsKey) == "AIza-test-key-12345", "去掉首尾空白后写入偏好")
        precondition(DigestAPIKey.resolve(provider: .gemini, defaults: defaults, environment: [:]) == "AIza-test-key-12345")
        precondition(model.hasKey)
        precondition(model.maskedKey == "AIza••••••2345")
        await model.awaitVerification()
        precondition(model.status == DigestSettingsCopy.validStatus)
        precondition(model.statusTone == .positive)

        model.provider = .anthropic
        precondition(defaults.string(forKey: DigestProvider.defaultsKey) == "anthropic", "切换服务写入偏好")
        precondition(model.key.isEmpty, "切到 Anthropic 后显示该服务自己的密钥（空）")
        precondition(!model.hasKey)
        precondition(model.verification == .idle)
        precondition(defaults.string(forKey: DigestGeminiAPIKey.defaultsKey) == "AIza-test-key-12345", "切换服务不得清掉另一家的密钥")

        model.key = "sk-ant-1"
        precondition(DigestAPIKey.resolve(provider: .anthropic, defaults: defaults, environment: [:]) == "sk-ant-1")
        precondition(DigestProvider.resolve(defaults: defaults, environment: [:]) == .anthropic)

        model.provider = .gemini
        precondition(model.key == "AIza-test-key-12345", "切回 Gemini 带出原密钥")
        await model.awaitVerification()
        precondition(model.status == DigestSettingsCopy.validStatus, "切回后立即重新验证")

        model.key = "   "
        precondition(defaults.string(forKey: DigestGeminiAPIKey.defaultsKey) == nil, "清空即删除")
        precondition(!model.hasKey)
        precondition(model.verification == .idle)
        precondition(model.status == DigestSettingsCopy.emptyStatus)

        let reopened = DigestSettingsModel(defaults: defaults, environment: [:], verifier: { _, _ in .valid })
        precondition(reopened.provider == .gemini, "重开读回上次选择")
        precondition(reopened.key.isEmpty)
    }

    @MainActor
    private static func checkAutoVerification() async {
        let suite = "digest-settings-verify-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        final class Probe: @unchecked Sendable {
            var calls: [(DigestProviderKind, String)] = []
            var verdict: DigestKeyVerdict = .invalid
        }
        let probe = Probe()
        let model = DigestSettingsModel(defaults: defaults, environment: [:], verifier: { provider, key in
            probe.calls.append((provider, key))
            return probe.verdict
        })
        model.debounce = 0.05

        model.key = "AIza-wrong-key-000"
        precondition(model.verification == .verifying)
        precondition(model.status == DigestSettingsCopy.verifyingStatus)
        precondition(model.statusTone == .neutral)
        await model.awaitVerification()
        precondition(probe.calls.count == 1, "一次输入只验证一次，实际 \(probe.calls.count)")
        precondition(probe.calls[0].0 == .gemini && probe.calls[0].1 == "AIza-wrong-key-000", "验证用的是修剪后的密钥与当前服务")
        precondition(model.status == DigestSettingsCopy.invalidStatus)
        precondition(model.statusTone == .negative)

        // 连续击键只在停下来后验证一次
        probe.verdict = .quota
        model.key = "AIza-typing-1"
        model.key = "AIza-typing-12"
        model.key = "AIza-typing-123"
        await model.awaitVerification()
        precondition(probe.calls.count == 2, "连续输入合并成一次验证，实际 \(probe.calls.count)")
        precondition(probe.calls.last?.1 == "AIza-typing-123")
        precondition(model.status == DigestSettingsCopy.quotaStatus)

        probe.verdict = .network
        model.key = "AIza-net"
        await model.awaitVerification()
        precondition(model.status == DigestSettingsCopy.networkStatus)
        precondition(model.statusTone == .negative)

        probe.verdict = .service("HTTP 503")
        model.key = "AIza-svc"
        await model.awaitVerification()
        precondition(model.status == "服务返回错误：HTTP 503")

        // 已有密钥时打开设置页：立刻验证一次
        probe.verdict = .valid
        let before = probe.calls.count
        let opened = DigestSettingsModel(defaults: defaults, environment: [:], verifier: { provider, key in
            probe.calls.append((provider, key))
            return probe.verdict
        })
        precondition(opened.verification == .verifying, "打开时有密钥就验证")
        await opened.awaitVerification()
        precondition(probe.calls.count == before + 1)
        precondition(opened.status == DigestSettingsCopy.validStatus)
    }

    @MainActor
    private static func checkEnvironmentKey() async {
        let suite = "digest-settings-env-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        final class Seen: @unchecked Sendable { var key: String? }
        let seen = Seen()
        let model = DigestSettingsModel(defaults: defaults, environment: ["GEMINI_API_KEY": "from-env"], verifier: { _, key in
            seen.key = key
            return .valid
        })
        precondition(model.provider == .gemini)
        precondition(model.key.isEmpty, "环境变量密钥不回填到输入框")
        precondition(model.hasKey)
        await model.awaitVerification()
        precondition(seen.key == "from-env", "环境变量密钥也验证")
        precondition(model.status == DigestSettingsCopy.validStatus)
    }

    @MainActor
    private static func checkSessionRefresh() async {
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

        let settings = DigestSettingsModel(defaults: defaults, environment: [:], verifier: { _, _ in .valid })
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
        await settings.awaitVerification()
    }
}
