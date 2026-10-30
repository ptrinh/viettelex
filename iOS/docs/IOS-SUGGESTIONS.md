# Hệ thống gợi ý của bàn phím iOS (suggestion bar)

Tài liệu thiết kế cho toàn bộ pipeline gợi ý trên `VietTelexKeyboard` (iOS
keyboard extension). Viết 2026-07-24, sau hai vòng research (thiết kế datastore
cá nhân hóa + thuật toán inline suggestion) — nguồn tham khảo chính: Gboard
federated n-gram, SwiftKey dynamic model, Grammarly personal LM blog, KenLM,
kinh nghiệm pinyin IME.

## Tổng quan

Thanh gợi ý (30pt — quyết định giữ 30pt thay vì 44pt như stock, 2026-07-24; từ 18/10/2026 thành cài đặt
**Chiều cao thanh gợi ý** Thấp 30 / Vừa 36 (mặc định) / Cao 44 — xem mục cuối; chỉ hiện khi bật toggle
**Thanh gợi ý** trong app) có **ba trạng thái** theo ngữ cảnh gõ:

| Trạng thái | Hiển thị | Nguồn dữ liệu |
|---|---|---|
| Field trống, chưa gõ | 3 từ user hay mở đầu nhất | `UserLangModel.topWords` |
| Vừa space sau một từ ("Anh ␣") | 3 từ **kế tiếp** dự đoán | `SuggestRank.nextFill`: có trigram tĩnh (prev2, prev) ⇒ bộ ba người dùng đã gõ → trigram tĩnh → `UserLangModel.nextWords`; không ⇒ nextWords (trigram ⊕ bigram ⊕ seed) rồi lấp bằng bigram tĩnh (tầng 7) |
| Đang gõ dở một từ | `["nguyên văn"] \| ứng viên 1 \| ứng viên 2 (hoặc ≤3 emoji)` | `VNSuggest` (inline) + trigram/bigram tĩnh (tầng 7) + `EmojiSuggest` |

Rule ngữ cảnh cứng chạy trước cả ba: token trước con trỏ kết thúc bằng `@` →
gợi `gmail.com / yahoo.com / outlook.com`; kết thúc bằng `.` sau chữ/số → gợi
TLD `com / vn / net`. Các fragment này chèn không kèm space và không đi qua
datastore (token chứa `@`/`.` không phải "từ").

