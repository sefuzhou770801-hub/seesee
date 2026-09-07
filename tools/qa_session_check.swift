import AVFoundation
import CoreVideo
import Foundation

// MARK: - 测试替身
//
// 只提供 WatchQASession.swift 编译所需的最小面，避免把 2000 行 LocalVideoPlayer.swift 及其
// AVKit / MediaPlayer 依赖拖进这个校验。生产代码不改，替身只在测试目标里。

struct PlaybackSnapshot { var currentTime: Double }

final class PlaybackCommandCenter: @unchecked Sendable {
    static let shared = PlaybackCommandCenter()
    var testPlayer: AVPlayer?
    var activeRoutePlayer: AVPlayer? { testPlayer }
    func play() {}
}

/// 为 `URLSession`（含 `.shared`）提供**可分段**的 SSE 响应，驱动真实的 `WatchQAClient.stream`。
/// `gateAfter >= 0` 时，交付该段后阻塞在 `gate` 上，给测试留出交错点（放行前先 dismiss）。
final class MockSSEProtocol: URLProtocol, @unchecked Sendable {
    // 串行测试：每次请求前设好，请求期间不变。
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var segments: [String] = []
    nonisolated(unsafe) static var gateAfter = -1
    nonisolated(unsafe) static var gate = DispatchSemaphore(value: 0)

