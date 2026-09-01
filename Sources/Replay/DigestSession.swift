import Combine
import Foundation

@MainActor
final class DigestSession: ObservableObject {
    @Published var notes: [DigestNote] = []
    @Published var overview: DigestOverviewPayload?
    @Published var isGeneratingOverview = false
    @Published var overviewMessage: String?
    @Published var selectedText = ""
    @Published var selectedCueTime = 0.0
    @Published var selectedCueIndex: Int?
    @Published var explanation: String?
    @Published var isExplaining = false
    @Published var explainMessage: String?
    @Published var pendingDeletions: [UUID: Date] = [:]
    @Published var noteJustSaved = false
    @Published var explainNeedsRetry = false
    @Published var shouldAutoGenerateOverview = false

    private var itemID: UUID?
    private var folder: URL?
    private var explainTask: Task<Void, Never>?
    private var overviewTask: Task<Void, Never>?
    private var noteDeleteTask: Task<Void, Never>?
    private var noteSavedTask: Task<Void, Never>?

    var hasAPIKey: Bool {
        DigestAPIKey.resolve() != nil
    }

    func load(itemID: UUID, folder: URL) {
        explainTask?.cancel()
        overviewTask?.cancel()
        self.itemID = itemID
        self.folder = folder
        notes = DigestNotesStore.load(itemID: itemID, folder: folder)
            .sorted { $0.createdAt > $1.createdAt }
        if let record = DigestOverviewStore.load(itemID: itemID, folder: folder) {
            overview = record.payload
            shouldAutoGenerateOverview = false
        } else {
            overview = nil
            shouldAutoGenerateOverview = DigestOverviewStore.fileExists(itemID: itemID, folder: folder)
        }
        isGeneratingOverview = false
        overviewMessage = nil
        pendingDeletions = [:]
        noteJustSaved = false
        explainNeedsRetry = false
        noteDeleteTask?.cancel()
        noteSavedTask?.cancel()
        clearSelection()
    }

    func clearSelection() {
        selectedText = ""
        selectedCueTime = 0
        selectedCueIndex = nil
        explanation = nil
        isExplaining = false
        explainMessage = nil
        explainNeedsRetry = false
        explainTask?.cancel()
        explainTask = nil
    }

