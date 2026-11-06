package com.viettelex.keyboard

import kotlin.math.floor
import kotlin.math.hypot

/**
 * Popup nhiều lựa chọn kiểu stock iOS: giữ phím ⇒ hàng ô, ô gốc chọn sẵn, trượt để chọn,
 * nhấc chèn, trượt xa huỷ. Bản THUẦN song sinh iOS/Keyboard/DomainPopup.swift — sửa ở đây
 * thì sửa y hệt bên kia. Dùng cho:
 *  - giữ "." ở bàn CHỮ ô URL / thanh địa chỉ / email ⇒ đuôi tên miền ([tlds]);
 *  - giữ phím bàn số / ký hiệu ⇒ biến thể ký tự ([KeyVariants]).
 * Toạ độ trong file này là dp (view chia mật độ trước khi gọi).
 */
object DomainPopup {
    /** Ô có hàng đuôi tên miền (app ánh xạ từ loại ô Android). */
    enum class Field { NORMAL, URL, EMAIL }

    /**
     * Đuôi tên miền — .com mặc định như stock, .vn / .com.vn kế tiếp cho người dùng Việt
     * (issue #113: bỏ phím ".com" riêng ở ô URL, gom vào giữ ".").
     */
    val tlds = listOf(".com", ".vn", ".com.vn", ".net", ".org", ".edu")

    /** Phím `key` ở bàn CHỮ của ô [field] có popup không — chỉ phím "." ô URL / email; ô khác rỗng (0 chi phí). */
    fun choices(field: Field, key: String, lettersPlane: Boolean): List<String> {
        if (!lettersPlane || key != ".") return emptyList()
        return when (field) {
            Field.URL, Field.EMAIL -> tlds
            Field.NORMAL -> emptyList()
        }
    }

    /**
     * Bố cục ô. Ô đầu (mặc định) nằm ngay trên tâm phím; hàng loe về phía còn chỗ (không đủ
     * chỗ bên phải thì lật ngược — ô đầu ở bên phải, hàng loe sang trái — như stock), rồi kẹp
     * trong [margin, width − margin].
     *
     * HAI HÀNG (issue #154: giữ "," 10 ô, ô xa không với tới): khi một hàng không vừa bề
     * ngang với bề rộng ô mong muốn, HOẶC phải kẹp mép đẩy ô đầu lệch khỏi tâm phím quá nửa ô ⇒
     * chia [perRow] = ⌈n/2⌉ ô mỗi hàng, hàng 0 (ô 0…perRow−1) sát phím, hàng 1 chồng LÊN trên;
     * ô i+perRow nằm ngay trên ô i. Vừa một hàng mà ô đầu vẫn trên phím ⇒ y như cũ.
     */
    data class Layout(val originX: Float, val itemWidth: Float, val count: Int,
                      /** true ⇒ ô 0 ở bên PHẢI (hàng đọc từ phải sang trái). */
                      val mirrored: Boolean,
                      /** Số ô mỗi hàng (= [count] khi một hàng). */
                      val perRow: Int = count,
                      /** Cao một hàng (dp) — ranh giới hai hàng khi chọn theo y; một hàng thì không dùng. */
                      val rowHeight: Float = 0f) {
        /** Bề ngang một hàng. */
        val width: Float get() = itemWidth * perRow
        /** 1 hoặc 2. */
        val rows: Int get() = if (perRow <= 0) 0 else (count + perRow - 1) / perRow
        /** Hàng của ô [index]: 0 = sát phím, 1 = phía trên. */
        fun rowOf(index: Int): Int = if (perRow <= 0) 0 else index / perRow
        /** Mép trái ô [index]. */
        fun slotMinX(index: Int): Float {
            val col = if (perRow <= 0) 0 else index % perRow
            val slot = if (mirrored) perRow - 1 - col else col
            return originX + slot * itemWidth
        }
    }

    /**
     * [itemWidth] = bề rộng ô mong muốn (co lại nếu không vừa); [rowHeight] = cao một hàng;
     * [maxRows] = 1 khi không có chỗ phía trên cho hàng thứ hai (view tự quyết).
     */
    fun layout(keyMidX: Float, itemWidth: Float, count: Int, containerWidth: Float, margin: Float = 2f,
               rowHeight: Float = 0f, maxRows: Int = 2): Layout {
        val avail = maxOf(containerWidth - 2 * margin, 1f)
        val oneW = minOf(itemWidth, avail / maxOf(count, 1))
        val one = place(keyMidX, oneW, count, count, containerWidth, margin, rowHeight)
        if (maxRows < 2 || count < 2) return one.first
        val crowded = itemWidth * count > avail || one.second > oneW / 2
        if (!crowded) return one.first
        val perRow = (count + 1) / 2
        return place(keyMidX, minOf(itemWidth, avail / perRow), count, perRow, containerWidth, margin, rowHeight).first
    }

