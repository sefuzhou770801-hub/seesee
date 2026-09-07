import Foundation

struct DigestAnnotation: Codable, Equatable, Identifiable {
    var id: UUID
    var time: Double
    var text: String
    var explanation: String
    var createdAt: Date
    var model: String
}

enum DigestAnnotationAnchor {
    static let timeTolerance = 0.01

    static func matching(
        time: Double,
        text: String,
        in annotations: [DigestAnnotation]
    ) -> DigestAnnotation? {
        guard let index = index(time: time, text: text, in: annotations) else { return nil }
        return annotations[index]
    }

    static func index(
        time: Double,
        text: String,
        in annotations: [DigestAnnotation]
    ) -> Int? {
        annotations.firstIndex { annotation in
            abs(annotation.time - time) < timeTolerance && annotation.text == text
        }
    }
}

enum DigestAnnotationUpsert {
    static func applying(
        _ annotation: DigestAnnotation,
        to annotations: [DigestAnnotation]
    ) -> [DigestAnnotation] {
        var next = annotations
        if let index = DigestAnnotationAnchor.index(
            time: annotation.time,
            text: annotation.text,
            in: next
        ) {
            next[index] = annotation
        } else {
            next.append(annotation)
        }
        return next
    }
}

enum DigestAnnotationCollapse {
    static func toggling(_ id: UUID, in collapsed: Set<UUID>) -> Set<UUID> {
        var next = collapsed
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    static func isCollapsed(_ id: UUID, in collapsed: Set<UUID>) -> Bool {
        collapsed.contains(id)
    }
}

enum DigestContinueAsk {
    static let title = "继续问"

    static func isVisible(watchQAEnabled: Bool) -> Bool {
        watchQAEnabled
    }

    static func question(sourceText: String, explanation: String) -> String {
        """
        来源句：
        \(sourceText)

        解释：
        \(explanation)

        我想继续问：
        """
    }
}

enum DigestAnnotationChrome {
    static let collapseTitle = "收起"
    static let expandTitle = "展开"
    static let deleteTitle = "删除"
}

enum DigestAnnotationsStore {
    static let sidecarSuffix = "annotations.json"

    enum Read: Equatable {
        case missing
        case ready([DigestAnnotation])
        case corrupt
    }

    static func fileURL(itemID: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent("\(itemID.uuidString).\(sidecarSuffix)")
    }

    static func load(itemID: UUID, folder: URL) -> [DigestAnnotation] {
        load(from: fileURL(itemID: itemID, in: folder))
    }

    static func load(from url: URL) -> [DigestAnnotation] {
        switch read(from: url) {
        case .ready(let annotations):
            return annotations
        case .missing, .corrupt:
            return []
        }
    }

    static func read(itemID: UUID, folder: URL) -> Read {
        read(from: fileURL(itemID: itemID, in: folder))
    }

    static func read(from url: URL) -> Read {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .corrupt
        }
        if data.isEmpty { return .missing }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return .ready(try decoder.decode([DigestAnnotation].self, from: data))
        } catch {
            return .corrupt
        }
    }

    static func save(_ annotations: [DigestAnnotation], itemID: UUID, folder: URL) throws {
        try save(annotations, to: fileURL(itemID: itemID, in: folder))
    }

    static func save(_ annotations: [DigestAnnotation], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(annotations)
        try data.write(to: url, options: .atomic)
    }
}
