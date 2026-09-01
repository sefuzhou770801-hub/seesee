import Foundation

struct DigestNote: Codable, Equatable, Identifiable {
    var id: UUID
    var time: Double
    var text: String
    var createdAt: Date
}

struct DigestNoteSource: Equatable {
    var startTime: Double
    var text: String
}

enum DigestNoteCapture {
    static func sources(
        selected: String,
        hintIndex: Int,
        cues: [DigestNoteSource]
    ) -> [DigestNoteSource] {
        guard !cues.isEmpty else { return [] }
        let needle = fold(selected)
        guard !needle.isEmpty else { return [] }
        let hint = cues.indices.contains(hintIndex) ? hintIndex : 0
        var indices = [hint]
        if !fold(cues[hint].text).localizedStandardContains(needle) {
            if hint > 0, fold(cues[hint - 1].text + "\n" + cues[hint].text).localizedStandardContains(needle) {
                indices.insert(hint - 1, at: 0)
            } else if hint + 1 < cues.count,
                      fold(cues[hint].text + "\n" + cues[hint + 1].text).localizedStandardContains(needle) {
                indices.append(hint + 1)
            }
        }
        return indices.map { cues[$0] }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DigestNotesStore {
    static let sidecarSuffix = "notes.json"

    static func fileURL(itemID: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent("\(itemID.uuidString).\(sidecarSuffix)")
    }

    static func load(itemID: UUID, folder: URL) -> [DigestNote] {
        load(from: fileURL(itemID: itemID, in: folder))
    }

    static func load(from url: URL) -> [DigestNote] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DigestNote].self, from: data)) ?? []
    }

    static func save(_ notes: [DigestNote], itemID: UUID, folder: URL) throws {
        try save(notes, to: fileURL(itemID: itemID, in: folder))
    }

    static func save(_ notes: [DigestNote], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notes)
        try data.write(to: url, options: .atomic)
    }
}