    /** Đặt hàng [perRow] ô rộng [w]; trả kèm độ dời do kẹp mép (ô đầu lệch khỏi tâm phím bao nhiêu). */
    private fun place(keyMidX: Float, w: Float, count: Int, perRow: Int, containerWidth: Float, margin: Float,
                      rowHeight: Float): Pair<Layout, Float> {
        val rowW = w * perRow
        val rightFits = keyMidX - w / 2 + rowW <= containerWidth - margin
        val leftFits = keyMidX + w / 2 - rowW >= margin
        // Không bên nào vừa ⇒ loe về bên nhiều chỗ hơn (ô đầu bớt lệch khi kẹp).
        val roomRight = containerWidth - margin - (keyMidX - w / 2)
        val roomLeft = keyMidX + w / 2 - margin
        val mirrored = !rightFits && (leftFits || roomLeft > roomRight)
        val raw = if (mirrored) keyMidX + w / 2 - rowW else keyMidX - w / 2
        val x = minOf(maxOf(raw, margin), maxOf(margin, containerWidth - margin - rowW))
        return Layout(x, w, count, mirrored, perRow, rowHeight) to kotlin.math.abs(x - raw)
    }

    /** Ngón trượt ra ngoài hàng quá ngần này (ngang, dp) ⇒ huỷ. */
    const val CANCEL_SLACK_X = 30f
    /** Ngón trượt lên trên đỉnh popup / xuống dưới đáy phím quá ngần này (dp) ⇒ huỷ. */
    const val CANCEL_SLACK_Y = 40f
    /** Lúc mở luôn chọn ô 0; ngón phải dời quá ngần này (dp) mới đổi ô — run tay không đổi ô. */
    const val ENGAGE_DP = 8f

    /**
     * Độ bù ngang của một lượt kéo: chỗ mở ([startX]) coi như tâm ô 0 (ngón chạm lệch trong phím
     * vẫn là ô 0, trượt một ô ra ô kế — cảm giác cũ), nhưng bù tối đa NỬA Ô. Issue #154: trước
     * đây bù trọn độ lệch; hàng bị kẹp mép (ô 0 lệch xa phím) thì ô ở đầu kia cần ngón ra ngoài
     * màn hình. Bù ≤ nửa ô ⇒ ô đầu/cuối luôn với tới trong nửa ô tính từ mép popup.
     */
    fun dragOffset(startX: Float, layout: Layout): Float {
        val half = layout.itemWidth / 2
        return (layout.slotMinX(0) + half - startX).coerceIn(-half, half)
    }

    /**
     * Ô dưới điểm ([x] đã cộng [dragOffset]). Lố hai đầu hàng trong ngần slack ⇒ kẹp ô đầu /
     * cuối. Hai hàng: cao hơn ranh giới ([top] + [Layout.rowHeight]) ⇒ hàng trên; hàng trên
     * thiếu ô ⇒ ô cuối. null = huỷ (ra ngoài quá slack). [top] = đỉnh popup, [bottom] = đáy
     * phím. Quay lại gần hàng thì chọn lại được (như stock).
     */
    fun index(x: Float, y: Float, layout: Layout, top: Float, bottom: Float): Int? {
        val l = layout
        if (l.count <= 0 || x < l.originX - CANCEL_SLACK_X || x > l.originX + l.width + CANCEL_SLACK_X ||
            y < top - CANCEL_SLACK_Y || y > bottom + CANCEL_SLACK_Y) return null
        val slot = floor((x - l.originX) / l.itemWidth).toInt().coerceIn(0, l.perRow - 1)
        val col = if (l.mirrored) l.perRow - 1 - slot else slot
        val row = if (l.rows > 1 && y < top + l.rowHeight) 1 else 0
        return (row * l.perRow + col).coerceAtMost(l.count - 1)
    }

