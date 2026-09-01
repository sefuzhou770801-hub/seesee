import Foundation

@main
struct DigestNoteUndoCheck {
    static func main() {
        let first = DigestNote(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            time: 12,
            text: "不同的方面",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = DigestNote(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            time: 40,
            text: "另一条",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        var pending: [UUID: Date] = [:]
        let now = Date(timeIntervalSince1970: 100)

        DigestNoteUndo.request(pending: &pending, id: first.id, now: now)
        precondition(pending[first.id] == now.addingTimeInterval(5))
        precondition(DigestNoteUndo.visibleNotes([first, second], pending: pending).map(\.id) == [second.id])
        precondition(DigestNoteUndo.expiredIDs(pending: pending, now: now.addingTimeInterval(4.9)).isEmpty)

        DigestNoteUndo.undo(pending: &pending, id: first.id)
        precondition(pending.isEmpty)
        precondition(DigestNoteUndo.visibleNotes([first, second], pending: pending).count == 2)

        DigestNoteUndo.request(pending: &pending, id: first.id, now: now)
        let expired = DigestNoteUndo.expiredIDs(pending: pending, now: now.addingTimeInterval(5))
        precondition(expired == [first.id])

        print("digest_note_undo_check=passed")
    }
}
