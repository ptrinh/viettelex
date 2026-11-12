// DisplayCase — case chuẩn cho proper noun khi HIỂN THỊ gợi ý. Datastore
// case-fold toàn bộ để đếm ("senprints"), nhưng nút gợi ý và chữ được chèn
// phải ra "SenPrints". CHỈ chứa token không-nhập-nhằng: brand/sản phẩm/OS,
// địa danh nước ngoài, họ Việt an toàn. Token nhập nhằng (văn ↔ văn bản,
// pháp ↔ phương pháp, trần ↔ trần nhà) KHÔNG đưa vào — thà hiện thường còn
// hơn viết hoa sai giữa câu.
import Foundation

enum DisplayCase {
    /// Trả về dạng hiển thị chuẩn; từ không có trong bảng giữ nguyên.
    /// `after`: từ đứng ngay trước — token nhập nhằng được viết hoa THEO NGỮ
    /// CẢNH chuỗi tên riêng ("hà"→"nội" hiện "Nội", nhưng "nội" đơn lẻ giữ
    /// thường vì còn là "nội bộ").
    static func apply(_ w: String, after prev: String? = nil) -> String {
        if let p = prev?.lowercased(), chains[p]?.contains(w) == true {
            return w.prefix(1).uppercased() + w.dropFirst()
        }
        return proper[w] ?? w
    }

    /// Chuỗi tên riêng: prev → các next chỉ-proper-khi-đứng-sau-prev.
    static let chains: [String: Set<String>] = [
        // địa danh VN
        "hà": ["nội", "nam", "tĩnh", "giang"],
        "đà": ["nẵng", "lạt"],
        "nha": ["trang"],
        "phú": ["quốc", "thọ", "yên"],
        "sài": ["gòn"],
        "hồ": ["chí"], "chí": ["minh"],
        "việt": ["nam"],
        "cần": ["thơ"],
        "hải": ["phòng", "dương"],
        "hạ": ["long"],
        "quy": ["nhơn"],
        "vũng": ["tàu"],
        "biên": ["hòa"],
        "bình": ["dương", "định", "thuận"],
        "thanh": ["hóa"],
        "hội": ["an"],
        "quảng": ["ninh", "nam", "ngãi", "bình", "trị"],
        "nghệ": ["an"],
        "lâm": ["đồng"],
        "đồng": ["nai", "tháp"],
        "long": ["an"],
        "tây": ["ninh"],
        // 11/2026: nước láng giềng + tỉnh (chỉ cặp không còn nghĩa thường: bỏ hòa bình, thái bình)
        "hàn": ["quốc"],
        "trung": ["quốc"],
        "nhật": ["bản"],
        "thái": ["lan", "nguyên"],
        "đài": ["loan"],
        "bắc": ["ninh", "giang", "kinh"],
        "nam": ["định"],
        "ninh": ["bình", "thuận"],
        "kiên": ["giang"],
        "cà": ["mau"],
        "sóc": ["trăng"],
        "bến": ["tre"],
        "vĩnh": ["long", "phúc"],
        "lào": ["cai"],
        "điện": ["biên"],
        "yên": ["bái"],
        "hưng": ["yên"],
        "new": ["york"], "san": ["francisco"], "hong": ["kong"],
        // Gen Z ("gen" đứng một mình còn là gen di truyền ⇒ chỉ hoa "Z" sau "gen")
        "gen": ["z"],
        "chụp": ["x"],   // chụp X quang
        "phil": ["trinh"],   // Phil Trinh (tác giả)
        // họ → đệm (chuỗi tên người)
        "nguyễn": ["văn", "thị", "đức", "minh", "ngọc", "hữu", "xuân", "thùy", "kim", "hồng", "quốc", "đình"],
        "trần": ["văn", "thị", "đức", "minh", "ngọc", "quốc"],
        "lê": ["văn", "thị", "đức", "minh", "ngọc", "hữu"],
        "phạm": ["văn", "thị", "minh", "ngọc"],
        "hoàng": ["văn", "thị", "minh", "anh"],
        "vũ": ["văn", "thị", "minh"],
        "đặng": ["văn", "thị"],
        "bùi": ["văn", "thị"],
        "đỗ": ["văn", "thị"],
        "ngô": ["văn", "thị"],
        "dương": ["văn", "thị"],
        "trịnh": ["văn", "thị", "xuân"],
        // đệm → tên
        "văn": ["hùng", "tuấn", "dũng", "sơn", "nam", "long", "hải", "minh"],
        "thị": ["hương", "lan", "thu", "ngọc", "hồng", "phương", "hà", "linh"],
    ]

