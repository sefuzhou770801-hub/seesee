import Combine
import Foundation

@MainActor
final class DigestSession: ObservableObject {
    @Published var notes: [DigestNote] = []
    @Published var annotations: [DigestAnnotation] = []
    @Published var collapsedAnnotationIDs: Set<UUID> = []
    @Published var overview: DigestOverviewPayload?
    @Published var isGeneratingOverview = false
    @Published var overviewMessage: String?
    @Published var selectedText = ""
    @Published var selectedCueTime = 0.0
    @Published var selectedCueIndex: Int?
    @Published var explanation: String?
    @Published var explanationByCue: [Int: String] = [:]
    @Published var isExplaining = false
    @Published var explainingCueIndex: Int?
    @Published var explainMessage: String?
    @Published var explainMessageByCue: [Int: String] = [:]
    @Published var pendingDeletions: [UUID: Date] = [:]
    @Published var pendingAnnotationDeletions: [UUID: Date] = [:]
    @Published var persistMessage: String?
    @Published var showsHighlightsOnly = false
    @Published var editingCommentNoteID: UUID?
    @Published var commentDraft = ""
    @Published var noteJustSaved = false
    @Published var explainNeedsRetry = false
    @Published var retryCueIndices: Set<Int> = []
    @Published var shouldAutoGenerateOverview = false

    var apiKeyDefaults: UserDefaults = .standard
    var apiKeyEnvironment: [String: String] = ProcessInfo.processInfo.environment
    var completeFn: DigestCompleteFn?

    private var itemID: UUID?
    private var folder: URL?
    private var explainTask: Task<Void, Never>?
    private var overviewTask: Task<Void, Never>?
    private var noteDeleteTask: Task<Void, Never>?
    private var noteSavedTask: Task<Void, Never>?

    var hasAPIKey: Bool {
        DigestAPIKey.resolve(
            provider: DigestProvider.resolve(defaults: apiKeyDefaults),
            defaults: apiKeyDefaults,
            environment: apiKeyEnvironment
        ) != nil
    }

    /// 启动首选条目与切换视频共用：同一条目已加载则跳过。
    func ensureLoaded(itemID: UUID, folder: URL) {
        if self.itemID == itemID, self.folder == folder { return }
        load(itemID: itemID, folder: folder)
    }

    func load(itemID: UUID, folder: URL) {
        explainTask?.cancel()
        overviewTask?.cancel()
        self.itemID = itemID
        self.folder = folder
        persistMessage = nil
        switch DigestNotesStore.read(itemID: itemID, folder: folder) {
        case .ready(let loaded):
            notes = loaded.sorted { $0.createdAt > $1.createdAt }
        case .missing:
            notes = []
        case .corrupt:
            notes = []
            persistMessage = DigestCopy.fileCorrupt
        }
        switch DigestAnnotationsStore.read(itemID: itemID, folder: folder) {
        case .ready(let loaded):
            annotations = loaded
        case .missing:
            annotations = []
        case .corrupt:
            annotations = []
            persistMessage = DigestCopy.fileCorrupt
        }
        collapsedAnnotationIDs = []
        switch DigestOverviewStore.read(itemID: itemID, folder: folder) {
        case .ready(let record):
            overview = record.payload
            shouldAutoGenerateOverview = false
        case .stale:
            overview = nil
            shouldAutoGenerateOverview = true
        case .missing:
            overview = nil
            shouldAutoGenerateOverview = false
        case .corrupt:
            overview = nil
            shouldAutoGenerateOverview = false
            persistMessage = DigestCopy.fileCorrupt
        }
        isGeneratingOverview = false
        overviewMessage = nil
        pendingDeletions = [:]
        pendingAnnotationDeletions = [:]
        showsHighlightsOnly = false
        editingCommentNoteID = nil
        commentDraft = ""
        noteJustSaved = false
        explainNeedsRetry = false
        explanationByCue = [:]
        explainMessageByCue = [:]
        retryCueIndices = []
        explainingCueIndex = nil
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
        explainingCueIndex = nil
        explainTask?.cancel()
        explainTask = nil
    }