    /// 便捷：一次性整段交付，无交错点。
    static func setFullBody(status: Int, body: String) {
        Self.status = status
        Self.segments = [body]
        Self.gateAfter = -1
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.anthropic.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for (index, segment) in Self.segments.enumerated() {
            client?.urlProtocol(self, didLoad: Data(segment.utf8))
            if index == Self.gateAfter { Self.gate.wait() }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// 记录生产 onPersisted 回调是否被触发。只在 MainActor 上读写。
final class Recorder: @unchecked Sendable {
    var entry: WatchQAEntry?
}

@main
struct QASessionCheck {
    static func main() async throws {
        await checkPresentHonorsAvailability()

        // 真实流式代码：完成事件识别与累积（注入 mock session，不碰真实网络）。
        try await checkStreamCompletesOnMessageStop()
        try await checkStreamStopsAtMessageStop()
        try await checkStreamTruncationNotCompleted()
        try await checkStreamHTTPErrorThrows()

        // 真实生产事件链：submit → 截帧 → 流式 → 落盘 → onPersisted 分支。
        URLProtocol.registerClass(MockSSEProtocol.self)
        defer { URLProtocol.unregisterClass(MockSSEProtocol.self) }
        let video = try await makeTinyVideo()
        defer { try? FileManager.default.removeItem(at: video) }

        try await checkSubmitPersistsAndFiresOnPersisted(video: video)
        try await checkSubmitWriteFailureDoesNotFireOnPersisted(video: video)
        try await checkSubmitDroppedWhenDeletedDoesNotFire(video: video)
        try await checkCompletedAnswerSurvivesDismiss(video: video)

        print("qa_session_check=passed")
    }

    private static func checkPresentHonorsAvailability() async {
        await MainActor.run {
            let suite = "qa.session.availability.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }

            let session = WatchQASession()
            session.present(defaults: defaults)
            precondition(!session.isPresented, "开关关闭时不得唤起问答浮层")

            defaults.set(true, forKey: WatchQAAvailability.defaultsKey)
            session.present(defaults: defaults)
            precondition(session.isPresented, "开关打开时必须能唤起问答浮层")
            precondition(session.question.isEmpty, "无预填时问题须为空")

            session.present(prefill: "来源句：大家好。", defaults: defaults)
            precondition(session.question == "来源句：大家好。", "已打开时继续问须写入预填上下文")
            _ = session.dismiss(resume: false)

            session.present(prefill: "来源句：Hello world.", defaults: defaults)
            precondition(session.isPresented)
            precondition(session.question == "来源句：Hello world.", "打开浮层时须带上预填上下文")
            _ = session.dismiss(resume: false)
        }
    }

    // MARK: - 流式（真实 WatchQAClient.stream，注入 mock session）

    /// 收到 message_stop → 返回累积的完整回答并标记完成。
    private static func checkStreamCompletesOnMessageStop() async throws {
        let result = try await WatchQAClient.stream(
            input: input(),
            apiKey: "k",
            session: session(status: 200, body: delta("大") + delta("象") + stop)
        ) { _ in }
        precondition(result.text == "大象", "累积到 message_stop 前的全部文本")
        precondition(result.completed, "收到 message_stop 须标记完成")
    }

    /// message_stop 之后的增量必须忽略（字节流未结束也照样在完成事件处返回）。
    private static func checkStreamStopsAtMessageStop() async throws {
        let result = try await WatchQAClient.stream(
            input: input(),
            apiKey: "k",
            session: session(status: 200, body: delta("大") + stop + delta("象") + "data: [DONE]\n\n")
        ) { _ in }
        precondition(result.text == "大", "message_stop 后的增量不得再累积")
        precondition(result.completed)
    }

    /// 流被截断、没等到 message_stop：有文本但不算完成，据此不落盘。
    private static func checkStreamTruncationNotCompleted() async throws {
        let result = try await WatchQAClient.stream(
            input: input(),
            apiKey: "k",
            session: session(status: 200, body: delta("半") + delta("截"))
        ) { _ in }
        precondition(result.text == "半截")
        precondition(!result.completed, "无 message_stop 不得标记完成")
    }

    /// 非 2xx 状态：向上抛出带服务端消息的错误，不静默。
    private static func checkStreamHTTPErrorThrows() async throws {
        var thrown: Error?
        do {
            _ = try await WatchQAClient.stream(
                input: input(),
                apiKey: "k",
                session: session(status: 429, body: #"{"error":{"message":"限流了"}}"#)
            ) { _ in }
        } catch {
            thrown = error
        }
        precondition(thrown != nil, "HTTP 错误必须抛出")
        precondition(
            (thrown as? WatchQAClientError)?.message == "限流了",
            "错误消息须取自服务端 error.message"
        )
    }

    // MARK: - 生产事件链（真实 WatchQASession.submit）

    /// 收到 message_stop 后：完整回答经 actor 写入 sidecar，且 onPersisted 被回调。
    /// 覆盖「onPersisted 仅在真实写入成功后触发」与「message_stop → 落盘」两条链。
    private static func checkSubmitPersistsAndFiresOnPersisted(video: URL) async throws {
        MockSSEProtocol.setFullBody(status: 200, body: delta("画面里是大象") + stop)
        let sidecar = freshSidecar()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }
        let recorder = Recorder()

        _ = try await runSubmit(video: video, sidecar: sidecar, recorder: recorder) { session in
            recorder.entry != nil || session.statusMessage != nil
        }

        precondition(recorder.entry != nil, "写入成功后必须回调 onPersisted")
        precondition(recorder.entry?.answer == "画面里是大象", "落盘的是流内累积的完整回答")
        let loaded = WatchQAStore.load(from: sidecar.url)
        precondition(loaded.count == 1, "sidecar 须写入一条")
        precondition(loaded[0].answer == "画面里是大象", "sidecar 内容须是完整回答")
    }

    /// 写入失败（sidecar 指向不存在父目录）：不回调 onPersisted，浮层提示失败，磁盘无文件。
    private static func checkSubmitWriteFailureDoesNotFireOnPersisted(video: URL) async throws {
        MockSSEProtocol.setFullBody(status: 200, body: delta("会失败") + stop)
        let badFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-session-nodir-\(UUID().uuidString)", isDirectory: true)
        let sidecar = WatchQASidecar(itemID: UUID(), folder: badFolder)
        let recorder = Recorder()
        let expectedHint = await MainActor.run { WatchQASession.persistFailedHint }

        var status: String?
        _ = try await runSubmit(video: video, sidecar: sidecar, recorder: recorder) { session in
            status = session.statusMessage
            return session.statusMessage != nil
        }

        precondition(recorder.entry == nil, "写入失败绝不能回调 onPersisted")
        precondition(status == expectedHint, "写失败须提示「回答没有存上」")
        precondition(!FileManager.default.fileExists(atPath: sidecar.url.path), "写失败不留文件")
    }

    /// 视频已删除（itemID 打了删除标记）：persist 返回 .dropped，不回调 onPersisted，不提示，无文件。
    private static func checkSubmitDroppedWhenDeletedDoesNotFire(video: URL) async throws {
        MockSSEProtocol.setFullBody(status: 200, body: delta("已删除") + stop)
        let sidecar = freshSidecar()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }
        // 生产 submit 走 WatchQAStore.shared，这里对同一 itemID 预先打删除标记。
        await WatchQAStore.shared.deleteSidecar(sidecar)
        let recorder = Recorder()

        // 等到流式结束（isStreaming 落 false），再 settle 让 .dropped 落定，然后断言什么都没发生。
        let session = try await runSubmit(video: video, sidecar: sidecar, recorder: recorder) { s in
            !s.isStreaming
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let (entry, status) = await MainActor.run { (recorder.entry, session.statusMessage) }

        precondition(entry == nil, "已删除视频不得回调 onPersisted")
        precondition(status == nil, "已删除是静默丢弃，不提示失败")
        precondition(!FileManager.default.fileExists(atPath: sidecar.url.path), "删除后不得复活 sidecar")
    }

    /// 关闭浮层竞态：回答已完成（message_stop 收到）但字节流未关时调 dismiss()，
    /// 已完成的回答仍须完整落盘（落盘读流内累积的 result.text，不读被 dismiss 清空的 answer）。
    /// 故障注入自查：把落盘源改回 self.answer，本用例超时转红。
    private static func checkCompletedAnswerSurvivesDismiss(video: URL) async throws {
        let answer = "画面里是大象"
        MockSSEProtocol.status = 200
        MockSSEProtocol.segments = [delta(answer), stop] // 先交付增量，挂在 gate 上等放行 message_stop
        MockSSEProtocol.gateAfter = 0
        MockSSEProtocol.gate = DispatchSemaphore(value: 0)
        let sidecar = freshSidecar()
        defer { try? FileManager.default.removeItem(at: sidecar.url) }
        let recorder = Recorder()

        setenv("ANTHROPIC_API_KEY", "sk-test", 1)
        let session = await MainActor.run { () -> WatchQASession in
            PlaybackCommandCenter.shared.testPlayer = AVPlayer(url: video)
            let s = WatchQASession()
            let suite = "qa.session.present.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            defaults.set(true, forKey: WatchQAAvailability.defaultsKey)
            defer { defaults.removePersistentDomain(forName: suite) }
            s.present(defaults: defaults) // isPresented = true，dismiss() 才会真正生效
            s.question = "画面里是什么"
            s.submit(
                item: makeItem(id: sidecar.itemID),
                snapshot: PlaybackSnapshot(currentTime: 0),
                subtitleTrack: nil,
                sidecar: sidecar
            ) { entry in recorder.entry = entry }
            return s
        }

        // 等增量处理完（answer 填上），此刻流挂起等 message_stop，MainActor 空闲。
        try await waitFor { session.answer == answer }

        // 交错点：占住 MainActor，放行 message_stop，等协作池把它处理完（流返回、续体入队但被挡），
        // 再 dismiss 清空 answer，然后让出 MainActor；续体随后执行落盘。
        await MainActor.run {
            MockSSEProtocol.gate.signal()
            Thread.sleep(forTimeInterval: 0.25)
            _ = session.dismiss()
        }

        // 落盘应来自 result.text；若 buggy 读被清空的 answer，则永不落盘 → waitFor 超时转红。
        try await waitFor { recorder.entry != nil }
        precondition(recorder.entry?.answer == answer, "已完成回答须完整落盘，不受 dismiss 清空 answer 影响")
        precondition(
            WatchQAStore.load(from: sidecar.url).first?.answer == answer,
            "sidecar 内容须是完整回答"
        )
    }

    /// 轮询 MainActor 上的条件，最多 5 秒；超时视为失败（用于让回退路径转红）。
    private static func waitFor(_ predicate: @escaping @Sendable @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if await MainActor.run(body: predicate) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("等待超时")
    }

    // MARK: - 驱动 submit

    /// 在 MainActor 上装配 player、发起 submit，轮询到 done 或超时，返回会话供进一步断言。
    @discardableResult
    private static func runSubmit(
        video: URL,
        sidecar: WatchQASidecar,
        recorder: Recorder,
        done: @escaping @MainActor (WatchQASession) -> Bool
    ) async throws -> WatchQASession {
        setenv("ANTHROPIC_API_KEY", "sk-test", 1)
        let session = await MainActor.run { () -> WatchQASession in
            PlaybackCommandCenter.shared.testPlayer = AVPlayer(url: video)
            let s = WatchQASession()
            s.question = "画面里是什么"
            s.submit(
                item: makeItem(id: sidecar.itemID),
                snapshot: PlaybackSnapshot(currentTime: 0),
                subtitleTrack: nil,
                sidecar: sidecar
            ) { entry in recorder.entry = entry }
            return s
        }
        // 轮询完成条件（每 tick 10ms，最多 500 tick = 5s）。
        for _ in 0..<500 {
            if await MainActor.run(body: { done(session) }) { return session }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("submit 未在超时内完成")
    }

    // MARK: - 辅助

    private static func input() -> WatchQARequestInput {
        WatchQARequestInput(
            title: "t", author: "", chapterTitle: nil,
            currentTime: 5, cues: [], jpegBase64: "framemock", question: "q"
        )
    }

    private static func session(status: Int, body: String) -> URLSession {
        MockSSEProtocol.setFullBody(status: status, body: body)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEProtocol.self]
        return URLSession(configuration: config)
    }

    private static func delta(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"\(escaped)\"}}\n\n"
    }

    private static let stop = "data: {\"type\":\"message_stop\"}\n\n"

    private static func freshSidecar() -> WatchQASidecar {
        WatchQASidecar(itemID: UUID(), folder: FileManager.default.temporaryDirectory)
    }

    private static func makeItem(id: UUID) -> WatchItem {
        WatchItem(
            id: id,
            urlString: "https://example.com/v",
            title: "Me at the zoo",
            author: "jawed",
            duration: 60,
            addedAt: Date(timeIntervalSince1970: 1),
            watchedAt: nil,
            state: .ready,
            progress: 1,
            progressLabel: "",
            localFilePath: nil,
            errorMessage: nil,
            playbackPosition: 0,
            chapters: [],
            thumbnailFilePath: nil,
            subtitleFilePath: nil
        )
    }

    /// 生成一段 1 帧的极小视频，供真实 WatchQAFrameCapture 截帧。
    private static func makeTinyVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-session-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        if let pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 128, CVPixelBufferGetBytesPerRow(pixelBuffer) * 64)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: .zero)
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
