import AppKit
import AVFoundation
import SwiftUI

struct WatchQAClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum WatchQAFrameCapture {
    static let missingHint = "没拿到当前画面，按回车重试"

    static func jpegBase64(
        asset: AVAsset,
        time: CMTime,
        maxWidth: Double = WatchQARequestBuilder.frameMaxWidth
    ) -> String? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let data = representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        ) else {
            return nil
        }
        return data.base64EncodedString()
    }
}

enum WatchQAClient {
    /// 流式结果：任务内部累积的完整回答，以及是否收到 `message_stop` 完成事件。
    struct StreamResult {
        let text: String
        let completed: Bool
    }

    @discardableResult
    static func stream(
        input: WatchQARequestInput,
        apiKey: String,
        session: URLSession = .shared,
        onDelta: @escaping (String) -> Void
    ) async throws -> StreamResult {
        var request = URLRequest(url: WatchQARequestBuilder.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(WatchQARequestBuilder.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        guard let httpBody = WatchQARequestBuilder.jsonData(from: input) else {
            throw WatchQAClientError(message: WatchQAFrameCapture.missingHint)
        }
        request.httpBody = httpBody

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 2_000 { break }
            }
            throw WatchQAClientError(message: httpErrorMessage(status: http.statusCode, body: body))
        }

        // 回答在流任务内部独立累积，不依赖界面上可变的 answer 状态。
        // 逐行判定复用 WatchQASSEParser.step，与 reduce（及其测试）同一规则。
        var accumulated = ""
        for try await line in bytes.lines {
            let step = WatchQASSEParser.step(line: line)
            // 先认完成事件：收到 message_stop 立即返回完整回答，不再检查取消，
            // 保证「回答已完成但浮层刚被关闭」时，已完成的记录仍会落盘。
            if case .completed = step {
                return StreamResult(text: accumulated, completed: true)
            }
            try Task.checkCancellation()
            if case .delta(let delta) = step {
                accumulated += delta
                await MainActor.run {
                    onDelta(delta)
                }
            }
        }
        return StreamResult(text: accumulated, completed: false)
    }

    private static func httpErrorMessage(status: Int, body: String) -> String {
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }
        return "问答请求失败（\(status)）"
    }
}

@MainActor
final class WatchQASession: ObservableObject {
    static let persistFailedHint = "回答没有存上，可重试"
    static let incompleteHint = "回答没说完就断了，没有存上，可重试"

    /// 浮层的两态：正常提问，或缺密钥时的界面内引导。
    enum Mode: Equatable {
        case ask
        case keyGuide
    }

    @Published var isPresented = false
    @Published var mode: Mode = .ask
    @Published var question = ""
    @Published var answer = ""
    @Published var statusMessage: String?
    @Published var isStreaming = false
    /// 引导态里粘贴的密钥草稿，以及「不像 sk- 开头」的一次性提醒。
    @Published var keyDraft = ""
    @Published var keyPrefixWarning: String?

    private var streamTask: Task<Void, Never>?
    /// 密钥的读取与写入抽成注入点：生产走 UserDefaults + 环境变量，测试可注入内存替身，
    /// 不依赖进程级 env 与共享 defaults。
    private let resolveKey: () -> String?
    private let persistKey: (String) -> Void

    init(
        resolveKey: @escaping () -> String? = { WatchQAAPIKey.resolve() },
        persistKey: @escaping (String) -> Void = { WatchQAAPIKey.save($0) }
    ) {
        self.resolveKey = resolveKey
        self.persistKey = persistKey
    }

    /// 保存按钮是否可点：草稿去空白后非空即可点。
    var canSaveKey: Bool { WatchQAKeyEntry.canSave(keyDraft) }

    func present() {
        guard !isPresented else { return }
        isPresented = true
        question = ""
        answer = ""
        isStreaming = false
        streamTask?.cancel()
        streamTask = nil
        statusMessage = nil
        keyDraft = ""
        keyPrefixWarning = nil
        // 已配密钥（defaults 或环境变量任一）直接进提问态，缺密钥才进引导态。
        mode = resolveKey() == nil ? .keyGuide : .ask
    }