    var highlightCount: Int {
        DigestHighlight.visibleCount(notes: notes, pending: pendingDeletions)
    }

    func isHighlighted(_ cue: VideoSubtitleCue) -> Bool {
        note(for: cue) != nil
    }

    func note(for cue: VideoSubtitleCue) -> DigestNote? {
        DigestHighlightFilter.matchingVisibleNote(
            time: cue.startTime,
            text: cue.text,
            notes: notes,
            pending: pendingDeletions
        )
    }

    enum PendingDeletion: Equatable {
        case note(UUID)
        case annotation(UUID)
    }

    var latestPendingDeletion: PendingDeletion? {
        let note = pendingDeletions.max(by: { $0.value < $1.value })
        let annotation = pendingAnnotationDeletions.max(by: { $0.value < $1.value })
        switch (note, annotation) {
        case (nil, nil):
            return nil
        case (let note?, nil):
            return .note(note.key)
        case (nil, let annotation?):
            return .annotation(annotation.key)
        case (let note?, let annotation?):
            return note.value >= annotation.value ? .note(note.key) : .annotation(annotation.key)
        }
    }

    var latestPendingDeletionID: UUID? {
        switch latestPendingDeletion {
        case .note(let id), .annotation(let id):
            return id
        case nil:
            return nil
        }
    }

    func toggleHighlightFilter() {
        showsHighlightsOnly.toggle()
    }

    func beginEditComment(noteID: UUID) {
        editingCommentNoteID = noteID
        commentDraft = notes.first(where: { $0.id == noteID })?.comment ?? ""
    }

    func cancelEditComment() {
        editingCommentNoteID = nil
        commentDraft = ""
    }

    func commitCommentDraft() {
        guard let id = editingCommentNoteID else { return }
        updateComment(noteID: id, comment: commentDraft)
    }

    var editingNote: DigestNote? {
        guard let id = editingCommentNoteID else { return nil }
        return notes.first(where: { $0.id == id })
    }

    func updateComment(noteID: UUID, comment: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let previous = notes
        notes[index].comment = DigestNoteComment.normalized(comment)
        guard persistNotes(revertingTo: previous) else { return }
        if editingCommentNoteID == noteID {
            editingCommentNoteID = nil
            commentDraft = ""
        }
    }

    func explanation(for index: Int) -> String? {
        explanationByCue[index]
    }

    func annotation(for cue: VideoSubtitleCue) -> DigestAnnotation? {
        DigestAnnotationAnchor.matching(time: cue.startTime, text: cue.text, in: visibleAnnotations)
    }

    private var visibleAnnotations: [DigestAnnotation] {
        annotations.filter { pendingAnnotationDeletions[$0.id] == nil }
    }

    func isAnnotationCollapsed(_ id: UUID) -> Bool {
        DigestAnnotationCollapse.isCollapsed(id, in: collapsedAnnotationIDs)
    }

    func toggleAnnotationCollapsed(_ id: UUID) {
        collapsedAnnotationIDs = DigestAnnotationCollapse.toggling(id, in: collapsedAnnotationIDs)
    }

    func deleteAnnotation(_ id: UUID) {
        requestDeleteAnnotation(id)
    }

    func requestDeleteAnnotation(_ id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        if pendingAnnotationDeletions[id] != nil {
            return
        }
        DigestNoteUndo.request(pending: &pendingAnnotationDeletions, id: id)
        scheduleDeletionCommit()
    }

    func undoDeleteAnnotation(_ id: UUID) {
        DigestNoteUndo.undo(pending: &pendingAnnotationDeletions, id: id)
    }

