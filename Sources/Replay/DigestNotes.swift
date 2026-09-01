import Foundation

struct DigestNote: Codable, Equatable, Identifiable {
    var id: UUID
    var time: Double
    var text: String
    var createdAt: Date
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