    @discardableResult
    func dismiss(resume: Bool = true) -> Bool {
        guard isPresented else { return false }
        cancel()
        isPresented = false
        mode = .ask
        question = ""
        answer = ""
        statusMessage = nil
        keyDraft = ""
        keyPrefixWarning = nil
        if resume {
            PlaybackCommandCenter.shared.play()
        }
        return true
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    /// 引导态点「保存并开始提问」：写入密钥并当场切回提问态（焦点落回问题框由界面处理）。
    /// 不以 sk- 开头时首次点击只提醒，再点一次仍保存，不做网络校验。
    func saveKey() {
        let normalized = WatchQAKeyEntry.normalized(keyDraft)
        guard !normalized.isEmpty else { return }
        if WatchQAKeyEntry.needsPrefixWarning(keyDraft), keyPrefixWarning == nil {
            keyPrefixWarning = WatchQAKeyEntry.prefixWarning
            return
        }
        persistKey(normalized)
        mode = .ask
        keyDraft = ""
        keyPrefixWarning = nil
        statusMessage = nil
        question = ""
        answer = ""
    }

    /// 缺密钥时进引导态：停掉在跑的流，清掉提问态残留，让界面替换为引导内容。
    private func enterKeyGuide() {
        cancel()
        mode = .keyGuide
        keyDraft = ""
        keyPrefixWarning = nil
        statusMessage = nil
        answer = ""
    }

    func submit(
        item: WatchItem,
        snapshot: PlaybackSnapshot,
        subtitleTrack: VideoSubtitleTrack?,
        sidecar: WatchQASidecar? = nil,
        onPersisted: ((WatchQAEntry) -> Void)? = nil
    ) {
        // 密钥失效被删（resolve 返回 nil）时切入引导态，不再只弹一行状态文字。
        guard let apiKey = resolveKey() else {
            enterKeyGuide()
            return
        }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let currentTime = snapshot.currentTime
        let askedAt = Date()
        let title = item.title
        let author = item.author
        let chapters = item.availableChapters
        let cues = subtitleTrack?.cues(
            around: currentTime,
            window: WatchQARequestBuilder.subtitleWindow
        ) ?? []
        let frameSource: (asset: AVAsset, time: CMTime)? = {
            guard let player = PlaybackCommandCenter.shared.activeRoutePlayer,
                  let asset = player.currentItem?.asset else { return nil }
            return (asset, player.currentTime())
        }()

        answer = ""
        statusMessage = nil
        isStreaming = true
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            let jpeg = await Task.detached {
                guard let frameSource else { return nil as String? }
                return WatchQAFrameCapture.jpegBase64(asset: frameSource.asset, time: frameSource.time)
            }.value
            guard !Task.isCancelled else { return }
            guard let jpeg, !jpeg.isEmpty else {
                self?.statusMessage = WatchQAFrameCapture.missingHint
                self?.isStreaming = false
                return
            }
            let input = WatchQARequestInput(
                title: title,
                author: author,
                chapterTitle: WatchQAChapter.title(at: currentTime, in: chapters),
                currentTime: currentTime,
                cues: cues,
                jpegBase64: jpeg,
                question: trimmed
            )
            let result: WatchQAClient.StreamResult
            do {
                result = try await WatchQAClient.stream(input: input, apiKey: apiKey) { delta in
                    self?.answer += delta
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.statusMessage = error.localizedDescription
                self?.isStreaming = false
                return
            }
            self?.isStreaming = false
            // 用流任务内部累积的不可变文本落盘，不读可变界面状态 answer（关闭浮层会清空它）。
            guard WatchQAPersistDecision.shouldPersist(
                completed: result.completed,
                answer: result.text
            ) else {
                // 流被截断、没等到 message_stop：半截回答不落盘，但明确提示，不静默丢。
                if !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self?.statusMessage = WatchQASession.incompleteHint
                }
                return
            }
            guard let sidecar else { return }
            let entry = WatchQAEntry(
                id: UUID(),
                time: currentTime,
                question: trimmed,
                answer: result.text,
                askedAt: askedAt,
                model: WatchQARequestBuilder.model
            )
            // 落盘经串行 actor，且不响应取消：完成的记录必写，关闭浮层只影响显示。
            switch await WatchQAStore.shared.persist(entry, to: sidecar) {
            case .persisted:
                onPersisted?(entry)
            case .failed:
                self?.statusMessage = WatchQASession.persistFailedHint
            case .dropped:
                break
            }
        }
    }
}