    func recordAnnotation(time: Double, text: String, explanation: String, model: String) {
        let existing = DigestAnnotationAnchor.matching(time: time, text: text, in: annotations)
        let annotation = DigestAnnotation(
            id: existing?.id ?? UUID(),
            time: time,
            text: text,
            explanation: explanation,
            createdAt: Date(),
            model: model
        )
        let previous = annotations
        annotations = DigestAnnotationUpsert.applying(annotation, to: annotations)
        if let existing {
            collapsedAnnotationIDs.remove(existing.id)
        }
        persistAnnotations(revertingTo: previous)
    }

    func isExplainingCue(_ index: Int) -> Bool {
        isExplaining && explainingCueIndex == index
    }

    func needsRetry(_ index: Int) -> Bool {
        retryCueIndices.contains(index)
    }

    func explainMessage(for index: Int) -> String? {
        explainMessageByCue[index]
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
        guard !selected.isEmpty else { return nil }
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
        let previous = notes
        notes = next
        guard persistNotes(revertingTo: previous) else { return nil }
        noteJustSaved = true
        noteSavedTask?.cancel()
        noteSavedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.noteJustSaved = false
        }
        return last
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
        let expiredNotes = DigestNoteUndo.expiredIDs(pending: pendingDeletions, now: now)
        if !expiredNotes.isEmpty {
            let previous = notes
            notes.removeAll { expiredNotes.contains($0.id) }
            for id in expiredNotes {
                pendingDeletions.removeValue(forKey: id)
            }
            if !persistNotes(revertingTo: previous) {
                for id in expiredNotes {
                    DigestNoteUndo.request(pending: &pendingDeletions, id: id, now: now)
                }
            }
        }
        let expiredAnnotations = DigestNoteUndo.expiredIDs(pending: pendingAnnotationDeletions, now: now)
        if !expiredAnnotations.isEmpty {
            let previous = annotations
            annotations.removeAll { expiredAnnotations.contains($0.id) }
            for id in expiredAnnotations {
                pendingAnnotationDeletions.removeValue(forKey: id)
                collapsedAnnotationIDs.remove(id)
            }
            if !persistAnnotations(revertingTo: previous) {
                for id in expiredAnnotations {
                    DigestNoteUndo.request(pending: &pendingAnnotationDeletions, id: id, now: now)
                }
            }
        }
    }

    @discardableResult
    private func persistNotes(revertingTo previous: [DigestNote]? = nil) -> Bool {
        guard let itemID, let folder else { return false }
        do {
            try DigestNotesStore.save(notes, itemID: itemID, folder: folder)
            if persistMessage == DigestCopy.saveFailed {
                persistMessage = nil
            }
            return true
        } catch {
            if let previous {
                notes = previous
            }
            persistMessage = DigestCopy.saveFailed
            return false
        }
    }

    @discardableResult
    private func persistOverview(
        _ record: DigestOverviewRecord,
        revertingTo previous: DigestOverviewPayload?
    ) -> Bool {
        guard let itemID, let folder else { return false }
        do {
            try DigestOverviewStore.save(record, itemID: itemID, folder: folder)
            overview = record.payload
            if persistMessage == DigestCopy.saveFailed {
                persistMessage = nil
            }
            return true
        } catch {
            overview = previous
            persistMessage = DigestCopy.saveFailed
            return false
        }
    }

    @discardableResult
    private func persistAnnotations(revertingTo previous: [DigestAnnotation]? = nil) -> Bool {
        guard let itemID, let folder else { return false }
        do {
            try DigestAnnotationsStore.save(annotations, itemID: itemID, folder: folder)
            if persistMessage == DigestCopy.saveFailed {
                persistMessage = nil
            }
            return true
        } catch {
            if let previous {
                annotations = previous
            }
            persistMessage = DigestCopy.saveFailed
            return false
        }
    }

    private func scheduleDeletionCommit() {
        noteDeleteTask?.cancel()
        noteDeleteTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let session = self else { return }
                let now = Date()
                session.commitExpiredDeletions(now: now)
                let next = [session.pendingDeletions.values.min(), session.pendingAnnotationDeletions.values.min()]
                    .compactMap { $0 }
                    .min()
                guard let next else { return }
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
        cues: [VideoSubtitleCue],
        chapters: [VideoChapter] = []
    ) {
        guard !isGeneratingOverview else { return }
        let provider = DigestProvider.resolve(defaults: apiKeyDefaults)
        guard let apiKey = DigestAPIKey.resolve(
            provider: provider,
            defaults: apiKeyDefaults,
            environment: apiKeyEnvironment
        ) else {
            overviewMessage = DigestCopy.missingKeyHint
            return
        }
        guard !cues.isEmpty else {
            overviewMessage = DigestCopy.noSubtitles
            return
        }
        guard self.itemID != nil, self.folder != nil else { return }

        // 金句以整句为单位：转写与回查都用句块，不用 ASR 原始碎片，否则原文译文按碎片错位、整句金句对不上。
        let aggregated = SubtitleSentenceBlocks.aggregate(cues)
        let blocks = aggregated.isEmpty ? cues : aggregated
        let resolvedDuration = DigestOverviewPrompt.resolvedDuration(itemDuration: duration, cues: blocks)
        let transcript = DigestOverviewPrompt.timestampedTranscript(from: blocks)
        let skeletonBlock = DigestTOCComposer.skeletonBlock(from: chapters)
        let system = DigestOverviewPrompt.systemPrompt(
            duration: resolvedDuration,
            skeletonBlock: skeletonBlock
        )
        let user = DigestOverviewPrompt.userPrompt(
            title: title,
            author: author,
            duration: resolvedDuration,
            transcript: transcript,
            skeletonBlock: skeletonBlock
        )

        isGeneratingOverview = true
        overviewMessage = nil
        shouldAutoGenerateOverview = false
        overviewTask?.cancel()
        overviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                var accepted: DigestOverviewPayload?
                for _ in 0..<2 {
                    let text = try await self.complete(
                        system: system,
                        user: user,
                        apiKey: apiKey,
                        maxTokens: DigestRequestBuilder.overviewMaxTokens,
                        provider: provider,
                        temperature: nil
                    )
                    guard !Task.isCancelled else { return }
                    guard let parsed = DigestOverviewCodec.parse(text) else { continue }
                    let payload = DigestTOCComposer.compose(
                        skeleton: chapters,
                        ai: parsed,
                        duration: resolvedDuration,
                        cues: blocks
                    )
                    guard !payload.chapters.isEmpty else { continue }
                    accepted = payload
                    if DigestTOCCompleteness.hasAllSummaries(payload) {
                        break
                    }
                }
                guard var accepted else {
                    self.overviewMessage = DigestCopy.requestFailed
                    self.isGeneratingOverview = false
                    return
                }
                accepted = DigestTOCCompleteness.fillingMissingSummaries(accepted)
                let record = DigestOverviewRecord(
                    payload: accepted,
                    generatedAt: Date(),
                    model: provider.activeModel
                )
                let previous = self.overview
                if self.persistOverview(record, revertingTo: previous) {
                    self.overviewMessage = nil
                }
                self.isGeneratingOverview = false
            } catch {
                guard !Task.isCancelled else { return }
                self.isGeneratingOverview = false
                self.overviewMessage = DigestCopy.requestFailed
            }
        }
    }

    func explainCue(index: Int, title: String, cues: [VideoSubtitleCue]) {
        guard cues.indices.contains(index) else { return }
        selectText(cues[index].text, cueIndex: index, time: cues[index].startTime)
        explainSelection(title: title, cues: cues)
    }

    @discardableResult
    func toggleHighlight(cue: VideoSubtitleCue) -> DigestHighlightToggle.Action {
        let action = DigestHighlightToggle.action(
            time: cue.startTime,
            text: cue.text,
            notes: notes,
            pending: pendingDeletions
        )
        switch action {
        case .requestDelete(let id):
            editingCommentNoteID = nil
            commentDraft = ""
            requestDeleteNote(id)
        case .undoDelete(let id):
            undoDeleteNote(id)
        case .add:
            let captured = DigestNoteCapture.sources(
                selected: cue.text,
                hintIndex: 0,
                cues: [DigestNoteSource(startTime: cue.startTime, text: cue.text)]
            )
            guard let source = captured.first else { return action }
            let previous = notes
            let note = DigestNote(id: UUID(), time: source.startTime, text: source.text, createdAt: Date())
            notes.insert(note, at: 0)
            if persistNotes(revertingTo: previous) {
                editingCommentNoteID = note.id
                commentDraft = ""
            }
        }
        return action
    }

    func explainSelection(
        title: String,
        cues: [VideoSubtitleCue]
    ) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        let cueIndex = selectedCueIndex ?? 0
        let provider = DigestProvider.resolve(defaults: apiKeyDefaults)
        guard let apiKey = DigestAPIKey.resolve(
            provider: provider,
            defaults: apiKeyDefaults,
            environment: apiKeyEnvironment
        ) else {
            explanation = nil
            explanationByCue[cueIndex] = nil
            explainMessage = DigestCopy.missingKeyHint
            explainMessageByCue[cueIndex] = DigestCopy.missingKeyHint
            retryCueIndices.remove(cueIndex)
            explainNeedsRetry = false
            return
        }
        let passage = DigestExplainPrompt.passage(selected: selected, around: cueIndex, in: cues)
        let cueTime = cues.indices.contains(cueIndex) ? cues[cueIndex].startTime : selectedCueTime
        let cueText = cues.indices.contains(cueIndex) ? cues[cueIndex].text : selected
        isExplaining = true
        explainingCueIndex = cueIndex
        explainMessage = nil
        explainMessageByCue[cueIndex] = nil
        explanation = nil
        explanationByCue[cueIndex] = nil
        explainNeedsRetry = false
        retryCueIndices.remove(cueIndex)
        explainTask?.cancel()
        explainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.complete(
                    system: DigestExplainPrompt.systemPrompt,
                    user: DigestExplainPrompt.userText(videoTitle: title, passage: passage),
                    apiKey: apiKey,
                    maxTokens: DigestExplainPrompt.maxTokens,
                    provider: provider,
                    temperature: DigestExplainPrompt.temperature
                )
                guard !Task.isCancelled else { return }
                self.isExplaining = false
                self.explainingCueIndex = nil
                let trimmedAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                switch DigestExplainQuality.verdict(selected: selected, explanation: trimmedAnswer) {
                case .ok:
                    self.explanation = nil
                    self.explanationByCue[cueIndex] = nil
                    self.recordAnnotation(
                        time: cueTime,
                        text: cueText,
                        explanation: trimmedAnswer,
                        model: provider.activeModel
                    )
                    self.explainNeedsRetry = false
                    self.retryCueIndices.remove(cueIndex)
                    self.explainMessage = nil
                    self.explainMessageByCue[cueIndex] = nil
                case .empty, .tooShort, .unrelated:
                    self.explanation = nil
                    self.explanationByCue[cueIndex] = nil
                    self.explainNeedsRetry = true
                    self.retryCueIndices.insert(cueIndex)
                    self.explainMessage = nil
                    self.explainMessageByCue[cueIndex] = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isExplaining = false
                self.explainingCueIndex = nil
                self.explainMessage = DigestCopy.requestFailed
                self.explainMessageByCue[cueIndex] = DigestCopy.requestFailed
            }
        }
    }

    private func complete(
        system: String,
        user: String,
        apiKey: String,
        maxTokens: Int,
        provider: DigestProviderKind,
        temperature: Double?
    ) async throws -> String {
        if let completeFn {
            return try await completeFn(system, user, apiKey, maxTokens, provider, temperature)
        }
        return try await DigestAPIClient.complete(
            system: system,
            user: user,
            apiKey: apiKey,
            maxTokens: maxTokens,
            provider: provider,
            temperature: temperature
        )
    }
}
