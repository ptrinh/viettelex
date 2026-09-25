package com.viettelex.keyboard

/**
 * Case chuẩn cho proper noun khi HIỂN THỊ gợi ý (port iOS). Chỉ token không nhập nhằng;
 * token nhập nhằng viết hoa THEO CHUỖI ([chains]).
 */
object DisplayCase {
    fun apply(w: String, after: String? = null): String {
        val p = after?.lowercase()
        if (p != null && chains[p]?.contains(w) == true) return Cp.capitalizeFirst(w)
        return proper[w] ?: w
    }

    val chains: Map<String, Set<String>> = hashMapOf(
        // địa danh VN
        "hà" to setOf("nội", "nam", "tĩnh", "giang"),
        "đà" to setOf("nẵng", "lạt"),
        "nha" to setOf("trang"),
        "phú" to setOf("quốc", "thọ", "yên"),
        "sài" to setOf("gòn"),
        "hồ" to setOf("chí"),
        "chí" to setOf("minh"),
        "việt" to setOf("nam"),
        "cần" to setOf("thơ"),
        "hải" to setOf("phòng", "dương"),
        "hạ" to setOf("long"),
        "quy" to setOf("nhơn"),
        "vũng" to setOf("tàu"),
        "biên" to setOf("hòa"),
        "bình" to setOf("dương", "định", "thuận"),
        "thanh" to setOf("hóa"),
        "hội" to setOf("an"),
        "quảng" to setOf("ninh", "nam", "ngãi", "bình", "trị"),
        "nghệ" to setOf("an"),
        "lâm" to setOf("đồng"),
        "đồng" to setOf("nai", "tháp"),
        "long" to setOf("an"),
        "tây" to setOf("ninh"),
        "new" to setOf("york"),
        "san" to setOf("francisco"),
        "hong" to setOf("kong"),
        // họ → đệm (chuỗi tên người)
        "nguyễn" to setOf("văn", "thị", "đức", "minh", "ngọc", "hữu", "xuân", "thùy", "kim", "hồng", "quốc", "đình"),
        "trần" to setOf("văn", "thị", "đức", "minh", "ngọc", "quốc"),
        "lê" to setOf("văn", "thị", "đức", "minh", "ngọc", "hữu"),
        "phạm" to setOf("văn", "thị", "minh", "ngọc"),
        "hoàng" to setOf("văn", "thị", "minh", "anh"),
        "vũ" to setOf("văn", "thị", "minh"),
        "đặng" to setOf("văn", "thị"),
        "bùi" to setOf("văn", "thị"),
        "đỗ" to setOf("văn", "thị"),
        "ngô" to setOf("văn", "thị"),
        "dương" to setOf("văn", "thị"),
        "trịnh" to setOf("văn", "thị", "xuân"),
        // đệm → tên
        "văn" to setOf("hùng", "tuấn", "dũng", "sơn", "nam", "long", "hải", "minh"),
        "thị" to setOf("hương", "lan", "thu", "ngọc", "hồng", "phương", "hà", "linh"),
    )

    val proper: Map<String, String> = hashMapOf(
        // thương hiệu / sản phẩm
        "senprints" to "SenPrints", "printik" to "Printik",
        "apple" to "Apple", "iphone" to "iPhone", "ipad" to "iPad", "macbook" to "MacBook",
        "samsung" to "Samsung", "google" to "Google", "facebook" to "Facebook",
        "youtube" to "YouTube", "tiktok" to "TikTok", "zalo" to "Zalo",
        "shopee" to "Shopee", "lazada" to "Lazada", "grab" to "Grab",
        "momo" to "MoMo", "vnpay" to "VNPay", "vietcombank" to "Vietcombank",
        "techcombank" to "Techcombank", "viettel" to "Viettel", "vingroup" to "Vingroup",
        "vinfast" to "VinFast", "vietjet" to "Vietjet", "fpt" to "FPT",
        "arsenal" to "Arsenal", "liverpool" to "Liverpool", "chelsea" to "Chelsea",
        "manchester" to "Manchester", "bitcoin" to "Bitcoin", "ethereum" to "Ethereum",
        "binance" to "Binance", "netflix" to "Netflix", "spotify" to "Spotify",
        "github" to "GitHub", "claude" to "Claude", "chatgpt" to "ChatGPT",
        "tesla" to "Tesla", "openai" to "OpenAI", "anthropic" to "Anthropic",
        "yahoo" to "Yahoo", "hotmail" to "Hotmail",
        // OS / phần mềm
        "windows" to "Windows", "macos" to "macOS", "ios" to "iOS",
        "android" to "Android", "linux" to "Linux", "chrome" to "Chrome",
        "safari" to "Safari", "excel" to "Excel", "word" to "Word",
        "wifi" to "WiFi", "gmail" to "Gmail", "outlook" to "Outlook",
        // địa danh nước ngoài (token đơn, không nhập nhằng)
        "singapore" to "Singapore", "dubai" to "Dubai", "london" to "London",
        "tokyo" to "Tokyo", "sydney" to "Sydney", "canada" to "Canada",
        "houston" to "Houston", "seattle" to "Seattle", "miami" to "Miami",
        "dallas" to "Dallas", "austin" to "Austin", "texas" to "Texas",
        "california" to "California", "washington" to "Washington",
        "york" to "York", "francisco" to "Francisco", "paris" to "Paris",
        "bangkok" to "Bangkok", "seoul" to "Seoul",
        // họ Việt an toàn (gần như luôn là tên riêng khi đứng một mình).
        // CÁC TOKEN NHẬP NHẰNG bị loại có chủ ý: vũ (vũ khí), đỗ (đỗ xe),
        // ngô (bắp ngô), dương (đại dương), trang (trang web), nội (nội bộ),
        // quốc (tổ quốc) — hiện thường an toàn hơn hoa sai.
        "nguyễn" to "Nguyễn", "trịnh" to "Trịnh", "đặng" to "Đặng", "bùi" to "Bùi",
    )
}