    static let proper: [String: String] = [
        // thương hiệu / sản phẩm
        "senprints": "SenPrints", "printik": "Printik",
        "apple": "Apple", "iphone": "iPhone", "ipad": "iPad", "macbook": "MacBook",
        "samsung": "Samsung", "google": "Google", "facebook": "Facebook",
        "youtube": "YouTube", "tiktok": "TikTok", "zalo": "Zalo",
        "shopee": "Shopee", "lazada": "Lazada", "grab": "Grab",
        "momo": "MoMo", "vnpay": "VNPay", "vietcombank": "Vietcombank",
        "techcombank": "Techcombank", "viettel": "Viettel", "vingroup": "Vingroup",
        "vinfast": "VinFast", "vietjet": "Vietjet", "fpt": "FPT",
        "arsenal": "Arsenal", "liverpool": "Liverpool", "chelsea": "Chelsea",
        "manchester": "Manchester", "bitcoin": "Bitcoin", "ethereum": "Ethereum",
        "binance": "Binance", "usdt": "USDT", "usd": "USD", "vnđ": "VNĐ", "vnd": "VND",
        "netflix": "Netflix", "spotify": "Spotify",
        "github": "GitHub", "claude": "Claude", "chatgpt": "ChatGPT",
        "tesla": "Tesla", "openai": "OpenAI", "anthropic": "Anthropic",
        "yahoo": "Yahoo", "hotmail": "Hotmail",
        // công nghệ / AI / tài chính (18/10/2026)
        "gemini": "Gemini", "grok": "Grok", "ubuntu": "Ubuntu", "copilot": "Copilot",
        "docker": "Docker", "kubernetes": "Kubernetes", "javascript": "JavaScript", "typescript": "TypeScript", "llm": "LLM",
        "nft": "NFT", "etf": "ETF", "ipo": "IPO", "defi": "DeFi",
        "cloudflare": "Cloudflare", "golang": "Golang", "vpn": "VPN", "kotlin": "Kotlin", "panadol": "Panadol", "viettelex": "VietTelex", "phil": "Phil", "covid": "Covid",
        // OS / phần mềm
        "windows": "Windows", "macos": "macOS", "ios": "iOS",
        "android": "Android", "linux": "Linux", "chrome": "Chrome",
        "safari": "Safari", "excel": "Excel", "word": "Word",
        "wifi": "WiFi", "gmail": "Gmail", "outlook": "Outlook",
        // địa danh nước ngoài (token đơn, không nhập nhằng)
        "singapore": "Singapore", "dubai": "Dubai", "london": "London",
        "tokyo": "Tokyo", "sydney": "Sydney", "canada": "Canada",
        "houston": "Houston", "seattle": "Seattle", "miami": "Miami",
        "dallas": "Dallas", "austin": "Austin", "texas": "Texas",
        "california": "California", "washington": "Washington",
        "york": "York", "francisco": "Francisco", "paris": "Paris",
        "bangkok": "Bangkok", "seoul": "Seoul",
        // 11/2026: tên nước / thành phố / hãng viết kiểu Anh có trong từ điển vuốt tiếng Anh (Phil: Saigon…)
        "saigon": "Saigon", "hanoi": "Hanoi", "vietnam": "Vietnam", "america": "America", "europe": "Europe",
        "asia": "Asia", "africa": "Africa", "japan": "Japan", "korea": "Korea", "china": "China",
        "india": "India", "france": "France", "germany": "Germany", "england": "England", "britain": "Britain",
        "australia": "Australia", "thailand": "Thailand", "malaysia": "Malaysia", "indonesia": "Indonesia", "philippines": "Philippines",
        "taiwan": "Taiwan", "russia": "Russia", "italy": "Italy", "spain": "Spain", "mexico": "Mexico",
        "brazil": "Brazil", "egypt": "Egypt", "israel": "Israel", "iran": "Iran", "iraq": "Iraq",
        "ukraine": "Ukraine", "poland": "Poland", "sweden": "Sweden", "norway": "Norway", "denmark": "Denmark",
        "finland": "Finland", "ireland": "Ireland", "scotland": "Scotland", "netherlands": "Netherlands", "switzerland": "Switzerland",
        "austria": "Austria", "belgium": "Belgium", "portugal": "Portugal", "greece": "Greece", "cambodia": "Cambodia",
        "laos": "Laos", "myanmar": "Myanmar", "beijing": "Beijing", "shanghai": "Shanghai", "berlin": "Berlin",
        "rome": "Rome", "moscow": "Moscow", "madrid": "Madrid", "amsterdam": "Amsterdam", "vienna": "Vienna",
        "boston": "Boston", "chicago": "Chicago", "vegas": "Vegas", "hollywood": "Hollywood", "manhattan": "Manhattan",
        "brooklyn": "Brooklyn", "florida": "Florida", "hawaii": "Hawaii", "alaska": "Alaska", "ohio": "Ohio",
        "michigan": "Michigan", "virginia": "Virginia", "oregon": "Oregon", "arizona": "Arizona", "colorado": "Colorado",
        "toronto": "Toronto", "vancouver": "Vancouver", "melbourne": "Melbourne", "taipei": "Taipei", "jakarta": "Jakarta",
        "manila": "Manila", "delhi": "Delhi", "mumbai": "Mumbai", "istanbul": "Istanbul", "cairo": "Cairo",
        "jerusalem": "Jerusalem", "munich": "Munich", "milan": "Milan", "barcelona": "Barcelona", "oxford": "Oxford",
        "cambridge": "Cambridge", "harvard": "Harvard", "microsoft": "Microsoft", "amazon": "Amazon", "twitter": "Twitter",
        "instagram": "Instagram", "whatsapp": "WhatsApp", "telegram": "Telegram", "intel": "Intel", "sony": "Sony",
        "toyota": "Toyota", "honda": "Honda", "nokia": "Nokia", "nike": "Nike", "disney": "Disney",
        "wikipedia": "Wikipedia", "python": "Python", "java": "Java",
        "huế": "Huế",
        // họ Việt an toàn (gần như luôn là tên riêng khi đứng một mình).
        // CÁC TOKEN NHẬP NHẰNG bị loại có chủ ý: vũ (vũ khí), đỗ (đỗ xe),
        // ngô (bắp ngô), dương (đại dương), trang (trang web), nội (nội bộ),
        // quốc (tổ quốc) — hiện thường an toàn hơn hoa sai.
        "nguyễn": "Nguyễn", "trịnh": "Trịnh", "đặng": "Đặng", "bùi": "Bùi",
    ]
}