Chip số chạy song song cả hai trạng thái có chữ (xem tầng 8): khi token trước con
trỏ là số/số tiền/biểu thức "…=", **một** chip chiếm slot GIỮA — literal vẫn ở slot
đầu, nội dung slot giữa dời sang slot 3. Các chip khác (hoàn tác, clipboard, "Thêm
dấu") tranh slot theo **Thứ tự ưu tiên slot** bên dưới.

Hành vi bấm nhận: **nguyên văn** = giữ như đã gõ; **từ** = thay từ đang gõ +
space, đồng thời **học với weight 2**; **emoji** = thay từ bằng emoji (hành vi
QuickType). Tự tắt ở field từ chối gợi ý (`isSecureTextEntry`,
`autocorrectionType == .no`) — giống bàn phím stock.

## Các tầng dữ liệu

### 1. `VNSuggest` + `VNLexicon2Data` — inline suggestion (từ đang gõ dở)

- **Lexicon**: 7.184 âm tiết tiếng Việt (tập đóng, danh sách hieuthi) + tần
  suất văn nói OpenSubtitles, generate bởi `Scripts/gen-vnlexicon.py` thành
  blob tĩnh (~90KB) nằm thẳng trong binary — **zero cold-start**, quan trọng
  vì extension bị iOS kill/respawn liên tục.
- **Chuẩn hóa dấu kiểu cũ** lúc build: `hoà→hòa`, `thuý→thúy` — CHỈ với âm
  tiết mở (cặp oa/oe/uy ở cuối từ); có coda giữ nguyên (`toàn`, `thuyền`),
  sau `q` giữ nguyên (`quý` — u là glide).
- **Decompose**: mỗi ký tự → `(base, quality, tone)` pack 1 byte
  (`attr = quality<<3 | tone`; quality: 0 none / 1 â-ê-ô / 2 ơ-ư-ă / 3 đ;
  tone: 0-5 ngang sắc huyền hỏi ngã nặng). Bảng tra runtime ~190 ký tự, O(1)
  mỗi char, không allocation.
- **Lookup mỗi phím**: binary search range trên folded key (loại 99% lexicon)
  → post-filter **tương thích dấu** từng ký tự:
  - ký tự CHƯA bỏ dấu khớp mọi biến thể: gõ `to` → tôi, tớ, **toàn**…
  - quality đã chốt phải trùng: gõ `tô` → tôi, tối, tội… (**toàn** bị loại)
  - tone đã chốt phải trùng: gõ `tò` → tòa, tồi… (**tôi/tới** bị loại;
    `tồi` vẫn hợp lệ vì quality chưa chốt)
  - prefix 1 phím đi qua bucket **top-32 mỗi chữ cái** precomputed (hot path).
- Chi phí: **<50µs/phím** (budget 1-2ms). Trie/DAWG bị bác có chủ ý: ở scale
  7-15k entries chúng không thắng gì mà trả giá effort + cold-start.
- `VNSuggest.contains(word)` (binary search, zero RAM phụ) là nguồn
  "từ-trong-từ-điển" cho ngưỡng học của UserLangModel.

### 2. `UserLangModel` — datastore cá nhân hóa

- **Cấu trúc** (logic): `uni [từ: count]`, `bi [prev → next → count]`,
  `tri ["p2␁p1" → next → count]`. **Lưu trong RAM dạng gọn** (`UserLMTables`, 09/2026): từ
  intern thành id, uni = mảng count theo id, bi = mảng sắp `(next id<<32 | count)` theo prev id,
  tri = `[(p2<<32|p1): slot]` → mảng như bi. Lookup O(1)/O(log n), không scan; ngữ nghĩa y hệt
  bản dict cũ (property test `UserLMCompactTests` so với `LegacyUserLangModel`).
  Cap 3000/6000/3000, quá trần thì chia đôi mọi count (từ hiếm rơi về 0).
- **Học**: mỗi từ commit (+1; suggestion được bấm nhận +2 — tín hiệu mạnh
  hơn). Trigram chỉ ghi khi nền bigram (p2,p1) đã đạt count ≥2 — chống noise.
  Chống học typo: chỉ chữ cái thuần ≤12 ký tự, loại chuỗi lặp ≥3 ("heeeyyy");
  **learning-vs-suggesting** (pattern Grammarly): từ NGOÀI lexicon phải đạt
  count ≥3 mới được *xuất hiện* trong gợi ý (vẫn *đếm* từ lần đầu).
- **Ranking next-word**: linear interpolation với Bayesian shrinkage —
  `λ_tri = n/(n+2)`, `λ_bi = n/(n+4)`:
  `score = λ_tri·P_tri + λ_bi·P_bi + 0.1·P_uni + (1−λ_bi)·0.9·P_seed`
  (seed rank i → 0.5^i). Prev mới gặp 1-2 lần → tin seed; gặp nhiều → tin dữ
  liệu cá nhân. Một lần gõ nhầm không đè nổi seed curated (có golden test).
- **Decay**: mỗi ≥7 ngày, mọi count ×0.7^tuần lúc load (một timestamp toàn
  cục duy nhất — không lưu thời gian per-từ). Hồ sơ phản ánh thói quen gần đây.
- **Persistence**: nhị phân VTL2 `App Group/userlm.bin` (little-endian, CRC32, chung layout
  Android), ghi atomic, coalesce 5s sau phím cuối + khi bàn phím đóng. Bản cũ `userlm.plist`
  (và JSON v1) được chuyển một lần — plist chỉ bị xoá sau khi userlm.bin ghi xong và đọc lại
  khớp; file hỏng (CRC) ⇒ dùng plist nếu còn, không thì rỗng. Sao lưu/Từ điển cá nhân đi qua
  `UserLangModel.Plain` (dict) nên JSON sao lưu không đổi.
  SQLite trong App Group bị bác có chủ ý (anti-pattern iOS — corruption khi
  extension bị suspend).
- **Ranking inline**: điểm ứng viên khi đang gõ dở =
  `log(staticFreq+1) + 2.5·log(personalCount+1) + 4·[có trong nextWords ngữ cảnh] + 1.5·[chỉ-còn-thiếu-dấu] + bigram`
  (bigram = tầng 7). Logic thuần ở `SuggestRank.rankInline` (SuggestionSupport); hoà điểm giữ
  thứ tự pool (tần suất tĩnh) để iOS ≡ Android.
- **Từ điển cá nhân** (`manual`): từ người dùng tự thêm trong app (≤24 ký tự) — gợi ngay,
  không cần đạt ngưỡng count, vào pool hoàn thiện với freq trần; sao lưu/đồng bộ cùng backup.
- **Ẩn danh** (thủ công trong app, hoặc ô không-học): không học từ, không lưu clipboard,
  không chip clipboard.
- **Bảng gọn + file** (`UserLMTables` / `UserLMCodec` "VTL2") nằm riêng ở `UserLMTables.swift`
  (16/10/2026) để **máy tính** dùng đúng mã này cho "Học từ bạn gõ" của gợi ý từ cạnh con trỏ:
  `App/Sources/LearnedModel.swift` (macOS + Linux; Windows port C++ `windows/app/core/learned_words.*`,
  golden cột `learn`). Khác iOS: kho máy tính không mồi seed vào bảng — seed là dòng
  `SeedNextData` truyền vào `nextWords(seeds:)` (mô hình rỗng ⇒ đúng kết quả cũ); cặp học được
  chỉ gợi ý sau MỘT từ khi đã gõ ≥ 2 lần (`learnedPairMin` = `SuggestRank.learnedTriMin`).

### 3. `SeedData` — mồi ban đầu

Inject qua `seedIfEmpty()` khi datastore trống (cài mới / sau nút **Xóa từ đã
học**). ~1.140 unigram + ~930 bigram, sinh bởi `Scripts/gen-seed-data.py` (18/10/2026; docs/DATA-SOURCES.md
mục "SeedData"):

- Lõi hội thoại: 800 âm tiết + 600 cặp (PMI ≥ 1) từ OpenSubtitles v2024 + lát diễn đàn FineWeb-2 + Tatoeba,
  + lớp chọn tay `Scripts/seed-curated.txt` (ko, đc, haha…, cặp hội thoại của seed cũ), weight log-scale **max 50**.
- ~112 từ tiếng Anh hay pha trong chat Việt (ok, thanks, meeting…), cap ≤18.
- Proper noun (weight 3-15, dưới lớp hội thoại): địa danh VN/quốc tế, thương
  hiệu (SenPrints, FPT, VinFast…), tech (GitHub, Claude, ChatGPT…), OS, crypto,
  họ/đệm/tên VN với **chuỗi bigram họ→đệm→tên** (Nguyễn␣ → văn/thị → hùng/lan).
- Cụm đa âm tiết luôn tách thành **bigram nối** (`hồ→chí` + `chí→minh`) để gợi
  ý trôi liên tiếp cả chuỗi.
- **Hợp đồng weight**: gõ thật +1/lần vượt seed sau 2-3 ngày; decay tuần làm
  seed mờ dần — seed chỉ là bệ đỡ ngày đầu.

### 4. `EmojiSuggest` — emoji theo nghĩa từ

721 khóa generate từ `kid-words.json` + bản dịch EN của learn-site + bảng
"emoji họ hàng" curated: từ Việt, dạng KHÔNG DẤU và từ Anh cùng nghĩa trả về
cùng bộ ≤3 ứng viên (`yêu ≡ yeu ≡ love → ❤️ 💕 💗`).

**Dự phòng tiếng Anh (10/2026, `EmojiSearch.typing`, iOS + Android)**: bảng trên không có
từ → tra NGUYÊN khoá trong section SKEN của emoji.bin (từ khoá CLDR en, binary search trên
blob mmap): `japan → 🇯🇵`, `pizza → 🍕`, cụm "từ trước + từ này" (`united states`, `hot dog`).
Chỉ khi từ đang gõ toàn chữ ASCII (có dấu thì thôi); khoá trùng âm tiết Việt không dấu,
tiền tố âm tiết hay < 3 chữ đã bị script lọc; khoá > 24 emoji (`face`, `flag`) không gợi ý.
Mã nước 2 chữ chỉ khi gõ IN HOA đúng nguyên văn (`JP`, `VN`, `UK`; `jp`/`Jp` không ra) —
65/259 mã trùng âm tiết Việt (la, ma, to, do, ca, co…).

### 5. `DisplayCase` — case chuẩn khi hiển thị

Datastore case-fold toàn bộ; bảng `DisplayCase` map dạng thường → dạng chuẩn
lúc HIỂN THỊ và chèn (`senprints → SenPrints`, `iphone → iPhone`,
`macos → macOS`, `nguyễn → Nguyễn`). Nguyên tắc: **chỉ token không nhập
nhằng** — vũ/đỗ/ngô/trang/nội/quốc bị loại có chủ ý (thà hiện thường còn hơn
hoa sai giữa câu). Học vẫn đếm dưới khóa thường.

**Shift / Caps Lock (`SuggestionCase`, như Gboard — 10/2026)**: áp SAU DisplayCase,
chỉ lên vài ứng viên đang hiện, cả iOS lẫn Android (`DisplayCase.swift` / `DisplayCase.kt`):

| Trạng thái | Chưa gõ (gợi ý từ kế tiếp / mở đầu) | Đang gõ dở |
|---|---|---|
| Shift tắt | giữ nguyên (`bên`) | theo chữ đã gõ |
| Shift một-lần (tay hoặc đầu câu) | Hoa đầu (`Bên`) | theo chữ đã gõ |
| Caps Lock | HOA HẾT (`BÊN`) | HOA HẾT |

"Theo chữ đã gõ": ≥2 chữ cái đều hoa ⇒ HOA HẾT; chữ cái đầu hoa ⇒ Hoa đầu (`Bê` → `Bên`);
còn lại giữ nguyên. Hoa đầu không đụng từ đã có chữ hoa (`iPhone`, `SenPrints`); ứng
viên không bắt đầu bằng chữ cái (emoji, số, chip @/.) giữ nguyên. Ô địa chỉ / tìm
kiếm bỏ Shift một-lần (Caps Lock vẫn theo). Đổi Shift ⇒ bar vẽ lại ngay (gộp một lượt,
bỏ qua khi bar đã đúng / đang gõ dở mà không dính Caps). Chọn gợi ý chèn đúng dạng đang
hiện, rồi nhả Shift một-lần như gõ một chữ; học vẫn dưới khóa thường.

### 6. `SensitiveWords` — lọc từ nhạy cảm

Chuẩn ngành (Gboard/SwiftKey): từ tục **vẫn nằm trong datastore và vẫn được
học**, nhưng toggle **Lọc từ nhạy cảm khỏi gợi ý** (mặc định BẬT — cân nhắc
App Store review) giấu chúng khỏi thanh. Phân tầng: chỉ token thô (lồn, địt,
đcm, vcl, tml, sml, fuck…) bị lọc; insult chuẩn mực (khốn nạn, ngu si) và từ
đời thường (cướp, giết, đánh rắm, mày/má) KHÔNG lọc. Khi lọc, over-fetch 6
lấy top-3 nên slot luôn được lấp.

### 7. LM âm tiết tĩnh — `SyllableLM` (bigram 27/09/2026; vnlm.bin + trigram từ 28/09/2026)

Phần bigram của `Resources/vnlm.bin` (Kneser-Ney, cùng file với trigram gõ vuốt; nguồn/giấy phép
`docs/DATA-SOURCES.md`) — CÙNG một instance `SyllableLM.shared` với gõ vuốt (map một lần). PMI =
s2(b, c) + uniAdj(c) ≈ ln(P(c|b) / P(c)); thanh gợi ý chỉ dùng mục TƯỜNG MINH (thiếu = 0, như
bảng vnbigram.bin cũ — đã bỏ, tiết kiệm 1,2 MB/app). Mục đích: người dùng MỚI (UserLangModel chỉ
có seed) vẫn được gợi ý theo ngữ cảnh.

- **Inline**: `LM = min(12, 3·PMI(ngữ cảnh → ứng viên))`, nhân **0.33** khi có ứng
  viên nào của pool nằm trong nextWords (cá nhân/seed đã có ý kiến về lượt này) ⇒ trần hiệu
  dụng 3.96 < 4 (điểm nextWords) — **cá nhân thắng** khi còn lại ngang nhau (golden: user gõ
  "sao có" 3 lần ⇒ "co" ra có, dù bigram nghiêng cô). PMI = mục trigram (prev2, prev → ứng
  viên) nếu có, không thì mục bigram (`Context.explicitAll`, cả pool một lượt). Không âm tiết
  trước / từ lạ ⇒ 0. (Trước 28/09: bigram, 2.5 / 8 / 0.45.)
- **Từ kế tiếp** (`SuggestRank.nextFill`): có dòng trigram (prev2, prev) (cùng câu — ngữ cảnh
  đã xoá ở dấu câu) ⇒ từ người dùng đã gõ ĐÚNG bộ ba này ≥ 2 lượt (`UserLangModel.trigramCount`,
  tối đa 2) trước, rồi top trigram tĩnh (`Context.forEachNext`: KN lùi γ3 + s2 cho mục chỉ có
  ở bigram; dòng trigram ≥ 6 mục thì chỉ dòng đó), rồi nextWords cá nhân/seed. Không có dòng
  trigram ⇒ như cũ: nextWords giữ trước, còn < 3 thì lấp bằng top bigram. Điểm tĩnh
  `PMI + 10·freq/255` (PMI thuần nghiêng cặp hiếm), qua lọc nhạy cảm + DisplayCase + viết hoa
  đầu câu như mọi gợi ý; cuối cùng mới đệm topWords. Seed đứng sau trigram vì đo cho thấy
  seed/bigram cá nhân đoán kém trigram tĩnh kể cả với người dùng đã học dần (xem Đo).
- **Cụm nhiều âm tiết trong một ô** ("Việt" → "Việt Nam", "thành phố" → "Hồ Chí Minh"): đã
  đo (android `SuggestTrigramTests.tuneDev`), KHÔNG làm — tốt nhất +0,07 điểm phím tiết kiệm
  (ngang nhiễu) mà mất 0,5–3 điểm từ kế tiếp top-3 (ô đơn bị thay).
- **Hiệu năng**: PMI cho pool tính ở `suggestQueue` (nền, cùng generation token); từ kế tiếp
  tra trên main ~µs. Bảng mmap `.alwaysMapped`, đọc tại chỗ: RAM bẩn ≈ 0 (test đo
  phys_footprint sau khi duyệt toàn bảng). Map + hash kiểm lexicon chạy nền ở `viewDidLoad`.
- **Đo** (`SuggestBigramTests`, câu Tatoeba giữ lại, người dùng mới gõ chạm không dấu):
  slot1 0.747 → 0.829, 3 slot 0.880 → 0.938, từ kế tiếp top3 0.111 → 0.271; người dùng đã học
  dần cũng tăng (không tụt). Trọng số chọn bằng lưới `tuneGrid` (Android, `VT_TUNE=1`).
  Chuyển sang vnlm.bin (28/09/2026, lưới lại trên tập dev): slot1 0.830, 3 slot 0.939, từ kế
  tiếp 0.270 — ngang bảng cũ (±0.1 điểm). Thêm trigram (28/09/2026, `SuggestTrigramTests`,
  chọn trên tập dev `suggest-dev.txt`, đo một lần trên heldout — bảng ở docs/DATA-SOURCES.md
  mục "Trigram trên thanh gợi ý"): từ kế tiếp top-1 13,3 → 22,3 %, top-3 27,0 → 37,2 %, slot1
  83,0 → 85,4 %, 3 slot 93,9 → 94,7 %, phím tiết kiệm 52,7 → 57,2 %.

### 8. `NumberChips` — đọc số, định dạng tiền (kết quả phép tính: mục 8b)

Hàm thuần `NumberChips.chip(before:)` (Swift) ≡ `NumberChips.chip(before)` (Kotlin),
cùng kết quả trên fixture chung `KeyboardTests/Fixtures/number-chips.txt`. Không bao
giờ tự thay: chip chỉ hiện, chạm mới thay đúng đuôi đã tính (kiểm lại đuôi context
trước khi xoá — lệch thì bỏ, không xoá mù).

- **Chọn chip** (1 chip / lượt; `…=` không — thuộc `MathResults`):
  số + `k/nghìn/ngàn`, `tr/triệu`, `tỷ/tỉ/ty` (liền hoặc cách: `50k`, `1tr2`,
  `1.2tr`, `2 tỷ`) → `1.200.000 ₫`; số chưa phân nhóm + `đ`/`₫` (≥4 chữ số) →
  `1.250.000đ` (giữ ký hiệu); số đã định dạng + `đ`/`₫`, hoặc + `đồng`/`vnd` → chữ +
  " đồng"; số trơn/có phân cách → chữ. Chuỗi chạm: `1tr2` → `1.200.000 ₫` →
  `một triệu hai trăm nghìn đồng`. Viết hoa chữ đầu khi token ở đầu câu.
- **Không gợi ý**: số trơn mở đầu bằng 0 (số điện thoại, mã) hoặc >12 chữ số
  (số tài khoản); tiền có lẻ dưới 1 đồng.
- **Đọc số**: "linh" (hàm có tuỳ chọn "lẻ"), mười/mươi, mốt sau mươi, lăm sau
  mười/mươi, giữ "bốn" (không "tư"); nhóm 0 bỏ qua, nhóm sau nhóm đầu đọc đủ
  "không trăm" (`1.000.001` = một triệu không trăm linh một); tỷ lặp mỗi 9 chữ số
  (`10^12` = một nghìn tỷ, `10^18` = một tỷ tỷ). Thập phân "phẩy": phần lẻ ≤2 chữ số
  không mở đầu 0 đọc như số (3,14 = ba phẩy mười bốn), còn lại đọc từng chữ số. Âm: "âm".
- **Dấu phân cách** (không đoán): có cả `.` và `,` → dấu sau cùng là thập phân;
  chỉ `,`: 1 lần = thập phân, ≥2 = phân nhóm; chỉ `.`: ≥2 = phân nhóm, 1 lần = phân
  nhóm khi sau nó đúng 3 chữ số và phần nguyên 1–3 chữ số không mở đầu 0
  (`1.250` = 1250), còn lại thập phân kiểu Anh (`1.5`).
- **Chi phí**: chỉ đọc `documentContextBeforeInput` khi token hiện tại hoặc ngay
  trước có chữ số/phép tính (đếm dấu cách kể từ chữ số cuối ≤1).

### 8b. `MathResults` — "Hiện kết quả phép tính" (như Math Results của bàn phím gốc)

Công tắc `mathResults` (mặc định BẬT, trang Gợi ý & từ điển, có trong sao lưu). Hàm thuần
`MathResults.chip(before:)` (Swift) ≡ `MathResults.chip(before)` (Kotlin), fixture chung
`KeyboardTests/Fixtures/math-results.txt`. Chip ở **slot đầu**, mọi chip khác dời phải;
chạm = chèn kết quả sau `=` (tính lại từ context lúc chạm — khác thì bỏ).

- **Khi nào**: ngay sau phím `=` (chip ngầm: xem dưới; phím khác ⇒ không đọc context; công tắc
  tắt ⇒ 0 việc). Không ở ô mật khẩu / URL / email / username / OTP; ô số vẫn có (Android:
  ô số không có thanh gợi ý nên không hiện).
- **Phép tính**: `+ - − * × / ÷ : ^ ( ) %`, trừ một ngôi, có/không khoảng trắng; `x`/`X`
  là nhân chỉ khi đứng giữa hai số (`12x3`, `(1+2)x3`); `^` kết hợp phải, cao hơn trừ một
  ngôi (`-2^2` = -4); `A ± B%` = A ± A·B/100, còn lại `B%` = B/100. Không biến/hàm.
  Biểu thức ≤64 ký tự; dính liền sau chữ cái (`abc12*3=`) → không chip.
- **Số** (khác `NumberChips`: suy từ CẢ biểu thức): dấu lặp trong một số hoặc có cả hai
  dấu (dấu cuối là thập phân) → chắc nhóm nghìn; một dấu không phải dạng `d,ddd` (1–3 chữ
  số không mở đầu bằng 0 + đúng 3 chữ số) → chắc thập phân (`1,5`, `0.500`); `2,500` /
  `26.163` mơ hồ. Có dấu chắc thập phân → dấu kia là nhóm (`26.163*2,5` = 65.407,5); chỉ
  mơ hồ → nhóm nghìn (`26,160*2,500` = 65,400,000). Mâu thuẫn (`1,5+2.5`, `1,500+2.500`)
  → không chip, không lùi sang đuôi ngắn hơn.
- **Kết quả**: nguyên nếu tròn, không thì ≤6 chữ số lẻ (≤12 chữ số có nghĩa), bỏ 0 cuối;
  dấu thập phân = dấu đã suy (chỉ có nhóm → dấu kia; không có dấu nào → `,`); phân nhóm
  nghìn chỉ khi biểu thức có. Chia 0 / |kết quả| ≥ 10^15 / vô hạn /
  NaN / khác 0 mà tròn thành 0 → không chip.
- **Chip ngầm (không cần `=`)** — field report 18/10/2026 ("dấu bằng để rất sâu", `=` chỉ
  ở bàn #+= iPhone): `MathResults.implicitChip` (Swift ≡ Kotlin, dòng `implicit|` của
  fixture) khi văn bản trước con trỏ KẾT THÚC bằng phép tính thật. Chip hiện `= 36`, chạm
  chèn ` = 36`. Controller/session gọi `chipAtCaret` (thường ?? ngầm) sau phím ra chữ số /
  `)` / `%` hoặc ⌫ (công tắc bật, ô cho phép); phím khác / công tắc tắt ⇒ không đọc context.
  Chỉ xét ≤128 ký tự cuối. Luật (`looksLikeExpression`): phải có phép tính hai ngôi; `x`
  không là nhân (`1920x1080`, `3x4`); không số mở đầu bằng 0 (`090…`), không `:` viết liền
  giữa hai số (`10:30`, `16:9`), không ngày `d/m` (≤2 chữ số, 1…31, có số ≤12), không chuỗi
  ≥3 số nguyên nối liền bằng cùng `/` hoặc `-` (`12/10/2026`, `2026-10-18`), không `a-b`
  viết liền với a < b (`5-10`) hay cả hai ≥4 chữ số (`1900-1234`); dính liền sau chữ /
  `#@$_=\&~` → không.
- **Phím `=` ở bàn 123** (iPhone + Android): giữ `/` → hàng biến thể `/ = \` (KeyVariants).

### 9. `ClipDetect` — chip tách số từ clipboard (Clipboard nâng cao, Plus)

Vừa copy (thẻ Dán đang mời) và nội dung chứa số: `ClipDetect.detect` (Swift ≡ Kotlin) tách
tối đa 1 chip mỗi loại theo thứ tự OTP → SĐT → STK ("Dán OTP 482913"). Bar hiện **tối đa 2
chip + ô "Dán"** nguyên văn, thay thẻ Dán; chạm = chèn giá trị, không space, không học. Tắt
khi ẩn danh, ô bảo mật, clipboard "concealed"/nhạy cảm; khoá sau PlusGate `.advancedClipboard`.

### 10. `AddTones` — thêm dấu cả câu (Plus)

Chưa gõ dở, chữ trước con trỏ là câu không dấu có thể thêm dấu ⇒ chip **"Thêm dấu"** ở slot
đầu (Viterbi trên lưới âm tiết: vnlexicon + bigram vnlm.bin + đếm cá nhân — `AddTones.swift`, fixture
chung `add-tones.txt`). Chỉ thay khi bấm, fail-safe (đuôi context phải đúng bản gốc). Sau khi
thay: chip **"↩︎ Hoàn tác"** (và ⌫ ngay sau) trả bản gốc, đoạn vừa hoàn tác không mời lại.

### 11. Ô hoàn tác một lượt — vuốt ⌫, công cụ văn bản

- **"↩︎ Khôi phục"**: sau vuốt ⌫ xoá theo từ (`WordDelete`), chèn lại đoạn vừa xoá.
- **"↩︎ Hoàn tác"** công cụ văn bản (`TextTools`, Plus): sau khi đổi HOA/thường/Hoa Từ/Hoa câu/
  Xoá dấu (từ lưới mẫu câu), trả lại văn bản cũ.
- Cả hai (và "Hoàn tác" thêm dấu) sống tới phím kế tiếp; hành động mới xoá lời mời cũ.

### 12. "Sửa lỗi bằng Apple Intelligence" (Plus, iOS 26+, mặc định TẮT — 30/10/2026)

Công tắc `aiProofread` (Tính Năng → Gợi ý & từ điển, màn Plus; sao lưu). App hiện công tắc theo
trạng thái model (`AISettingUI`, Shared/PlusConfig.swift): máy không hỗ trợ ⇒ ẩn; chưa bật Apple
Intelligence / mô hình đang tải ⇒ hiện nhưng khoá + một dòng hướng dẫn. Trên máy hết — không mạng.

- **Không link FoundationModels vào bàn phím**: phần gọi model ở `VTIntelligence.framework` (app chủ,
  `iOS/VTIntelligence/IntelligenceEngine.swift`), bàn phím `dlopen` lần đầu cần (`AIAssistLoader`,
  cùng mẫu VTTranslate). Tắt ⇒ controller giữ `ai = nil`: không đọc vùng chọn, không dlopen, không
  prewarm. Bật mà model không dùng được lúc chạy ⇒ không có chip ✨ (không báo lỗi).
- **Vùng chọn ≥ 2 từ** (≤ 1000 ký tự) hoặc **không chọn gì** (cả ô ≤ 500 ký tự, ≥ 2 từ, chỉ sau khi
  ngừng gõ 0,8 s và ô khác lần sửa trước) ⇒ chip **"✨ Sửa lỗi"** ở slot đầu. Model chỉ chạy khi chạm
  (session mới mỗi lần, greedy, `@Generable` — mỗi dòng một mục, ráp lại đúng xuống dòng gốc), hạn
  10 s, chạy nền (chip "✨ Đang sửa…", chạm để huỷ). Kết quả qua kiểm (`AIText.assembleProofread`:
  độ dài/số từ không lệch quá đà, giữ số dòng + emoji) rồi mới hiện **bảng xem trước** phủ vùng phím
  (không đổi chiều cao), từ đã sửa được tô (`WordDiff`, LCS theo từ). **Áp dụng**: vùng chọn phải
  còn đúng chữ gốc; cả ô ⇒ dời con trỏ cuối/đầu/cuối để chắc ô CHỈ chứa bản gốc (`AIField`), xoá
  `deleteCount` (= số scalar) rồi chèn, đọc lại kiểm. Sau đó **"↩︎ Hoàn tác"** tới phím kế.
- **Chọn đúng 1 từ** ⇒ sau 0,35 s đứng yên, hỏi ≤ 3 từ thay thế theo ngữ cảnh quanh từ (≤ 160 ký
  tự mỗi phía, trong đoạn) — hiện như từ kế tiếp; chạm = thay (giữ dấu câu dính quanh từ).
- Đo trên simulator (Xcode 27.1, máy chủ có Apple Intelligence): lần đầu 5–8 s (prewarm còn ~5 s),
  sau đó 1,3–2,8 s; RAM tiến trình +~4 MB sau yêu cầu đầu (model chạy ở tiến trình hệ thống). Debug
  log ghi RAM trước/sau mỗi yêu cầu.

## Thứ tự ưu tiên slot

Mọi loại chip cùng tranh các slot (mặc định 3 — xem "Số từ gợi ý" bên dưới). Hàm THUẦN `SuggestionSlots.arrange` (Swift) ≡
`SuggestionSlots.arrange` (Kotlin, `android/keyboard/.../SuggestionSlots.kt`) quyết định, cùng
bảng ca kiểm `SuggestionSlotsTests` hai nền tảng. Từ cao xuống thấp:

| # | Loại | Chỗ hiện | Ghi chú |
|---|---|---|---|
| 0 | Xem trước vuốt ⌫ | pill giữa bar (Android) | tạm thời khi đang kéo, đè tất cả |
| 1 | Hoàn tác một lượt: Khôi phục (vuốt ⌫) › Hoàn tác công cụ văn bản › Hoàn tác thêm dấu | iOS: slot đầu, gợi ý dời phải; Android: pill giữa bar (kiểu Gboard) | thắng clipboard/thẻ Dán |
| 2 | Clipboard vừa copy: ≤2 chip STK/SĐT/OTP + ô "Dán" › thẻ Dán | thay cả bar | chỉ khi chưa gõ dở, sau khoảng trắng |
| 3 | "Thêm dấu" | slot đầu | nhường clipboard |
| 4 | Chip số | luôn slot GIỮA | nội dung slot giữa dời sang slot 3; slot 3 là vùng emoji thì rơi |
| 5 | Chữ: nguyên văn / ứng viên (chip gõ tắt = ứng viên chính) / emoji; hoặc từ kế tiếp (bigram, email/TLD, biến thể gõ vuốt) | 3 slot | iOS từ kế tiếp trái→phải; Android tốt nhất ở giữa |

Ví dụ: `[Thêm dấu][1.200.000 ₫][và]`; vừa copy tin OTP: `[Dán OTP 482913][Dán]` (chip số, "Thêm
dấu" ẩn); sau vuốt ⌫ trong lúc có chip số: iOS `[↩︎ Khôi phục][chip số][từ]`.

### Số từ gợi ý (`suggestionCount`, 10/2026)

Cài đặt "Số từ gợi ý" (Tính Năng → Gợi ý, hàng − / +): `0` = **Tự động** = 3 ô (hành vi cũ, cả
iPhone/iPad, cả điện thoại/tablet Android), hoặc `1…5`. Logic thuần: `SuggestionCount`
(`iOS/Shared/SuggestionCount.swift` ≡ `android/keyboard/.../SuggestionCount.kt`), bảng ca
`SuggestionCountTests` hai nền tảng. Có trong sao lưu / iCloud / PrefSync (cùng khoá).

- **Số ô hiện** = `SuggestionCount.fit(setting, bề rộng bar)`: không quá số chọn, mỗi ô ≥ 44pt/dp,
  tối thiểu 1 — bar chật (máy hẹp, nút 😊 "Thanh trên", 📋, icon con trỏ Android khi bar rỗng) thì
  hiện bớt ô; đổi bề rộng (xoay máy) vẽ lại ngay.
- **Ứng viên**: controller/session xin `resolved` (≤ 5) — `nextFill(need:)`, `padWords(need:)`,
  `topWords`, ứng viên đang gõ hạng 3+ vào `moreWords`. Không thêm việc mỗi phím ngoài ≤ 5 ứng viên.
  Biến thể gõ vuốt vẫn ≤ 3 (decoder), ô dư để trống.
- **Bố cục** (`arrange(count:)`; count = 3 y nguyên bảng trên): đang gõ — ô 0 nguyên văn, ô 1 ứng
  viên chính, rồi word2, moreWords… trái→phải; có emoji (count ≥ 3) ⇒ ô cuối là vùng emoji (≤ 3
  emoji khi 3 ô, ≤ 2 khi 4–5 ô); count < 3 ⇒ không emoji; count = 1 ⇒ chỉ ứng viên chính (không có
  thì nguyên văn, không đệm từ phổ biến). Từ kế tiếp: iOS trái→phải; Android tốt nhất ở ô giữa
  `(count−1)/2` rồi xen kẽ trái/phải (`nextOrder`: 5 ô = [2,1,3,0,4]); Android tô đậm ô
  `primaryIndex`. Chip dẫn đầu (hoàn tác/Thêm dấu/↩︎) ô 0; chip số chèn ô 1 (count 1: ô 0), phần
  sau dời phải; kết quả phép tính chèn ô 0. Chip clipboard / thẻ Dán / pill không theo số ô.
- Chữ dài: iOS co chữ (≥ 0.7) rồi cắt giữa; Android cắt giữa (…) theo bề rộng ô.

## Settings (App Group `group.com.viettelex`)

| Key | Mặc định | Ý nghĩa |
|---|---|---|
| `showSuggestions` | true | Bật thanh gợi ý (bàn phím 246pt ↔ 216pt) |
| `learnWords` | true | Cho phép học từ hay dùng |
| `filterSensitive` | true | Lọc từ tục khỏi gợi ý |
| `suggestionCount` | 0 | "Số từ gợi ý": 0 = Tự động (3 ô), 1…5 — xem "Số từ gợi ý" ở trên |
| `suggestionBarHeight` | "medium" | "Chiều cao thanh gợi ý": low / medium / high — xem "Chiều cao thanh gợi ý" |
| `suggestInNoSuggestFields` | true | "Gợi ý cả khi ứng dụng tắt gợi ý" (#113) — xem dưới |
| nút **Xóa từ đã học** | — | Xóa `userlm.bin` (+ `userlm.plist` cũ nếu còn); lần mở sau seed lại |

## Ô ứng dụng tắt gợi ý (#113)

Như Gboard/Laban: công tắc `suggestInNoSuggestFields` (mặc định BẬT, sao lưu, Android cùng key).
Bảng quyết định THUẦN — iOS `StripMode.of/learns` (`FieldPolicy.swift`), Android `StripMode.of/learns`
(`KeyboardSession.kt`); test `SuggestInNoSuggestFieldsTests` hai nền tảng.

| Ô | BẬT | TẮT | Tự sửa | Học từ |
|---|---|---|---|---|
| Ô chữ app tắt gợi ý (iOS `autocorrectionType == .no`, Android `NO_SUGGESTIONS` / VISIBLE_PASSWORD giả ở ô chat) | gợi ý đầy đủ | chỉ thanh công cụ | KHÔNG | KHÔNG (cả khi tắt) |
| Mật khẩu / OTP / ẩn danh (thủ công, Android NO_PERSONALIZED_LEARNING) / bàn số-SĐT-ngày | dải trống | dải trống | — | — |
| Ô literal (URL thuần, username, FORCE_ASCII) | thanh công cụ (+ chip URL) | như bật | — | — |
| Email | chip đuôi mail | như bật | — | — |

- Ô địa chỉ / tìm kiếm (iOS `.URL`/`.webSearch` hoặc Enter = Go/Search; Android
  `FieldMapping.isAddressOrSearch`): gợi ý chữ thường (`lowercaseSuggestions`).
- iOS thanh địa chỉ ở chế độ đầy đủ: chip URL (`https://` `www.` `.com` `.vn`) chỉ ở "vị trí tên
  miền" — ô trống, hoặc token trước con trỏ có "." / "://" (`StripMode.prefersURLChips`); còn
  lại gợi ý chữ.

## Privacy

- Chỉ đếm **tần suất** từ đơn + cặp/bộ-ba từ — không lưu câu, không thứ tự gõ,
  không timestamp per-từ. Ô mật khẩu không bao giờ đi qua pipeline.
- Toàn bộ dữ liệu nằm trong App Group container trên máy; không Full Access,
  không network.

## Bản đồ file

| File | Vai trò |
|---|---|
| `ios/Keyboard/VNSuggest.swift` | Engine inline suggestion (lookup + compat filter) |
| `ios/Keyboard/VNLexicon2.swift` | GENERATED — lexicon 7.184 âm tiết (blob) |
| `Scripts/gen-vnlexicon.py` | Script tái lập lexicon (nguồn hieuthi + OpenSubtitles) |
| `ios/Keyboard/UserLangModel.swift` | Datastore cá nhân hóa n-gram |
| `ios/Keyboard/SeedData.swift` | GENERATED + curated — seed ban đầu |
| `ios/Keyboard/EmojiSuggest.swift` | GENERATED — emoji theo nghĩa |
| `ios/Keyboard/DisplayCase.swift` | Case chuẩn proper noun |
| `ios/Keyboard/SensitiveWords.swift` | Bộ lọc từ nhạy cảm |
| `ios/Keyboard/SyllableLM.swift` | LM âm tiết tĩnh vnlm.bin (mmap): trigram gõ vuốt + bigram PMI thanh gợi ý / Thêm dấu |
| `ios/Keyboard/SuggestionSupport.swift` | `SuggestRank` (xếp hạng inline + lấp từ kế tiếp), `SuggestionFill` |
| `ios/Keyboard/NumberChips.swift` | Chip số: đọc chữ / định dạng tiền / máy tính (thuần) |
| `ios/Keyboard/ClipDetect.swift`, `ClipboardFeature.swift` | Chip tách số clipboard, lịch sử, ẩn danh |
| `ios/Keyboard/AddTones.swift` | Thêm dấu cả câu (Viterbi, thuần) |
| `ios/Keyboard/TextTools.swift` | Công cụ văn bản + hoàn tác (thuần) |
| `ios/Keyboard/SuggestionSlots.swift` | Thứ tự ưu tiên slot (thuần) |
| `ios/Keyboard/KeyboardViewController.swift` | Điều phối: context, học, build SuggestionSet |
| `ios/Keyboard/KeyboardView.swift` | UI thanh gợi ý (SuggestionSet → slots) |

Tests: `ios/KeyboardTests/EngineBridgeTests.swift` — goldens cho compat-match
("tô" ⊅ toàn), shrinkage (1 lần gõ nhầm không đè seed), trigram gating,
ngưỡng học từ lạ, seed contract (max weight ≤50), filter tiers, display-case.
`ios/KeyboardTests/SuggestBigramTests.swift` (≡ android `SuggestBigramTests.kt`) — số đo heldout
trước/sau làm ngưỡng hồi quy, cá nhân thắng, độ trễ, RAM bẩn.
`ios/KeyboardTests/SuggestTrigramTests.swift` (≡ android `SuggestTrigramTests.kt`) — trigram: duyệt
dòng ≡ `score`, bộ ba đã học đứng trước, fixture parity `suggest-trigram-parity.txt` (Kotlin sinh),
heldout trước/sau (từ kế tiếp top-1/3, slot, phím tiết kiệm, học dần), độ trễ cả lượt ≤ +20 %.
`ios/KeyboardTests/NumberChipsTests.swift` + android `NumberChipsTests.kt` — cùng
fixture `number-chips.txt` (đọc số, viết tắt k/tr/tỷ, biểu thức, chip theo context).
`ios/KeyboardTests/SuggestionSlotsTests.swift` + android `SuggestionSlotsTests.kt` — cùng bảng
ca thứ tự ưu tiên slot (+ một ca render thật trên KeyboardView).
Test đo đạc nặng (heldout, độ trễ, RAM) nằm trong bộ chậm — xem `iOS/README.md` mục Test.

## Đường nâng cấp đã vạch (chưa làm)

- Personal model >50k entries → binary sorted array + mmap.
- Lexicon tĩnh >100k mục (lên tầng từ ghép/cụm) → double-array trie / marisa,
  bài học pinyin IME.
- Học case từ chính user (hiện DisplayCase là bảng tĩnh).
- Gợi ý viết hoa theo ngữ cảnh câu (auto-shift-aware).

## Chiều cao thanh gợi ý (`suggestionBarHeight`, 18/10/2026)

Người dùng báo bar 30pt thấp, hay chạm nhầm. Cài đặt ở **Tính Năng → Giao diện → Bàn phím** (cạnh
"Chiều cao hàng phím"): **Thấp** (30, bố cục cũ) / **Vừa** (36, mặc định) / **Cao** (44). Khoá App Group
`suggestionBarHeight` (chuỗi, cùng Android), giá trị lạ ⇒ Vừa; có trong sao lưu (BackupFormat).

- `SuggestionBarHeight` (Shared, THUẦN) cho `delta` 0 / 6 / 14 pt so với Thấp. `KeyboardView.openStripNow` =
  strip cũ (stock 29 dọc / 34) + delta ⇒ tổng bàn phím tăng **đúng** delta; hàng phím, thu gọn (14), tắt (0),
  plane emoji (tổng giữ nguyên) không đổi.
- Hàng nội dung bar = 20 + delta (chữ gợi ý, chip, icon ☰/⌄/📋/😊 canh giữa hàng này); vùng chạm ô gợi ý
  phủ trọn bar + nở xuống tới mép hàng phím như cũ. Cỡ chữ ô 17/18/19, chip 14/15/15.
- iPhone **ngang**: delta kẹp ở Vừa (+6) — màn thấp. Máy gập mở / iPad không kẹp.
- Host cấp thiếu chiều cao: bar Vừa/Cao co lại trước (sàn 20 = Thấp), hết chỗ mới dời lên như cũ.
- Đọc một lần mỗi lần hiện bàn phím (`applyAppearance`) — 0 chi phí mỗi phím.
- Android song sinh: strip 35 / 42 (mặc định, như cũ) / 51 dp — cùng tỉ lệ 30/36/44.

## Tiếng Anh giữa câu Việt (`EnglishAssist`, 19/10/2026)

Góp ý người dùng: từ tiếng Anh dài hay không nhớ cách viết. Chế độ tiếng Việt, theo PHÍM THÔ của từ đang gõ
(`Keyboard/EnglishAssist.swift`, song sinh `android/.../EnglishAssist.kt`):

- **Hoàn thành**: phím thô ≥ 4 chữ a–z là tiền tố từ enlexicon và cách đọc Việt yếu — cùng ngưỡng macOS
  `PredictionLogic.prefersEnglish` (150 / 80 / 60). Không âm tiết Việt nào khớp ⇒ tiếng Anh luôn. Hai từ Anh đầu
  dẫn, rồi ứng viên Việt.
- **Sửa chính tả**: không tiền tố Anh nào khớp, không âm tiết Việt nào khớp, ≥ 5 phím ⇒ từ Anh cách ≤ 1 sửa
  (≤ 2 khi ≥ 8 phím; Damerau OSA, giữ chữ đầu, tính cả tiền tố khi đang gõ dở: "acomm" → accommodation), tần
  suất ≥ 80, tối đa 2. Bản sửa chạm trượt tiếng Việt (nếu có) đứng trước.
- 0 chi phí với tiếng Việt: chữ hiện đã có dấu/thanh mà có âm tiết khớp, hoặc âm tiết khớp đủ mạnh ⇒ trả nil trước
  khi chạm lexicon Anh (heldout: 0/4088 tiền tố bật nhầm; corpus bench 2/159 phím đọc lexicon). Chạy trên hàng
  đợi nền; dùng `SwipeEnglish.lexicon` vốn đã nạp ⇒ không thêm RAM. Lọc nhạy cảm + DisplayCase như gợi ý Việt.