    func selectText(_ text: String, cueIndex: Int, time: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if selectedCueIndex == cueIndex {
                clearSelection()
            }
            return
        }
        if selectedCueIndex != cueIndex || selectedText != trimmed {
            explanation = nil
            explainMessage = nil
            explainNeedsRetry = false
        }
        selectedText = trimmed
        selectedCueIndex = cueIndex
        selectedCueTime = time
    }

    @discardableResult
    func saveSelectedNote(cues: [VideoSubtitleCue] = []) -> DigestNote? {
        guard !noteJustSaved else { return nil }
        let noteCues = cues.map { DigestNoteSource(startTime: $0.startTime, text: $0.text) }
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, let itemID, let folder else { return nil }
        let captured = DigestNoteCapture.sources(
            selected: selected,
            hintIndex: selectedCueIndex ?? 0,
            cues: noteCues
        )
        guard !captured.isEmpty else { return nil }
        var next = notes
        var last: DigestNote?
        let createdAt = Date()
        for source in captured.reversed() {
            let note = DigestNote(id: UUID(), time: source.startTime, text: source.text, createdAt: createdAt)
            next.insert(note, at: 0)
            last = note
        }
        do {
            try DigestNotesStore.save(next, itemID: itemID, folder: folder)
            notes = next
            noteJustSaved = true
            noteSavedTask?.cancel()
            noteSavedTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.noteJustSaved = false
            }
            return last
        } catch {
            return nil
        }
    }

    func requestDeleteNote(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        DigestNoteUndo.request(pending: &pendingDeletions, id: id)
        scheduleDeletionCommit()
    }

    func undoDeleteNote(_ id: UUID) {
        DigestNoteUndo.undo(pending: &pendingDeletions, id: id)
    }

    func commitExpiredDeletions(now: Date = Date()) {
        let expired = DigestNoteUndo.expiredIDs(pending: pendingDeletions, now: now)
        guard !expired.isEmpty else { return }
        notes.removeAll { expired.contains($0.id) }
        for id in expired {
            pendingDeletions.removeValue(forKey: id)
        }
        persistNotes()
    }

    private func persistNotes() {
        guard let itemID, let folder else { return }
        try? DigestNotesStore.save(notes, itemID: itemID, folder: folder)
    }

    private func scheduleDeletionCommit() {
        noteDeleteTask?.cancel()
        noteDeleteTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let session = self else { return }
                let now = Date()
                session.commitExpiredDeletions(now: now)
                guard let next = session.pendingDeletions.values.min() else { return }
                let wait = next.timeIntervalSince(now)
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            }
        }
    }

    func generateOverview(
        title: String,
        author: String,
        duration: Double?,
        cues: [VideoSubtitleCue]
    ) {
        guard !isGeneratingOverview else { return }
        let provider = DigestProvider.resolve()
        guard let apiKey = DigestAPIKey.resolve(provider: provider) else {
            overviewMessage = DigestRequestBuilder.missingKeyHint
            return
        }
        guard !cues.isEmpty else {
            overviewMessage = "这段没有字幕"
            return
        }
        guard let itemID, let folder else { return }

        let resolvedDuration = DigestOverviewPrompt.resolvedDuration(itemDuration: duration, cues: cues)
        let transcript = DigestOverviewPrompt.timestampedTranscript(from: cues)
        let system = DigestOverviewPrompt.systemPrompt(duration: resolvedDuration)
        let user = DigestOverviewPrompt.userPrompt(
            title: title,
            author: author,
            duration: resolvedDuration,
            transcript: transcript
        )

        isGeneratingOverview = true
        overviewMessage = nil
        shouldAutoGenerateOverview = false
        overviewTask?.cancel()
        overviewTask = Task { [weak self] in
            do {
                let text = try await DigestAPIClient.complete(
                    system: system,
                    user: user,
                    apiKey: apiKey,
                    maxTokens: DigestRequestBuilder.overviewMaxTokens,
                    provider: provider
                )
                guard !Task.isCancelled else { return }
                guard let payload = DigestOverviewCodec.parse(text) else {
                    self?.overviewMessage = "这次没写成"
                    self?.isGeneratingOverview = false
                    return
                }
                let record = DigestOverviewRecord(
                    payload: payload,
                    generatedAt: Date(),
                    model: provider.activeModel
                )
                try DigestOverviewStore.save(record, itemID: itemID, folder: folder)
                self?.overview = payload
                self?.isGeneratingOverview = false
                if !DigestOverviewPrompt.lastChapterCoversLatePart(
                    chapters: payload.chapters,
                    duration: resolvedDuration
                ) {
                    self?.overviewMessage = "后面几段几乎没写到，可以再写一次。"
                } else {
                    self?.overviewMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.isGeneratingOverview = false
                self?.overviewMessage = error.localizedDescription
            }
        }
    }

    func explainSelection(
        title: String,
        cues: [VideoSubtitleCue]
    ) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        let provider = DigestProvider.resolve()
        guard let apiKey = DigestAPIKey.resolve(provider: provider) else {
            explanation = nil
            explainMessage = DigestRequestBuilder.missingKeyHint
            return
        }
        let cueIndex = selectedCueIndex ?? 0
        let passage = DigestExplainPrompt.passage(selected: selected, around: cueIndex, in: cues)
        isExplaining = true
        explainMessage = nil
        explanation = nil
        explainNeedsRetry = false
        explainTask?.cancel()
        explainTask = Task { [weak self] in
            do {
                let text = try await DigestAPIClient.complete(
                    system: DigestExplainPrompt.systemPrompt,
                    user: DigestExplainPrompt.userText(videoTitle: title, passage: passage),
                    apiKey: apiKey,
                    maxTokens: DigestExplainPrompt.maxTokens,
                    provider: provider,
                    temperature: DigestExplainPrompt.temperature
                )
                guard !Task.isCancelled else { return }
                self?.isExplaining = false
                let trimmedAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                switch DigestExplainQuality.verdict(selected: selected, explanation: trimmedAnswer) {
                case .ok:
                    self?.explanation = trimmedAnswer
                    self?.explainNeedsRetry = false
                    self?.explainMessage = nil
                case .empty, .tooShort, .unrelated:
                    self?.explanation = nil
                    self?.explainNeedsRetry = true
                    self?.explainMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.isExplaining = false
                self?.explainMessage = error.localizedDescription
            }
        }
    }
}