extension DisplayCase {
    /// Dạng tên riêng của một ứng viên gợi ý / từ vuốt `w`: đã có chữ hoa ⇒ giữ nguyên; người
    /// dùng đã viết nhất quán một dạng (UserLangModel.learnedCase — `learned`) ⇒ dạng đó; còn lại
    /// `apply` (bảng tên riêng + chuỗi sau `prev`). Không bao giờ hạ chữ hoa.
    static func resolve(_ w: String, after prev: String? = nil, learned: ((String) -> String?)? = nil) -> String {
        if w.contains(where: { $0.isUppercase }) { return w }
        if let learned, let l = learned(w) { return l }
        return apply(w, after: prev)
    }

    /// Hoa/thường của `word` (đúng như đã gõ, đứng sau `prev`) có là bằng chứng cho bảng hoa/thường
    /// đã học không: chỉ GIỮA CÂU — caller cắt `prev` (nil) ở đầu ô / sau . ! ? / xuống dòng / dời
    /// con trỏ, nên chữ hoa đầu câu (tự hoa hay Shift tay) không bao giờ được tính — và không phải
    /// chữ hoa do CHUỖI tên riêng ("Việt Nam": "Nam" không dạy "nam" thành tên riêng).
    static func casingEvidence(_ word: String, prev: String?) -> Bool {
        guard let p = prev, !p.isEmpty else { return false }
        return chains[p.lowercased()]?.contains(word.lowercased()) != true
    }

    /// `next` (chữ thường) viết hoa vì CHUỖI sau `prev` (không phải tên riêng đứng một mình)?
    static func chainCapitalizes(_ next: String, after prev: String) -> Bool {
        chains[prev.lowercased()]?.contains(next) == true
    }
}

/// Hoa/thường của gợi ý theo Shift + chữ đang gõ — như Gboard / bàn phím stock
/// (feedback 10/2026: bật Shift mà gợi ý vẫn thường). Song sinh Android
/// `SuggestionCase` (DisplayCase.kt). Chỉ áp lên vài ứng viên đang hiện.
///   • Caps Lock ⇒ CHỮ HOA HẾT ("BÊN").
///   • Đang gõ dở: theo chữ đã gõ — ≥2 chữ cái đều hoa ⇒ HOA HẾT; chữ cái đầu hoa ⇒
///     Hoa đầu ("Bê" → "Bên"); còn lại giữ nguyên.
///   • Chưa gõ (gợi ý từ kế tiếp / mở đầu): Shift một-lần (tay hoặc đầu câu) ⇒ Hoa đầu.
///   • Hoa đầu KHÔNG đụng từ đã có chữ hoa (tên riêng/viết tắt: "iPhone", "SenPrints");
///     ứng viên không bắt đầu bằng chữ cái (emoji, số, @/. chip) giữ nguyên.
enum SuggestionCase: Equatable {
    case asIs, capitalized, upper

    enum Shift: Equatable { case off, once, capsLock }

    static func mode(shift: Shift, typed: String) -> SuggestionCase {
        if shift == .capsLock { return .upper }
        var letters = 0, upper = 0
        var firstUpper = false
        for ch in typed where ch.isLetter {
            if ch.isUppercase { upper += 1; if letters == 0 { firstUpper = true } }
            letters += 1
        }
        if letters == 0 { return shift == .once ? .capitalized : .asIs }
        if letters >= 2, upper == letters { return .upper }
        return firstUpper ? .capitalized : .asIs
    }

    func apply(_ w: String) -> String {
        guard self != .asIs, let f = w.first, f.isLetter else { return w }
        switch self {
        case .asIs: return w
        case .upper: return w.uppercased()
        case .capitalized:
            if w.contains(where: { $0.isUppercase }) { return w }
            return f.uppercased() + w.dropFirst()
        }
    }

    /// Gộp: dạng hiển thị của `w` khi Shift = `shift`, chữ đang gõ = `typed`.
    static func display(_ w: String, shift: Shift, typed: String = "") -> String {
        mode(shift: shift, typed: typed).apply(w)
    }
}