    /**
     * MỘT lượt giữ phím có popup (thuần, không đồng hồ): view chạm ⇒ phím đã [KeyCommitQueue.arm]
     * ký tự gốc; hết giờ view gọi [fire] — nếu phím còn chờ chốt thì đổi thành "chèn ô đang
     * chọn" (chốt lúc nhấc / khi ngón khác chạm, cùng đường với phím thường ⇒ thứ tự đúng).
     * Trượt xa ⇒ không chọn ⇒ nhấc không chèn gì. Toạ độ dp, cùng hệ với [layout].
     */
    class Hold(val choices: List<String>) {
        var fired = false; private set
        var layout: Layout? = null; private set
        /** Ô đang chọn; null = huỷ (trượt xa) hoặc chưa mở. */
        var selection: Int? = null; private set
        private var startX = 0f
        private var startY = 0f
        private var dx = 0f
        private var engaged = false
        private var top = 0f
        private var bottom = 0f

        /** Chữ sẽ chèn khi nhấc (null = không gì). */
        val chosen: String? get() = selection?.let { choices.getOrNull(it) }

        /**
         * Hết giờ giữ. false ⇒ phím đã chốt (ngón khác chạm trước) — không mở popup.
         * [insert] chạy lúc chốt với ô đang chọn (không gọi nếu đã huỷ).
         */
        fun fire(commits: KeyCommitQueue, key: Any, layout: Layout, top: Float, bottom: Float,
                 x: Float, y: Float, insert: (String) -> Unit): Boolean {
            if (fired || !commits.isArmed(key)) return false
            commits.disarm(key)
            commits.arm(key) { chosen?.let(insert) }
            return open(layout, top, bottom, x, y)
        }

        /**
         * Mở hàng KHÔNG qua hàng chốt — menu hành động (giữ 😊, [EmojiKeyMenu]): view đọc
         * [selection] lúc nhấc rồi tự chạy. false nếu đã mở.
         */
        fun open(layout: Layout, top: Float, bottom: Float, x: Float, y: Float): Boolean {
            if (fired) return false
            this.layout = layout; this.top = top; this.bottom = bottom; startX = x; startY = y
            engaged = false
            dx = dragOffset(x, layout)
            selection = if (index(x + dx, y, layout, top, bottom) != null) 0 else null
            fired = true
            return true
        }

        /** Ngón di chuyển sau khi mở; true nếu ô chọn đổi. */
        fun move(x: Float, y: Float): Boolean {
            val l = layout ?: return false
            if (!engaged && hypot(x - startX, y - startY) < ENGAGE_DP) return false
            engaged = true
            val s = index(x + dx, y, l, top, bottom)
            if (s == selection) return false
            selection = s
            return true
        }
    }
}

/**
 * Ô email: vừa gõ "@" (hoặc tiền tố tên miền sau "@") ⇒ chip đuôi mail trên thanh gợi ý
 * ("@gmail.com" trước). Chạm chip chèn PHẦN CÒN THIẾU (không lặp "@" / tiền tố đã gõ).
 * Thuần — session chỉ gọi ở ô email (ô khác 0 việc). Song sinh iOS EmailDomains.
 */
object EmailDomains {
    val providers = listOf("gmail.com", "icloud.com", "yahoo.com", "outlook.com")

    /** [label] trên thanh gợi ý ("@gmail.com"); [insert] chèn sau con trỏ ("ail.com" sau "phuc@gm"). */
    data class Chip(val label: String, val insert: String)

    /**
     * Chip cho chữ trước con trỏ. Token cuối (sau khoảng trắng / "," / ";" / "<") phải có
     * đúng một "@", phần trước "@" không rỗng; phần sau là tiền tố (không phân biệt hoa
     * thường) của tên miền và chưa gõ đủ.
     */
    fun chips(before: String, limit: Int = 3): List<Chip> {
        if (limit <= 0) return emptyList()
        val at = before.lastIndexOf('@')
        if (at < 0) return emptyList()
        val partial = before.substring(at + 1)
        if (partial.length >= 12 || !partial.all { it.code < 128 && (it.isLetterOrDigit() || it == '.' || it == '-') })
            return emptyList()
        var i = at - 1
        while (i >= 0) {
            val c = before[i]
            if (c.isWhitespace() || c == ',' || c == ';' || c == '<') break
            if (c == '@') return emptyList()
            i--
        }
        if (i == at - 1) return emptyList()          // phần trước "@" rỗng
        val p = partial.lowercase()
        return providers.asSequence().filter { it.startsWith(p) && it != p }.take(limit)
            .map { Chip("@$it", it.substring(p.length)) }.toList()
    }
}
