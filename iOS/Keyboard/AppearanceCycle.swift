// AppearanceCycle — logic THUẦN theo dõi chuỗi callback hiện/ẩn của UIInputViewController.
//
// Bàn phím XÉ cây view ở viewDidDisappear (RAM-AUDIT.md #1) và dựng + cấu hình lại ở
// viewWillAppear. Hai chuỗi callback làm hỏng giả định "will → did, đúng cặp":
//
// 1. Ẩn bị ngắt bởi một lần hiện (host gọi resign rồi become ngay — app vừa mở lại sau khi
//    bị kill, Zalo dựng lại màn chat): willDisappear → willAppear → didDisappear (MUỘN) →
//    didAppear. Xé ở didDisappear muộn đó ⇒ bàn phím hiện ra RỖNG (không phím, không thanh
//    gợi ý) tới lần mở sau.
// 2. Hiện mà không có willAppear (callback bị nuốt khi host khởi động) ⇒ không ai áp trait ô /
//    bật thanh gợi ý / đọc cài đặt; thanh gợi ý ẩn cả phiên.
//
// Quy tắc: didDisappear chỉ xé khi KHÔNG có willAppear nào tới sau willDisappear gần nhất;
// didAppear tự chạy phần cấu hình nếu lần hiện này chưa được cấu hình (hoặc view đã bị xé).
struct AppearanceCycle: Equatable {
    /// Callback gần nhất thuộc chiều "hiện" (willAppear/didAppear) — chưa có ẩn nào sau nó.
    private(set) var showing = false
    /// Phần cấu hình của viewWillAppear đã chạy cho lần hiện hiện tại (đặt lại khi xé).
    private(set) var configured = false

    /// viewWillAppear: controller sẽ cấu hình ngay sau đó.
    mutating func willAppear() {
        showing = true
        configured = true
    }

    mutating func willDisappear() {
        showing = false
    }

    /// viewDidDisappear: true ⇒ được xé cây view. Có willAppear chen vào sau willDisappear
    /// (ẩn đã bị huỷ) ⇒ false, giữ nguyên bàn phím đang hiện.
    mutating func didDisappear() -> Bool {
        guard !showing else { return false }
        configured = false
        return true
    }

    /// Hiện lại LẶNG LẼ: view đã bị xé (didDisappear) nhưng đang nằm trong window mà không có
    /// willAppear/didAppear nào (host gắn lại input view cũ — Zalo mở lại / dựng lại màn chat,
    /// 28/10/2026 vẫn còn "lần đầu không hiện"). Người dùng chạm vào bàn phím trống ⇒ true:
    /// controller dựng + cấu hình lại như một lần hiện.
    static func needsHeal(tornDown: Bool, inWindow: Bool) -> Bool { tornDown && inWindow }

    /// Đã tự dựng lại (needsHeal) ⇒ coi như một lần hiện đã cấu hình.
    mutating func healed() {
        showing = true
        configured = true
    }

    /// viewDidAppear: true ⇒ controller phải chạy phần cấu hình của viewWillAppear ngay
    /// (willAppear bị bỏ qua, hoặc view đã bị xé dù đang hiện).
    mutating func didAppear(tornDown: Bool) -> Bool {
        showing = true
        let need = !configured || tornDown
        configured = true
        return need
    }
}
