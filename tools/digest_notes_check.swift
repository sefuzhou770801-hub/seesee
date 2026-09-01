import Foundation

@main
struct DigestNotesCheck {
    static func main() throws {
        checkFileNaming()
        try checkRoundTripAndDelete()
        checkCorruptAndMissing()
        print("digest_notes_check=passed")
    }

    private static func checkFileNaming() {
        let id = UUID(uuidString: "9D0A346E-068C-41CE-B3FC-938A773AADC9")!
        let folder = URL(fileURLWithPath: "/tmp/replay-media", isDirectory: true)
        let url = DigestNotesStore.fileURL(itemID: id, in: folder)
        precondition(
            url.lastPathComponent == "9D0A346E-068C-41CE-B3FC-938A773AADC9.notes.json",
            "笔记 sidecar 须为 {UUID}.notes.json"
        )
        precondition(url.lastPathComponent.hasPrefix(id.uuidString + "."))
    }

    private static func checkRoundTripAndDelete() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("digest-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let itemID = UUID()
        let note = DigestNote(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            time: 75.5,
            text: "这段在讲注意力机制",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try DigestNotesStore.save([note], itemID: itemID, folder: folder)

        let loaded = DigestNotesStore.load(itemID: itemID, folder: folder)
        precondition(loaded.count == 1)
        precondition(loaded[0].id == note.id)
        precondition(loaded[0].time == 75.5)
        precondition(loaded[0].text == "这段在讲注意力机制")
        precondition(loaded[0].createdAt.timeIntervalSince1970 == 1_700_000_000)

        let remaining = loaded.filter { $0.id != note.id }
        try DigestNotesStore.save(remaining, itemID: itemID, folder: folder)
        precondition(DigestNotesStore.load(itemID: itemID, folder: folder).isEmpty, "删除后列表应为空")
    }

    private static func checkCorruptAndMissing() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).notes.json")
        precondition(DigestNotesStore.load(from: missing).isEmpty)

        let folder = FileManager.default.temporaryDirectory
        let corrupt = folder.appendingPathComponent("digest-notes-corrupt-\(UUID().uuidString).json")
        try? "not-json".write(to: corrupt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        precondition(DigestNotesStore.load(from: corrupt).isEmpty, "坏 JSON 按空列表")
    }
}