struct WatchQAOverlay: View {
    @ObservedObject var session: WatchQASession
    var isQuestionFieldFocused: FocusState<Bool>.Binding
    var isKeyFieldFocused: FocusState<Bool>.Binding
    let onSaveKey: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        Group {
            switch session.mode {
            case .keyGuide:
                keyGuide
            case .ask:
                askPanel
            }
        }
        .padding(14)
        .frame(maxWidth: 640)
        .background(
            OpenMyChrome.canvas.opacity(0.94),
            in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusXl, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OpenMyChrome.radiusXl, style: .continuous)
                .strokeBorder(OpenMyChrome.hair)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var askPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = session.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(OpenMyChrome.ink.opacity(0.86))
                    .textSelection(.enabled)
            }

            if session.isStreaming || !session.answer.isEmpty {
                ScrollView {
                    Text(session.answer.isEmpty ? "正在回答…" : session.answer)
                        .font(.body)
                        .foregroundStyle(OpenMyChrome.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }

            HStack(spacing: 8) {
                TextField("问画面或字幕…", text: $session.question)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(OpenMyChrome.ink)
                    .focused(isQuestionFieldFocused)
                    .onSubmit(onSubmit)

                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(OpenMyChrome.ink.opacity(canSubmit ? 1 : 0.35))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .help("发送（回车）")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                OpenMyChrome.raise,
                in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusLg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OpenMyChrome.radiusLg, style: .continuous)
                    .strokeBorder(OpenMyChrome.fieldBorder)
            }
        }
    }

    // 临时占位布局：仅用于打通「缺密钥切引导态」的状态骨架，让 present/submit/saveKey
    // 全链路可编译、可测、可手动走通。最终形态（可能改为居中模态窗口）与文案待原型定稿后重做，
    // 届时只改本视图，底层状态机与密钥写入逻辑不动。
    private var keyGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("看时问答需要 Anthropic API 密钥")
                    .font(.headline)
                    .foregroundStyle(OpenMyChrome.ink)
                Text("提问时会把当前画面和前后字幕发送给 Claude 回答。")
                    .font(.callout)
                    .foregroundStyle(OpenMyChrome.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("sk-ant-…", text: $session.keyDraft)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(OpenMyChrome.ink)
                .focused(isKeyFieldFocused)
                .onSubmit(onSaveKey)
                .onChange(of: session.keyDraft) { _ in
                    // 改动草稿即重新判定，让「以 sk- 开头」提醒随输入复位。
                    session.keyPrefixWarning = nil
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    OpenMyChrome.raise,
                    in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusLg, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: OpenMyChrome.radiusLg, style: .continuous)
                        .strokeBorder(OpenMyChrome.fieldBorder)
                }

            if let warning = session.keyPrefixWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(OpenMyChrome.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onSaveKey) {
                Text("保存并开始提问")
                    .font(.body.weight(.medium))
                    .foregroundStyle(OpenMyChrome.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        OpenMyChrome.ink,
                        in: RoundedRectangle(cornerRadius: OpenMyChrome.radiusMd, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: OpenMyChrome.radiusMd, style: .continuous)
                            .strokeBorder(OpenMyChrome.hair)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!session.canSaveKey)
            .opacity(session.canSaveKey ? 1 : 0.5)

            Text("也可以在终端执行：\(WatchQAAPIKey.terminalCommand)")
                .font(.footnote)
                .foregroundStyle(OpenMyChrome.faint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canSubmit: Bool {
        !session.isStreaming
            && !session.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
