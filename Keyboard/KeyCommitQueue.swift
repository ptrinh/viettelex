// KeyCommitQueue — thứ tự chốt phím khi gõ chồng ngón (research 25/09/2026).
//
// Phím chữ chèn lúc CHẠM XUỐNG; space / dấu câu / số-ký hiệu / return chèn lúc
// NHẤC. Gõ nhanh hai ngón cái ("anh␣em"): ngón trên space chưa nhấc thì "e" đã
// chèn → "anhe" rồi mới tới space — cảm giác "space không ăn", và "e" bị engine
// gộp vào từ cũ. Stock iOS chốt đúng thứ tự: phím đang đè được chốt ngay khi có
// ngón MỚI chạm xuống.
//
// Hàng đợi này giữ các phím nhấc-mới-chốt đang đè (theo thứ tự chạm):
//   • arm      — phím chạm xuống: ghi nhận, CHƯA chèn.
//   • flush    — một phím KHÁC chạm xuống: chốt mọi phím đang giữ, đúng thứ tự.
//   • release  — nhấc ngón HOẶC touch bị hệ thống huỷ: chốt nếu còn giữ (touch
//                bị cancel ở hàng dưới sát home indicator không còn nuốt phím).
//   • disarm   — bỏ không chốt (giữ space vào chế độ trackpad: nhả ra không có
//                dấu cách như stock).
// Pure, không UIKit — pinned by KeyCommitQueueTests.
final class KeyCommitQueue {
    private var pending: [(id: ObjectIdentifier, fire: () -> Void)] = []

    var isEmpty: Bool { pending.isEmpty }

    func arm(_ id: ObjectIdentifier, fire: @escaping () -> Void) {
        // Same key pressed again while the earlier press is still down (two thumbs
        // on space): the earlier press is a real keystroke — commit it, don't drop it.
        release(id)
        pending.append((id, fire))
    }

    /// Commit every pending key except `id`, in press order.
    func flush(except id: ObjectIdentifier? = nil) {
        guard !pending.isEmpty else { return }
        let fired = pending.filter { $0.id != id }
        pending.removeAll { $0.id != id }
        for p in fired { p.fire() }
    }

    /// Commit `id` if it is still pending (touch up / cancelled).
    func release(_ id: ObjectIdentifier) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let p = pending.remove(at: i)
        p.fire()
    }

    /// Drop `id` without committing.
    func disarm(_ id: ObjectIdentifier) {
        pending.removeAll { $0.id == id }
    }
}
