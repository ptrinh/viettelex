# Nguồn dữ liệu & giấy phép

Mã nguồn VietTelex theo [MIT](../LICENSE). Một số **file dữ liệu** đóng gói trong app có
nguồn và giấy phép riêng, ghi dưới đây.

## vnlm.bin — mô hình n-gram âm tiết (gõ vuốt, thanh gợi ý, Thêm dấu)

`iOS/Keyboard/Resources/vnlm.bin` = `android/app/src/main/assets/vnlm.bin` (định dạng v3 từ
28/09/2026; từ 18/10/2026 thêm nguồn hội thoại: 1.991.768 byte ≈ 1,90 MiB — ngân sách 2 MB; trước
là 1.427.048 byte; 463.463 bigram, 120.073 ngữ cảnh trigram, 398.822 trigram, + 7.184 byte
`uniAdj`); app macOS / Linux / Windows đóng gói cùng file cho Thêm dấu. Sinh bởi `Scripts/gen-syllable-lm.py` (lệnh + định dạng ở docstring; mục "Nén v3" dưới).
Chỉ chứa **số liệu thống kê** (điểm log-xác suất lượng tử theo cặp/bộ ba âm tiết), không chứa
câu hay đoạn văn nào của nguồn.

Dùng bởi: gõ vuốt (trigram, `SwipeTyping` + `SwipeRevise`), thanh gợi ý gõ chạm (bigram PMI —
chọn dấu inline + từ kế tiếp, `SuggestRank`), Thêm dấu cả câu (bigram PMI, `AddTones`; iOS,
Android và process con `VietTelex --add-tones` trên macOS).

### Nguồn

Trọng số = hệ số nhân số đếm; từ 18/10/2026 hai nguồn hội thoại chiếm đúng 25 % / 15 % TỔNG khối
lượng có trọng số, các nguồn cũ chia 60 % còn lại theo tỉ lệ cũ (×0,6) — tổng khối lượng giữ như
trước nên ngưỡng cắt tỉa giữ nghĩa (mục "Nguồn hội thoại" dưới).

| Nguồn | Bản dùng | Giấy phép | Trọng số | Âm tiết đếm |
|---|---|---|---|---|
| [Wikipedia tiếng Việt](https://vi.wikipedia.org) | CirrusSearch dump `viwiki-20251229-cirrussearch-content.json.gz`, 600 MB nén đầu | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | ×0,6 (trước ×1) | 57,5 tr |
| [Wikisource tiếng Việt](https://vi.wikisource.org) | `viwikisource-20251229-cirrussearch-content` | CC BY-SA 4.0 (nhiều tác phẩm là phạm vi công cộng) | ×0,6 | 33,0 tr |
| [Wikibooks](https://vi.wikibooks.org), [Wikivoyage](https://vi.wikivoyage.org), [Wikiquote](https://vi.wikiquote.org) tiếng Việt | `…-20251229-cirrussearch-content` | CC BY-SA 4.0 | ×0,6 / ×0,6 / ×1,2 | 2,6 / 1,3 / 0,6 tr |
| [Tatoeba](https://tatoeba.org) (câu tiếng Việt) | `downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2` (bản xuất 17/10/2026; trước 09/2026) | [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/) | ×18 (trước ×30) | 0,25 tr |
| [OpenSubtitles](http://www.opensubtitles.org/) qua [OPUS OpenSubtitles v2024](https://opus.nlpl.eu/OpenSubtitles/corpus/version/OpenSubtitles) — đơn ngữ tiếng Việt `https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2024/mono/vi.txt.gz` (919 MB nén) | lọc + khử trùng: giữ 35,7 tr / 79,2 tr câu | OPUS không ghi giấy phép cho bộ này; điều kiện của OPUS: ghi liên kết http://www.opensubtitles.org/ và trích Lison & Tiedemann 2016 (LREC). **Phil chấp nhận 18/10/2026** | 25 % khối lượng (×0,0857) | 300,8 tr |
| [FineWeb-2](https://huggingface.co/datasets/HuggingFaceFW/fineweb-2) `vie_Latn` (commit `af9c1333`) — lát cắt trang diễn đàn/hỏi đáp/bình luận (crawl ≥ 2018), đọc thẳng parquet qua HTTP Range, 1.691 row group / 3,65 GB tải luồng, 19.319 tên miền (≤ 3 % mỗi miền) | 2,0 tr câu giữ lại | [ODC-By 1.0](https://opendatacommons.org/licenses/by/1-0/), kèm [Common Crawl Terms of Use](https://commoncrawl.org/terms-of-use). **Phil chấp nhận 18/10/2026** | 15 % khối lượng (×0,387) | 40,0 tr |
| [ViSoLex](https://github.com/HaDung2002/visolex) `dict/dictionary.json` (commit `53c62c72`) | chỉ để CHUẨN HOÁ teencode trước khi đếm (k/ko/khum → không, đc → được…) — không đóng gói | MIT (© 2024 HaDung2002) | — | — |
| [ViLexNorm](https://github.com/ngxtnhi/ViLexNorm) cột `normalized` (dev + test) | chỉ làm TẬP DEV nội bộ (không đếm, không đóng gói, không commit) | CC BY-NC-SA 4.0, chỉ dùng nghiên cứu | — | — |

Dump Wikimedia lấy tại https://dumps.wikimedia.org/other/cirrussearch/20251229/ (trường
`text` đã là văn bản thuần; dump mới từ 09/2026 ở https://dumps.wikimedia.org/other/cirrus_search_index/
— bản 20251229 vẫn còn ở chỗ cũ ngày 18/10/2026). Tatoeba nhỏ nhưng là câu hội thoại, gần văn phong bàn phím
nhất ⇒ trọng số cao (chọn trên tập dev, xem dưới).

### Giấy phép của vnlm.bin

Số đếm n-gram là dữ liệu thống kê, nhưng để an toàn ta **coi vnlm.bin là tác phẩm phái
sinh** của các nguồn trên và phát hành nó theo **CC BY-SA 4.0** (Tatoeba CC BY 2.0 FR cho
phép gộp vào tác phẩm CC BY-SA khi ghi công; FineWeb-2 ODC-By chỉ đòi ghi công). Phần
OpenSubtitles không có giấy phép rõ ràng — Phil đã chấp nhận rủi ro này 18/10/2026; ta tôn trọng
yêu cầu của OPUS (liên kết opensubtitles.org + trích dẫn). Hệ quả:

- Dùng thương mại được (cả CC BY-SA lẫn CC BY đều cho phép).
- ShareAlike chỉ áp lên **file dữ liệu** (và bản sửa của nó), không lên mã nguồn app đọc
  nó — mã vẫn MIT.
- Phải ghi công khi phân phối (app + repo). Ghi công đặt ở: file này, mục "Giới thiệu"
  trong app iOS/Android (dòng "Dữ liệu gõ vuốt…", mở trang này), header fixture kiểm thử.

**Thông báo ghi công** (dùng nguyên văn khi phân phối lại vnlm.bin):

> vnlm.bin chứa số liệu thống kê n-gram âm tiết suy ra từ nội dung Wikipedia,
> Wikisource, Wikibooks, Wikivoyage và Wikiquote tiếng Việt (© các tác giả Wikimedia,
> CC BY-SA 4.0), từ câu tiếng Việt của Tatoeba (© các thành viên Tatoeba, CC BY 2.0 FR), từ
> phụ đề tiếng Việt của OpenSubtitles (http://www.opensubtitles.org/, qua OPUS: P. Lison và
> J. Tiedemann, 2016, "OpenSubtitles2016: Extracting Large Parallel Corpora from Movie and TV
> Subtitles", LREC 2016) và từ một phần FineWeb-2 (© Hugging Face, ODC-By 1.0; nội dung theo
> Điều khoản Common Crawl). Teencode chuẩn hoá bằng từ điển ViSoLex (MIT). Đã biến đổi: lọc
> câu, chuẩn hoá, tách âm tiết, đếm n-gram, làm trơn Kneser-Ney, cắt tỉa, lượng tử hoá, nén.
> vnlm.bin phát hành theo CC BY-SA 4.0.

### Nguồn KHÔNG dùng (và lý do)

- **Báo điện tử (VnExpress, Tuổi Trẻ…), corpus VLSP / corpus tin tức cào web**: bản
  quyền thuộc toà soạn; phần lớn chỉ cho phép dùng nghiên cứu. (FineWeb-2 lọc bỏ tên miền báo.)
- **OSCAR / CC-100**: như Common Crawl dưới, chưa được duyệt riêng.
- **Văn bản LLM sinh, cào web trực tiếp**: không dùng (giai đoạn 1).

Đã từng nằm ở đây, **Phil chấp nhận 18/10/2026** (chuyển lên bảng nguồn):

- ~~OpenSubtitles thô / OPUS OpenSubtitles~~ (lý do cũ: phụ đề thuộc bản quyền phim + người
  dịch; điều khoản opensubtitles.org/OPUS không cấp rõ quyền phân phối số liệu phái sinh cho app
  thương mại) — dùng bản OPUS v2024 đơn ngữ, chỉ số liệu thống kê đi vào app.
- ~~Common Crawl~~ (lý do cũ: bản quyền từng trang không xác định) — dùng qua FineWeb-2 (ODC-By),
  chỉ lát cắt diễn đàn/hỏi đáp, chỉ số liệu thống kê đi vào app.

### Tái tạo

Lệnh đầy đủ ở docstring `Scripts/gen-syllable-lm.py` (tải dump về thư mục tạm → `count` →
`build` → copy sang assets Android; `chains` sinh fixture kiểm thử). Dữ liệu thô **không**
commit. Build từ cùng cache đếm cho ra file y hệt từng byte (đã kiểm 28/09/2026: bản v1 cũ tái
tạo đúng, `count` của script mới = script cũ trên Tatoeba).

- Tách âm tiết: NFC, chữ thường, kiểu dấu cũ như vnlexicon (hòa, thủy); chỉ giữ âm
  tiết có trong vnlexicon; chuỗi đứt ở dấu câu/số/từ lạ.
- Câu có `blake2b(câu) % 20 == 0` là **tập kiểm thử**, `== 1` là **tập dev** — cả hai bị
  loại khỏi phép đếm. Trọng số nguồn/hệ số chấm điểm chỉnh trên tập dev.

### Nguồn hội thoại (18/10/2026, giai đoạn 1)

Mục tiêu: thêm văn nói/chat hiện đại (OpenSubtitles + lát diễn đàn FineWeb-2) trong ngân sách 2 MB,
cùng định dạng v3 (lượng tử 6/4/4) ⇒ reader 5 nền tảng không đổi. **vnlexicon.bin không đổi**.

**Tái tạo nền.** Dump 20251229 còn nguyên ⇒ chạy lại `count` + `build`: 332.432 bigram / 92.285 ngữ
cảnh / 260.186 trigram, 1.427.216 byte — KHÔNG trùng từng byte với bản cũ (1.427.048) chỉ vì bản xuất
Tatoeba đã khác (17/10/2026 thay 09/2026; Tatoeba chỉ giữ bản xuất mới nhất). Số đo trên tập dev
y hệt bản cũ (±0,01). Đường đếm mới (`ids` → `count-np`, numpy) cho file **trùng từng byte** với
`count` cũ trên cùng nguồn — đã kiểm.

**Làm sạch** (`Scripts/lm-chat-prep.py`, chạy trong container; mỗi câu): NFC → (phụ đề: tách rác
"\N" dính chữ: "Nvà", "biếtN") → URL/email/@mention/#hashtag thành chỗ đứt chuỗi → tách câu ở
. ! ? …, xuống dòng, " - " → chữ thường → câu kiểm thử/dev (blake2b % 20 ∈ {0, 1}, như Tatoeba) giữ
lại, không đếm → kéo dài ("điiii" → "đi") → teencode ViSoLex → kiểu dấu cũ → id vnlexicon. Bỏ câu:
< 2 âm tiết Việt; có từ chỉ hợp lệ khi không dấu (khong, duoc); ≥ 5 âm tiết mà < 30 % có dấu (hoặc
≥ 3 âm tiết mà không âm tiết nào có dấu); > 50 % từ không phải âm tiết Việt; số điện thoại / ≥ 2 từ
khoá quảng cáo; một âm tiết lặp ≥ 4 lần liền hay quá ít âm tiết khác nhau; **từ tục/tình dục**
(dưới). Trùng lặp theo câu ĐÃ chuẩn hoá: câu ≥ 5 âm tiết đếm một lần (lọc Bloom 2^32 bit), câu ngắn
tối đa 8 lần mỗi nguồn ("cảm ơn", "được rồi" vẫn giữ tần suất tương đối).

- Teencode ViSoLex (3.091 khoá → giữ 1.382 + 16 khoá chọn tay như khum/thui/nhìu/lun/bít/iu): chỉ
  khoá KHÔNG phải âm tiết vnlexicon, một đáp án duy nhất, đáp án toàn âm tiết vnlexicon, không phải
  chỉ là dạng không dấu (khong → không là gõ không dấu — bộ lọc câu lo), khoá giống đáp án (loại
  nhiễu nsfw → nữa); 280 khoá mơ hồ (t, r, v, mk…) KHÔNG thay (chỉ đứt chuỗi).
- OpenSubtitles: 79,2 tr câu → giữ 35,7 tr (300,8 tr âm tiết); bỏ 12,3 tr trùng dài + 15,2 tr trùng
  ngắn quá trần, 8,3 tr câu < 2 âm tiết, 288 nghìn câu tục, 247 nghìn câu không dấu, 182 nghìn câu
  tiếng Anh.
- FineWeb-2: trang crawl ≥ 2018, bỏ tên miền báo/truyện/cá cược/18+; chọn theo URL diễn đàn (forum,
  threads, hỏi đáp, bình luận, voz/tinhte/webtretho/lamchame/otofun…) hoặc mật độ từ hội thoại ≥ 7 %
  trên trang .vn / slug tiếng Việt. 1,69 tr trang đọc → 65 nghìn trang chọn → 2,0 tr câu (40,0 tr âm
  tiết; 47,6 nghìn câu tục bỏ). Nhiều nhất: webtretho, spiderum, lamchame, blogradio, tinhte, voz…
- **Lỗi gõ sai dấu** (`lm-chat-prep.py detypo`): cặp (a, b) mà một cặp cùng dạng không dấu phổ biến
  hơn ≥ 300 lần trong chính nguồn hội thoại (cặp đó ≥ 500 lần) ⇒ đứt chuỗi giữa a và b (344.610 cặp;
  1,2 tr + 0,26 tr chỗ: cô thế, có thẻ, cô ây, tai sao, có gắng…). Không có bước này "có gắng" lên
  −1,4 nat (Wikipedia: −6,1) và sửa từ vuốt theo từ gõ không lật "có gắng" về "cố gắng"
  (SwipeTypingTests); số đo tập dev không đổi (±0,1).

**Từ tục / tình dục (chính sách).** Với nguồn hội thoại, câu chứa một từ của SensitiveWords.swift
(đcm, đm, vl, lồn, cặc, buồi, đĩ, điếm, đụ, địt, dâm, cứt, fuck…) + chịch, xoạc, nứng, đéo, loz, cmn,
đmm, sex, porn…, hoặc "làm tình", hoặc teencode mà đáp án ViSoLex chứa từ tục (clgt, cmnr…) bị **bỏ
cả câu** ⇒ n-gram chứa chúng chỉ còn từ Wikipedia/Tatoeba như trước (không tăng). Từ cơ thể thường
(vú, dái, cu) không lọc (Phil cần "bóp vú/bóp dái" khi tắt bộ lọc).

**Trộn + cắt tỉa** (`count-np --share`): tổng khối lượng có trọng số giữ bằng của nguồn cũ ⇒ ngưỡng
cắt tỉa giữ nghĩa. Chọn trên tập DEV (suggest-dev.txt Tatoeba; dev hội thoại: ViLexNorm chuẩn hoá —
riêng tư, OpenSubtitles/FineWeb `% 20 == 1`; dev Wikimedia `% 20 == 1` để canh văn viết), đo một lần
trên tập kiểm thử. Ngưỡng cũ 10/20, chỉ OpenSubtitles (cột: dev Tatoeba Thêm dấu âm tiết / từ kế
top-1 / vuốt top-1; ViLexNorm và Wikimedia: Thêm dấu âm tiết):

| phần hội thoại | cỡ | dev Thêm dấu | dev kế top1 | dev vuốt | ViLexNorm | Wikimedia |
|---|---|---|---|---|---|---|
| 0 % (nền) | 1,43 MB | 95,71 | 21,84 | 88,78 | 83,51 | 93,32 |
| 5 % | 1,33 MB | 95,76 | 22,08 | — | 82,78 | — |
| 10 % | 1,31 MB | 95,95 | 22,26 | 89,22 | 83,52 | 92,86 |
| 20 % | 1,29 MB | 96,28 | 22,95 | — | 84,47 | — |
| 30 % | 1,26 MB | 96,42 | 22,96 | 89,48 | 84,86 | 92,72 |
| 50 % | 1,22 MB | 96,47 | 23,33 | 89,44 | 85,40 | 92,51 |

Hội thoại giúp cả dev Tatoeba (câu dịch, văn nói) mà kéo văn viết xuống ⇒ hạ ngưỡng cắt tỉa (5/10)
để dùng ngân sách 2 MB, rồi trộn OpenSubtitles + FineWeb (ngưỡng 5/10):

| opus / FineWeb | cỡ (byte) | dev Thêm dấu | dev kế top1/top3 | dev vuốt | ViLexNorm | FineWeb dev | Wikimedia Thêm dấu / vuốt |
|---|---|---|---|---|---|---|---|
| 30 % / 0 | 1.984.296 | 96,50 | 24,04 / 39,89 | 90,05 | 85,47 | 92,14 | 93,40 / 85,98 |
| 5 % / 5 % | 2.037.272 | 96,13 | 23,05 / 38,62 | 89,61 | 84,10 | 92,38 | 93,38 / 86,65 |
| 10 % / 10 % | 2.027.952 | 96,49 | 23,41 / 39,30 | 89,90 | 84,95 | 93,16 | 93,35 / 86,46 |
| 20 % / 10 % | 1.997.544 | 96,62 | 24,12 / 40,08 | 89,99 | 85,58 | 93,42 | 93,48 / 86,18 |
| 15 % / 15 % | 2.018.920 | 96,70 | 23,78 / 39,77 | 90,10 | 85,68 | 93,62 | 93,37 / 86,16 |
| 25 % / 15 % | 1.984.824 | 96,78 | 24,22 / 39,93 | 90,18 | 86,11 | 93,72 | 93,32 / 85,75 |
| 30 % / 20 % | 1.967.376 | 96,81 | 24,30 / 40,15 | 90,24 | 86,52 | 94,03 | 93,21 / 85,43 |
| **25 % / 15 % + detypo (chọn)** | **1.991.768** | 96,76 | 24,09 / 40,16 | 90,18 | 86,16 | 93,70 | 93,36 / 85,77 |

Chọn 25 % / 15 % (40 % hội thoại): văn viết (Wikimedia) giữ ngang nền; 50 % thêm ~+0,4 điểm hội
thoại nhưng Wikimedia −0,1 (vuốt −0,4). Ngưỡng 5/9 (2,08 MB) vượt ngân sách. suggest-dev không tụt ở
cấu hình nào (+0,4…+2,4 điểm).

**Kết quả** (tập kiểm thử, JVM; iOS cùng số Thêm dấu 0,9727 / câu 0,853; "trước" = main 18/10/2026
đã có CuratedPairs):

| | trước | sau |
|---|---|---|
| Thêm dấu heldout — âm tiết / câu đúng hết | 96,45 / 81,1 % | **97,27 / 85,3 %** |
| Thêm dấu + seed UserLangModel | (không đo lại) | 97,25 % |
| Từ kế tiếp top-1 / top-3 (người dùng mới) | 22,27 / 37,19 % | **24,04 / 40,35 %** |
| Đang gõ slot1 / 3 slot | 85,44 / 94,74 % | **87,11 / 95,69 %** |
| Phím tiết kiệm | 57,15 % | **58,84 %** |
| Học dần: kế tiếp top-1 / top-3 · slot1 · phím | 23,3 / 38,1 · 88,2 · 57,9 % (28/09) | 24,73 / 41,01 · 89,11 · 59,25 % |
| Gõ vuốt heldout top-1 / top-3 | 89,2 / 96,1 % | **90,6 / 96,9 %** |
| — bật vuốt tiếng Anh | 89,1 / 96,0 % | 90,6 / 96,8 % |
| Câu trộn Việt–Anh top-1 / top-3 (n = 270) | 230 / 267 | 218 / 269 |
| Vuốt xen gõ + sửa theo từ gõ | 94,47 % (sửa sai 12) | 94,92 % (sửa sai 9) |
| Vuốt tuần tự + sửa chung cặp | 91,13 % | 92,74 % |
| TypoFix (macOS) P / R | 97,2 / 23,6 % | 97,2 / 23,6 % (không dùng vnlm) |
| Kiểm thử OpenSubtitles: Thêm dấu / kế top-1 / vuốt top-1 | 91,98 / 15,25 / 84,47 | **94,63 / 18,55 / 87,46** |
| Kiểm thử FineWeb: Thêm dấu / kế top-1 / vuốt top-1 | 90,81 / 16,72 / 82,17 | **93,32 / 20,11 / 85,16** |
| Dev ViLexNorm (bình luận MXH): Thêm dấu câu đúng hết | 37,1 % | 44,6 % |
| chat-cases.txt (52 câu; 6 câu Phil) | 43 / 52 | 44 / 52 (6 / 6) |
| **An toàn** — Thêm dấu ra từ tục khi đáp án lành (safety-cases + heldout + dev + 4 tập hội thoại) | 10 | **3** |
| — gõ vuốt ra từ tục | 0 | 0 |

Câu trộn Việt–Anh: thêm lỗi "em gửi → em gì" (5/10 đường) và "tôi nay → tôi này" (câu mẫu gõ nhầm
"tôi nay" thay "tối nay"), bớt "cho sếp → sắp/áp" (3). Độ trễ JVM như cũ (nhiễu máy lớn hơn khác
biệt); iOS simulator Debug Thêm dấu 30 âm tiết: 3,7–22 ms trước / 8,4–12 ms sau qua nhiều lần chạy
(nhiễu lớn; ngưỡng test 10 ms sát). RAM: mmap trang sạch như cũ; app +0,56 MB.

Còn cần Phil quyết (bảng chọn tay KHÔNG sửa trong giai đoạn này):
- Vuốt "ví dụ như thế này" đường sạch ra "vì dù như thế này" — "dù như thế (nào)" là văn nói thật
  (+6,2 nat); `SwipeReviseTests.phraseViDuNhuTheNay` đỏ. Thêm `ví dụ` vào Scripts/curated-pairs.txt
  sửa được (đã thử, rồi bỏ). Cấu hình ≤ 10 % hội thoại thì không đỏ nhưng mất phần lớn mức tăng.
- "co dau" đứng một mình nay ra "có dấu" (trước "cô dâu"); "co dau chu re" vẫn "cô dâu chú rể".
- 22 cặp chọn tay nay vnlm.bin tự giải khi tắt bảng (`LMDataEvalTests.curatedRedundancy`): bóc phốt,
  bóp vú, bản có dấu, chuyển khoản, chốt đơn, chờ xíu, cà khịa, cái nịt, còn hàng, căng đét, gõ tắt,
  khét lẹt, lỗi nha, mã giảm, nhà mình, quá trời, sống ảo, tan làm, thả thính, tăng ca, được chưa,
  ổn mà (+4 cặp vốn tự đúng: chữ/gõ/viết/việt có dấu). Chưa bỏ.

**Tập đánh giá mới.** `iOS/KeyboardTests/Fixtures/chat-cases.txt` (câu Phil + câu chat tự soạn),
`safety-cases.txt` (câu lành có dạng không dấu trùng từ tục: lon, cac, buoi, di, diem, du, dam, cut,
deo, chich, nung, dit), `LMDataEvalTests` (Kotlin: khoá câu Phil + an toàn; `VT_LM_EVAL=1 VT_LM=…
VT_CHAT_SETS=tên=đường-dẫn;…` in mọi số đo cho một vnlm.bin ứng viên). Tập dev/kiểm thử hội thoại
(câu OpenSubtitles/FineWeb giữ lại, ViLexNorm) **không commit** (bản quyền / giấy phép chỉ nghiên
cứu): `lm-chat-prep.py` ghi `*.test.txt` / `*.dev.txt` cạnh luồng id, giữ ngoài repo.

**Tái tạo** (dữ liệu thô ~1,7 GB tạm: dump Wikimedia 0,73 GB + OpenSubtitles 0,92 GB; FineWeb đọc
luồng ~3,7 GB qua mạng, không ghi đĩa; luồng id + cache numpy ~2,5 GB; container
`python:3.12-slim` + `pip install numpy pyarrow`, dùng một lần):

    W=/tmp/lm   # vi.txt.gz (OPUS), dictionary.json (ViSoLex), các dump Wikimedia + Tatoeba ở đây
    python3 Scripts/gen-syllable-lm.py ids --lexicon iOS/Keyboard/Resources/vnlexicon.bin --out-dir $W/ids \
        $W/viwiki-part.json.gz $W/viwiki{books,quote,source,voyage}.json.gz $W/vie_sentences.tsv.bz2
    D="docker run --rm -v $PWD:/repo:ro -v $W:/w IMAGE python -I"
    $D /repo/Scripts/lm-chat-prep.py opus /w/vi.txt.gz --out /w/ids/opus --visolex /w/dictionary.json
    $D /repo/Scripts/lm-chat-prep.py fineweb URL… --out /w/ids/fineweb --visolex /w/dictionary.json \
        --workers 5 --max-rg-per-shard 110 --rg-step 9 --max-syllables 40e6
        # URL… = …/fineweb-2/resolve/main/data/vie_Latn/train/{004,003,002,001}_0000{0..5}.parquet,
        #         xen kẽ theo i rồi nhóm (004_00000, 003_00000, 002_00000, 001_00000, 004_00001, …)
    $D /repo/Scripts/lm-chat-prep.py detypo /w/ids/opus.ids /w/ids/fineweb.ids --ratio-inv 300 --min-max 500
    $D /repo/Scripts/gen-syllable-lm.py count-np --lexicon /repo/iOS/Keyboard/Resources/vnlexicon.bin \
        --cache /w/lm.pkl /w/ids/viwiki.ids /w/ids/viwikibooks.ids /w/ids/viwikiquote.ids \
        /w/ids/viwikisource.ids /w/ids/viwikivoyage.ids /w/ids/tatoeba.ids \
        /w/ids/opus.dt.ids /w/ids/fineweb.dt.ids --share opus=0.25 --share fineweb=0.15
    python3 Scripts/gen-syllable-lm.py build --lexicon iOS/Keyboard/Resources/vnlexicon.bin \
        --cache $W/lm.pkl --th2 5 --th3 10 --out iOS/Keyboard/Resources/vnlm.bin \
        --parity iOS/KeyboardTests/Fixtures/vnlm-parity.txt --chains iOS/KeyboardTests/Fixtures/bigram-heldout.txt

### vnbigram.bin (đã bỏ 28/09/2026)

Trước đây thanh gợi ý + Thêm dấu (và gõ vuốt trước khi có vnlm) đọc một bảng riêng
`vnbigram.bin` (~1,2 MB, 400.807 cặp PMI chiết khấu `ln((c(a,b) − 0.5)·N / (c(a)·c(b)))`,
chỉ PMI ≥ 0.25; `Scripts/gen-syllable-bigram.py`, cùng nguồn/giấy phép). Từ 28/09/2026 mọi nơi
đọc phần bigram của vnlm.bin (PMI = s2 + uniAdj, xem "Mô hình"), bỏ file đó (−1,2 MB mỗi app
iOS/Android) và gộp script vào `gen-syllable-lm.py`. Đo trên tập kiểm thử (bigram-heldout.txt),
tham số chỉnh lại trên tập dev:

| Người dùng | vnbigram.bin | bigram vnlm.bin |
|---|---|---|
| Thêm dấu — âm tiết đúng (câu đúng hết) | 94,63 % (73,2 %) | **95,56 %** (76,9 %) |
| Thêm dấu + seed UserLangModel | 94,71 % | **95,62 %** |
| Thanh gợi ý — slot1 / 3 slot / từ kế tiếp top3 | 82,9 / 93,8 / 27,1 % | 83,0 / 93,9 / 27,0 % |
| Thanh gợi ý, người dùng học dần | 86,1 / 94,8 / 29,1 % | 86,1 / 94,8 / 29,1 % |
| Gõ vuốt (trigram, không đổi) | 89,4 / 96,1 % | 89,4 / 96,1 % |

Thêm dấu tăng vì vnlm có **bằng chứng âm** + lùi Kneser-Ney cho cặp vắng mặt (sàn −2.5 nat;
bảng cũ chỉ có "thiếu cặp = −0.5"). Đổi trên fixture parity `add-tones.txt`: "Hà Nội mùa thu
đẹp lắm" → "mùa thứ" (cặp "thu đẹp" bị cắt tỉa ⇒ lùi rất âm), "mấy giờ rồi bạn" → "bắn"
(PMI "rồi bạn" < 0), "ăn phố" → "ăn phô" (đáp án "phở", cả hai sai). Đã thử: thêm lại cặp bị cắt
tỉa (+0,3–0,9 MB) chỉ +0,05 điểm, không sửa được 2 câu trên; Viterbi trigram −0,6 điểm ⇒ không
giữ.

**18/10/2026 — Thêm dấu dùng trigram (Viterbi bậc 2, `AddTones.viterbi3`).** Bản trigram −0,6 điểm
ở trên chấm cả phần lùi Kneser-Ney (γ3 + s2): chuỗi đi qua ngữ cảnh có dòng trigram "đầy" bị phạt
γ3 < 0 cho mọi tiếp nối vắng mặt. Bản giữ lại chỉ dùng mục trigram TƯỜNG MINH (q, r, s) thay PMI
bigram của chuyển r → s, thiếu thì giữ bigram (tham số cũ, chọn trên tập dev: λ trộn 1, sàn −2.5,
freqW 10; thêm phạt γ3 với hệ số 0,25–1 đều kém hơn). Không thêm dữ liệu, RAM bẩn +≈0 (trang mmap
sạch).

| Thêm dấu (heldout, n = 13 938 âm tiết / 1 911 câu) | âm tiết | câu đúng hết |
|---|---|---|
| chỉ unigram | 76,35 % | 20,9 % |
| + bigram | 95,50 % | 76,7 % |
| + trigram tường minh | **96,45 %** | **81,1 %** |
| (tập dev: bigram → trigram) | 95,01 → 95,71 % | 75,4 → 78,6 % |

Fixture `add-tones.txt`: "tự do", "biển Nha Trang" đúng ra; "năm sáu" (đếm số) → "năm sau".
Câu Phil 18/10/2026 "…gõ tiếng Việt không dấu" vẫn ra "không đâu": vnlm.bin không có mục
(không, dấu) nào — bigram lẫn trigram — nên đây là thiếu dữ liệu, không phải thiếu ngữ cảnh.
(Cùng ngày: cặp chọn tay CuratedPairs sửa; rồi nguồn hội thoại — mục "Nguồn hội thoại" — đưa
(không, dấu) vào mô hình.)

**18/10/2026 — cặp chọn tay (`Scripts/curated-pairs.txt` → `CuratedPairs` Swift/Kotlin/C++,
`Scripts/gen-curated-pairs.py [--check]`).** ~70 cặp/bộ ba chỉ để PHÂN ĐỊNH DẤU ở chỗ vnlm.bin
thiếu/yếu (gõ dấu, thử gõ, [việt] không dấu, bóp vú, lều báo, tiếng lóng Gen-Z…) — không nạp vào
UserLangModel, không phải seed từ kế tiếp. Thêm dấu: chuyển có trong bảng ⇒ số hạng cặp ≥
`curatedW` = 8 nat (6 chưa lật nửa số cặp lóng; 8 ≈ 10), mọi nền tảng; người dùng đã gõ cặp khác
≥ 3 lần ở vị trí đó ⇒ bảng tắt. Vuốt: từ chọn tay sau (prev2, prev) +3.0 trong `Context.word`, và
sửa chung hai từ vuốt (`SwipeRevise.revise`) cộng cùng mức cho cặp. Gợi ý đang gõ dở: từ chọn tay
vào `ctx` của `rankInline`. Heldout Thêm dấu giữ nguyên **96,45 % / 81,1 %** (không câu nào đổi).
Mỗi cặp thử thêm trên câu thường; cặp lật câu thường bị bỏ (từ từ → tự tử, cơ hội → có hơi mệt,
quá đỉnh → qua đỉnh núi…) hoặc chỉ cho vuốt (`~`: sờ cu ↔ số cũ, xịn sò ↔ xin số, cô dâu).

### Mô hình

Kneser-Ney nội suy bậc 3 (D = 0.75), lưu s = ln(P(c | 2 âm tiết trước) / P₁(c)) — có cả
điểm ÂM ("hiếm sau ngữ cảnh này"), điều vnbigram.bin cũ (chỉ PMI dương) không có. Bản 2
(28/09/2026) thêm `uniAdj(c) = ln(P₁(c)·N / c(c))` (1 byte/âm tiết): PMI bigram = s2(b, c) +
uniAdj(c) ≈ ln(P(c|b) / P(c)) — khớp PMI của vnbigram.bin ±0,08 nat trên các cặp chung. Cắt tỉa
"weighted difference" (Seymore & Rosenfeld 1996) trên chính điểm decoder dùng (β·s kẹp
[−1, 1]), ngưỡng bigram 10 / trigram 20 (đếm có trọng số). Decoder: điểm = 0.15·s kẹp
[−1, 1]; khi có trigram, λ tần suất lúc chọn dạng/bung dấu hạ 2.5 → 1.0 (cho cả từ tiếng
Anh, giữ cán cân Việt/Anh).

### Đo (27/09/2026)

Tập kiểm thử: `iOS/KeyboardTests/Fixtures/bigram-heldout.txt` (1.674 câu Tatoeba giữ lại,
12.027 vị trí có âm tiết trước; "top-3" = từ chèn + 2 phương án đầu trên thanh gợi ý), đường giả
σ 0.25, người dùng mới). Tham số chọn trên tập dev (11.915 vị trí), rồi đo MỘT lần trên
tập kiểm thử:

| Mô hình ngữ cảnh | Kích thước | top-1 | top-3 |
|---|---|---|---|
| Không (unigram) | — | 70,4 % | 86,5 % |
| Bigram PMI (vnbigram.bin) | 1,2 MB | 85,6 % | 94,8 % |
| Bigram PMI chỉnh lại λ/trần (dev tốt nhất) | 1,2 MB | ≈ +0,1 điểm trên dev | — |
| Trigram PMI lùi về bigram (không cắt tỉa) | — | 88,1 % | 95,7 % |
| KN bigram (không cắt tỉa) | — | 87,9 % | 96,0 % |
| KN trigram (không cắt tỉa, float) | ~ 31 MB | 90,1 % | 96,5 % |
| KN 4-gram (không cắt tỉa) | — | 90,0 % | 96,5 % |
| **KN trigram cắt tỉa + lượng tử (vnlm.bin)** | **2,6 MB** (v3: 1,43 MB) | **89,2 %** | **96,0 %** |

Bảng trên đo với decoder giai đoạn 2. Sau khi decoder có tầng 2 (σ thích nghi, độ dài,
chấm lại top-16 — commit 7cf48ae): bigram 86,1 % / 95,1 % → **trigram 89,4 % / 96,2 %**
(chỉnh lại β/λ trên dev chỉ +0,1 điểm ⇒ giữ tham số).

4-gram không hơn trigram (dữ liệu hội thoại quá ít). Độ trễ: JVM 0,2 ms/vuốt (decode +
LM), simulator Debug 1,91 vs 1,85 ms/vuốt (bigram) — LM gần như không tốn thêm. Test hồi
quy: `SyllableLMTests` (iOS + Android) — top-1 ≥ 87,7 %, top-3 ≥ 95 %, hơn bigram ≥ 2,5
điểm, bật tiếng Anh không tụt quá 1 điểm, câu trộn Việt–Anh không kém bigram.

### Nén v3 (28/09/2026): 2,65 MB → 1,43 MB

Cùng cache đếm, cùng ngưỡng cắt tỉa; chỉ đổi cách lưu. Chọn trên tập DEV (chuỗi Tatoeba
`hash % 20 == 1`) bằng file v2 "giả lập" (điểm đã lượng tử nhưng lưu định dạng cũ ⇒ đo bằng
reader cũ), rồi đo MỘT lần trên tập kiểm thử:

- **Lượng tử codebook** (k-means 1-D tối ưu bằng quy hoạch động, trọng số √đếm, tâm là số
  nguyên i8 để giải mã ra đúng giá trị i8 — parity dễ kiểm; cắt tỉa chạy lại trên điểm ĐÃ
  lượng tử). Dev: 4 bit cho cả bigram làm hỏng câu mẫu ("cho tôi một ly cà phê" → "cho tới",
  thứ tự từ kế tiếp "điện → thoại, tử, ảnh"); 5 bit bigram / 4 bit trigram qua hết test nhưng
  từ kế tiếp −0,3 điểm; **6 bit bigram + 4 bit trigram + 4 bit γ3** không tụt gì (≤ 0,1 điểm).
  Bigram lưu i8 thô (64 mức) thay mã 6 bit: +83 KB đổi lấy một lần đọc byte ở đường tra
  nóng nhất.
- **Elias–Fano**: bigram EF THEO DÒNG (L_b riêng ⇒ bit 1 ≈ bit 0 ở mọi dòng, select0 theo
  mẫu 64 số 0 luôn quét ~1 từ; EF toàn cục L = 7–8 dày đặc ở dòng lớn "của"/"và" ⇒ quét
  hàng nghìn bit, chậm 2–3×); dòng ≤ 8 mục quét tuần tự. Trigram: EF toàn cục khoá
  k·count + c (dòng trung vị 1 mục ⇒ bỏ được ctxKey/ctxOff 8 byte/ngữ cảnh); ngữ cảnh k =
  rank cờ `hasTri` trên mục bigram (a, b). Delta + varint (phương án 1) lớn hơn EF (bigram
  373 KB vs 268 KB id, trigram 447 KB vs 364 KB) và phải giải mã tuần tự để có chỉ số mục ⇒
  không dùng.
- **Cắt tỉa mạnh hơn** (đường cong đo trên dev, cùng lượng tử 6/4/4): ngưỡng ×1,5 (bigram
  15 / trigram 30) → ~0,99 MB nhưng sửa chung cặp −0,3–0,8 điểm, câu trộn Việt–Anh 230 → 213–221
  /270, hỏng câu mẫu ("mấy giờ rồi bạn", "bị mất ví"); ×2 → ~0,80 MB, tệ hơn; chỉ trigram ×2 →
  ~0,99 MB, sửa chung cặp −0,4. Tiêu chí "relative entropy" kiểu Stolcke (bỏ kẹp của
  decoder) ở cùng cỡ: không hơn (0,82 MB: sửa chung cặp −0,8, trộn 221/270). ⇒ GIỮ ngưỡng
  10/20 — mọi byte bớt thêm đều mất độ chính xác thấy được.

Bố cục + checksum: docstring `Scripts/gen-syllable-lm.py`. Script tự kiểm sau khi sinh (reader
Python cùng thuật toán ≡ dict mô hình) và ghi `iOS/KeyboardTests/Fixtures/vnlm-parity.txt`
(~2.800 truy vấn score/pmi/explicit/size ×16 + checksum duyệt toàn bộ mô hình + hash file);
`SyllableLMTests.parityFixtureAndChecksum` (Kotlin) / `testParityFixtureAndChecksum` (Swift)
khớp từng số. Build hai lần cho file y hệt từng byte.

| Kích thước | v2 | v3 |
|---|---|---|
| vnlm.bin | 2.652.944 B | **1.427.048 B** (−46 %) |
| — id bigram (+chỉ số dòng) / điểm bigram | 693 / 332 KB | 405 / 332 KB |
| — trigram (khoá, offset, γ3, id, điểm) | 1.613 KB | 674 KB |
| RAM bẩn sau map + duyệt cả bảng (iOS test) | 0 KB | 0 KB |

Độ chính xác tập kiểm thử (JVM; iOS cho cùng số trên các tập con của nó):

| Người dùng | v2 | v3 |
|---|---|---|
| Thêm dấu — âm tiết / câu đúng hết | 95,56 % / 76,9 % | 95,50 % / 76,7 % |
| Thêm dấu + seed UserLangModel | 95,65 % | 95,60 % |
| Thanh gợi ý — slot1 / 3 slot / từ kế tiếp top3 | 83,0 / 93,9 / 27,0 % | 83,0 / 93,9 / 27,0 % |
| Thanh gợi ý, người dùng học dần (slot1) | 86,1 % | 86,1 % |
| Gõ vuốt heldout trigram top1 / top3 | 89,4 / 96,1 % | 89,4 / 96,1 % |
| Nét vuốt thật (500 nét) top1 / top3 | 77,2 / 94,8 % | 77,2 / 94,8 % |
| Vuốt tuần tự cả câu + sửa chung cặp | 80,91 → 91,36 % | 80,98 → 91,32 % |
| Vuốt xen gõ + sửa theo từ gõ | 94,42 % | 94,47 % |
| Câu trộn Việt–Anh top1 / top3 (n=270) | 230 / 267 | 230 / 267 |

Độ trễ (ns/truy vấn, min nhiều vòng, cùng 2.665 truy vấn heldout; `SyllableLMTests.lookupLatency`
Kotlin/Swift). "Vị trí" = context + 32 điểm ứng viên (một cú vuốt), "dòng" = bigram + 32 pmi
(Thêm dấu), forEach = cả dòng (từ kế tiếp). v2 → v3:

| | JVM | Swift Release (arm64) | iOS sim Debug |
|---|---|---|---|
| vị trí (context + 32 score) | 1.537 → 1.928 (×1,25) | 999 → 1.292 (×1,3) | 9.420 → 12.631 (×1,34) |
| dòng (bigram + 32 pmi) | 647 → 634 (×1,0) | 384 → 566 (×1,47) | 7.257 → 7.096 (×1,0) |
| forEach dòng | 514 → 767 (×1,49) | 2.000 → 2.506 (×1,25) | 41.281 → 40.518 (×1,0) |
| context + score (lẻ) | 102 → 112 (×1,1) | 50 → 67 (×1,3) | 604 → 786 (×1,3) |
| score / pmi lẻ (mỗi truy vấn một dòng khác) | 25 → 34 (×1,36) | 8 → 17 (×2,1) | 288 → 392 (×1,36) |

Mức consumer: JVM Thêm dấu 30 âm tiết 0,133 → 0,158 ms, bigramNext 9,7 → 11,0 µs, PMI pool
1,5 → 0,7 µs, vuốt heldout 0,062 → 0,064 ms/vuốt; iOS sim PMI pool 8,5 → 8,5 µs, bigramNext
62,7 → 53,6 µs. Tra lẻ trên Swift Release chậm ×2 (+9 ns: select0 + đọc bit thay cho tìm nhị
phân u16) — không consumer nào tra lẻ kiểu đó. Dòng ≤ 8 mục quét tuần tự; `bigram()` O(1) (biRow)
nhanh hơn v2. RAM bẩn sau map + duyệt toàn bảng: 0 KB (iOS `SuggestBigramTests`).

Kích thước bản Release (main 28/09 → nhánh này): iOS .app 8.248 → 7.068 KB (appex 5.820 →
4.640 KB), macOS .app 5.492 → 4.296 KB, Android APK release 6.520.434 → 5.294.538 B (asset
`noCompress`), AAB 7.413.577 → 6.928.781 B (AAB nén asset — dữ liệu EF ít nén hơn mảng thô),
APK debug 16.142.435 → 14.932.923 B.

### Trigram trên thanh gợi ý (28/09/2026, `SuggestTrigramTests`)

Thanh gợi ý gõ chạm dùng thêm phần TRIGRAM của vnlm.bin (định dạng không đổi; API reader thêm
`Context.forEachNext` / `forEachTrigram` / `explicit` / `explicitAll`, Swift ≡ Kotlin):

- **Từ kế tiếp**: có dòng trigram (prev2, prev) trong cùng câu ⇒ top trigram (KN lùi γ3 + s2 cho
  mục chỉ có ở bigram; dòng ≥ 6 mục thì chỉ duyệt dòng trigram — khỏi quét cả dòng bigram của
  "của"/"và"). Ưu tiên người dùng: từ đã gõ ĐÚNG bộ ba này ≥ 2 lượt đứng trước, sau trigram tĩnh
  mới tới nextWords cá nhân/seed. Không có dòng trigram ⇒ như cũ (cá nhân/seed rồi bigram).
- **Đang gõ** (chọn dấu cho âm tiết đang gõ): PMI của mục trigram nếu có, không thì bigram;
  trọng số lưới lại 2.5/8/0.45 → 3/12/0.33 (trần hiệu dụng 3.96 < 4 ⇒ cá nhân vẫn thắng).
- Tập DEV mới `iOS/KeyboardTests/Fixtures/suggest-dev.txt` (chuỗi Tatoeba `hash % 20 == 1`,
  sinh bằng `chains` từ vie_sentences.tsv — tái tạo đúng từng dòng bigram-heldout.txt với
  `% 20 == 0`). Mọi tham số chọn trên dev, đo MỘT lần trên tập kiểm thử.

Tập kiểm thử (JVM, 12.027 vị trí; iOS đo 1/3 chuỗi cho cùng xu hướng: top-1 13,4 → 22,1, top-3
26,3 → 37,0, slot1 82,6 → 85,3, phím tiết kiệm 52,8 → 57,3 %). "Phím tiết kiệm" = ước lượng phím
Telex (chữ + phím dấu/mũ/móc, đ = 2, + dấu cách) bớt được khi chạm chip (từ kế tiếp = 1 chạm,
ứng viên sau tiền tố k chữ = k + 1):

| | trước (bigram) | sau (trigram) |
|---|---|---|
| Từ kế tiếp top-1 / top-3, người dùng mới | 13,3 / 27,0 % | **22,3 / 37,2 %** |
| Đang gõ slot1 / 3 slot, người dùng mới | 83,0 / 93,9 % | **85,4 / 94,7 %** |
| Phím tiết kiệm, người dùng mới | 52,7 % | **57,2 %** |
| Học dần: từ kế tiếp top-1 / top-3 | 15,7 / 29,0 % | **23,3 / 38,1 %** |
| Học dần: slot1 / 3 slot / phím tiết kiệm | 86,1 / 94,8 / 54,1 % | **88,2 / 95,5 / 57,9 %** |

Trên dev (cùng thứ tự): trigram cho từ kế tiếp +4,5 / +6,4 điểm khi vẫn để cá nhân/seed đứng trước;
đưa trigram lên trước seed thêm +4,1 / +3,5 (người dùng học dần cũng tăng: top-1 17,2 → 23,1 %);
PMI trigram cho âm tiết đang gõ +1,0 slot1, lưới lại trọng số thêm +1,5. Cộng γ3 vào mục chỉ có ở
bigram khi chấm âm tiết đang gõ: kém hơn (−0,6) ⇒ không. Ngưỡng bộ ba đã học 1/2/3 lượt: ngang
nhau (±0,3) ⇒ 2.

**Không làm — cụm nhiều âm tiết trong một ô** ("Việt" → "Việt Nam", nối âm tiết kế khi điểm
trigram và lề với hạng 2 đủ lớn; chạm = chèn cả cụm): tốt nhất +0,07 điểm phím tiết kiệm (57,29 →
57,36 %, 52/884 lần hiện là trúng) đổi lấy −0,6 điểm từ kế tiếp top-1; ngưỡng lỏng hơn thì tụt tới
−1,7 điểm phím. Ô đơn bị thay mất nhiều hơn cụm đem lại.

**Thêm dấu** không đổi (Viterbi trigram đã thử trước đây: −0,6 điểm).

Độ trễ (min nhiều vòng xen kẽ trước/sau, 10.116 vị trí heldout có 2 âm tiết trước): JVM top từ
kế tiếp 3,3 → 2,6 µs, PMI pool 0,56 → 0,91 µs; **cả lượt** gợi ý như bàn phím — đang gõ (pool +
PMI + xếp) 3,24 → 3,66 µs (×1,13), sau dấu cách (nextWords + lấp + đệm) 2,85 → 3,26 µs (×1,14).
iOS sim Debug: top từ kế tiếp 69 → 40 µs, PMI pool 8,8 → 15,5 µs; cả lượt đang gõ 58,6 → 63,6 µs
(×1,08), sau dấu cách 52,4 → 47,0 µs (×0,90). Đọc tại chỗ, không bảng/cache mới: RAM bẩn 0.

### Sửa lại từ vuốt trước — ngữ cảnh hai phía (27/09/2026, `SwipeRevise`)

Cú vuốt w2 chấm lại ứng viên của từ vuốt liền trước w1 (≤ 8 âm tiết: 3 dạng × 4 dấu) bằng
điểm cũ + 0.1·s(w2 | w0, c) kẹp [−1, 1]; thắng ≥ 0.1 ⇒ thay w1 (đuôi màn hình phải khớp),
rồi chọn lại w2 theo ngữ cảnh trái mới. Chip "↩︎ từ cũ" hoàn tác. Chọn trọng số/lề trên dev
(`SwipeReviseTests.sweep`: 0.1/0.1 ít sửa sai nhất ở gần mức tăng tối đa — 214 sửa đúng /
12 sửa sai), đo MỘT lần trên tập kiểm thử (1/3 chuỗi heldout, vuốt TUẦN TỰ — ngữ cảnh trái
là từ đã giải mã, không phải đáp án, nên thấp hơn bảng trên): JVM 80,9 % → **85,5 %**
(+4,6 điểm, 204 sửa đúng / 12 sửa sai); iOS qua EngineBridge thật 78,0 % → **83,0 %** (+5,0).
Chi phí: vài lần bung dấu + tra LM sau nhấc tay (JVM không đo được khác biệt, ~0,1 ms/vuốt).

**Từ kế gõ bằng phím.** Từ vuốt Việt còn nguyên được dấu cách (iOS: cả phím chữ — dấu cách
treo) chốt ⇒ chờ; ranh giới (dấu cách/dấu câu/xuống dòng) chốt từ gõ NGAY SAU thì chấm lại
từ vuốt với ngữ cảnh phải = từ gõ đã chốt (chắc chắn). Chỉ thay khi đuôi màn hình đúng
"từ vuốt ␠ từ gõ ranh giới" (không dính chữ phía trước), học lại cả hai từ, chip "↩︎ từ cũ"
tới phím kế. Hằng số riêng chỉnh trên dev (`SwipeReviseTests.sweepTyped`, vuốt/gõ xen kẽ):
0.15/0.3 — gần mức tăng tối đa (+8,5 so với đỉnh +8,9 ở 0.15/0.2) mà sửa sai chỉ 7 so với 13;
0.1/0.1 của ca vuốt cho +8,4 / 11 sửa sai. Tập kiểm thử (từ vuốt có từ gõ ngay sau, n = 3 994):
JVM 85,7 % → **94,2 %** (+8,4 điểm, 341 sửa đúng / 15 sửa sai = 3,9 % số lần sửa, 0,38 % số
từ); iOS 85,3 % → **93,4 %** (+8,1; 328 / 15).

### Nét vuốt thật — Luyện vuốt

App (Cài đặt → Gõ vuốt → Luyện vuốt) thu nét vuốt thật trên bàn phím mẫu cùng hình học,
chỉ khi người dùng bật lưu; kho nằm trên máy (không sao lưu, không gửi mạng), xuất JSON
(`viettelex-swipe-traces` v1, xem `SwipePractice.kt`). Đánh giá decoder trên file xuất:
`Scripts/eval-swipe-traces.sh file.json` (top-1/top-3 hiện tại, lúc ghi, tách Việt/Anh).

#### Phân tích 45 nét thật đầu tiên (iPhone, Luyện vuốt, 28/09/2026) — nhịp, lố, sửa chung cặp

Nét thật (SwiftUI 60 Hz, lọc 1/5 phím) khác hẳn đường giả cũ (`SwipeSim.path`: tốc độ đều
~21 phím/s, đầu/cuối đúng tâm):

| đo | nét thật | `SwipeSim.path` (cũ) | `SwipeSim.natural` (mới) |
|---|---|---|---|
| lấy mẫu | 16,6 ms, có khoảng 60–180 ms (dừng) | 16,7 ms đều | 16,7 ms + dừng |
| tốc độ (phím/s) p10/p50/p90 | 4 / 17 / 32 | ≈ 21 cố định | 4 / 20 / 34 |
| tốc độ tại phím định đi (giữa) / phím lướt qua, ÷ trung bình | 0,78 / 1,97 | ≈ 1 / ≈ 1 | 0,93 / 1,97 |
| thời gian trong bán kính 0,5 phím: phím định đi / lướt qua | 116 / 33 ms | — | 117 / 33 ms |
| giữ ngón trước khi đi (dt điểm 2) | 83 ms | 17 ms | 83 ms |
| lệch điểm đầu (theo hướng nét, + = về phím kế) | −0,16 ± 0,25 | 0 | −0,14 ± 0,25 |
| **lố điểm cuối** theo hướng nét cuối, p10/p50/p90 | **−0,09 / +0,45 / +1,14** | 0 | −0,25 / +0,43 / +0,92 |
| khoảng cách tâm phím giữa ↔ đường (trung vị) | 0,20 | ~0,2 | 0,17 |

Tức là: người thật CHẬM ở phím định đi, lướt nhanh gấp đôi qua phím nằm giữa đường, và TRÔI
chậm quá phím cuối trước khi nhấc tay (đấy → đâu, lấy → lâu, thay → thai). `SwipeSim.natural`
(SwipeDecoderTests, Kotlin + Swift) mô phỏng các đặc điểm trên; đường cũ giữ cho ngưỡng hồi quy.

Decoder (cả hai nền tảng, cùng hằng số; chỉ khi có thời gian điểm — đường không thời gian chấm y
hệt cũ, fixture `swipe-paths.txt` không đổi; parity nhịp: `swipe-paths-timed.txt`):
- **miễn lố cuối** (`overshoot` 1 phím): thành phần lệch THEO hướng nét cuối của template được
  miễn ở ~15 % cuối đường, chỉ khi đuôi nét chậm (tốc độ tương đối đuôi ≤ 0,5 đủ, ≥ 0,8 tắt);
- **phím lướt qua** (`speedWeight` 0,3, `speedRef` 1,3): mỗi phím giữa của ứng viên mà điểm đường
  gần nó nhất có tốc độ tương đối r > 1,3 bị trừ 0,3·(r − 1,3) (cũng → chung, vì → vui);
- **điểm dừng** (`dwellWeight` 3, r < 0,35, không sát 2 đầu) phải gần một phím của ứng viên.
- Đã thử, KHÔNG giữ: tiền nghiệm dạng không dấu = tổng mọi dấu (hiện là âm tiết mạnh nhất —
  vi = vì): +2 nét thật nửa dev nhưng −0,8…−1 điểm đường giả; miễn "hụt" ở điểm đầu (hội/gọi):
  ±0; ưu tiên Việt mạnh hơn sau từ Việt (bias −1,2…−1,5): +0,1 điểm Việt nhưng −1,5…−5 điểm từ
  Anh chen sau từ Việt — "như the" → "thế" đã đúng nhờ LM (test `phraseViDuNhuTheNay`).

**Sửa chung cặp** (`SwipeRevise.revise(…, next: [SwipeWord])`, iOS `SwipeTyping.finish` + Android
`KeyboardSession.resolveSwipe`): từ vuốt trước được chọn CÙNG ứng viên tốt nhất của cú vuốt này
theo nó (trigram · 0,15 = trọng số LM trái, lề 0,1), ứng viên rộng hơn (từ trước 3 dạng × 8 dấu
≤ 12, từ này ≤ 16). Báo lỗi "ví dụ như thế này" → trước: "vì dù như thế này" cả với đường sạch
(ví không nằm trong 4 dấu đầu của "vi", dụ kém sau "vì").

Chọn hằng số trên: nửa A nét thật (chỉ số chẵn) + đường giả dev (từ rời seed 1, câu giữ lại
%12==0 / chuỗi dev của SwipeRevise); báo trên nửa B + tập kiểm thử (`SwipeTuneTests`, layout
iPhone 36,8 pt). Trước = decoder cũ + sửa theo top-1 từ kế:

| tập | trước | sau |
|---|---|---|
| nét thật nửa A (dev, 23) top-1 | 15 | 18 |
| **nét thật nửa B (22, không dùng chỉnh)** top-1 | 15 | **18** |
| nét thật cả 45: top-1 / top-3 | 0,667 / 0,933 | **0,800** / 0,911 |
| — tiếng Việt / tiếng Anh top-1 | 0,606 / 0,833 | 0,788 / 0,833 |
| từ rời test, đường tự nhiên top-1 / top-3 | 0,788 / 0,945 | **0,873** / 0,978 |
| từ rời test, đường đều | 0,908 / 0,995 | 0,905 / 0,998 |
| câu giữ lại test (LM, bật EN), tự nhiên top-1 / top-3 | 0,835 / 0,908 | **0,882** / 0,944 |
| câu giữ lại test, đường đều | 0,915 / 0,964 | 0,914 / 0,964 |
| vuốt tuần tự cả câu (SwipeRevise test, n = 4 631), đường đều | 0,858 | **0,914** |
| — đường tự nhiên | 0,758 | **0,893** |
| — đường tự nhiên, bật vuốt tiếng Anh | 0,742 | **0,889** |
| "ví dụ như thế này" ×30 đường tự nhiên (JVM layout 40) | 0,527 | **0,740** |

Còn sai trên nét thật: thay→thai, đấy→đâu (1/4), hội→gọi ×2, trai→tai, have→gave, chỉ→cu (nét
trôi lên u), away/cũng nét vòng. Độ trễ decode (cùng đường tự nhiên, bật vs tắt nhịp): JVM +10 %,
iOS Debug simulator +5 %; sửa chung cặp thêm ≤ 12 × 16 lần tra LM sau nhấc tay (~0,01 ms JVM).
Chạy lại: `SWIPE_TUNE=1 SWIPE_TRACES=… SWIPE_CFGS='legacy;base' ./gradlew --offline
:keyboard:test --tests '*SwipeTuneTests*' -i | grep TUNE` (xem đầu SwipeTuneTests.kt).

#### 500 nét thật (iPhone, Luyện vuốt, 28/09/2026) — chữ h của phụ âm ghép

Kho 500 nét (415 Việt / 85 Anh, 257 từ mục tiêu, gồm cả 45 nét trên). Luyện vuốt lặp một từ tới
khi đúng ⇒ kho **nghiêng về từ khó** (chưa 16 lần, chọn 13, chúa 12…) và các lần thử cùng từ tương
quan. Tách TẤT ĐỊNH 70/30 (`SwipeTuneTests.split`): phân tầng theo dạng mục tiêu, trong nhóm xếp
theo băm chỉ số, lần thứ k vào tập giữ lại khi (3k + băm(từ)) mod 10 < 3 ⇒ chỉnh 341 / giữ lại 159.
Chỉ chỉnh trên 341 nét + đường giả dev; báo trên 159 nét + tập kiểm thử giả + câu giữ lại.

Phân tích lỗi lớn nhất (chua→cua ×19, chon→con ×9, cho→co ×7 trên tập chỉnh):
- h của ch/nh… bị lướt **nhanh như phím thường** (tốc độ tương đối tại h: chọn ≈ 2,1, chưa ≈ 1,5,
  phím lướt qua ≈ 2) — miễn phạt lướt qua cho chữ thứ hai của phụ âm ghép, hay lấy tốc độ nhỏ nhất
  quanh phím ("chậm nhẹ"), **không** cứu được: tắt hẳn phạt nhịp thì "cua" vẫn thắng (tiền nghiệm
  của 234 > chưa 204, hình học gần hoà) mà cũng → chung tăng. Đã thử, không giữ.
- Thứ phân biệt được là đường **UỐN về h**: uốn = khoảng cách h tới dây cung c→u − khoảng cách h
  tới đường. chưa: trung vị +0,22 (n = 28); của: −0,20 / −0,12; cũng: ≈ 0 (7/10 ≤ 0,12). Với
  chọn/con, có/cho (h gần như nằm trên dây cung c→o, 0,14 phím) và trên/tên, trả/ta (r thẳng hàng)
  hình học KHÔNG phân biệt được — chọn/con từ rời là do tiền nghiệm, cần ngữ cảnh.
- Decoder (cả hai nền tảng, cùng hằng số, không cần thời gian điểm): `bendWeight` 3 — hai ứng viên
  trong pool khác nhau đúng một h giữa sau c/n/t/p/k/g (Anh t/s/c/w/p/g), dây cung cách h
  0,3–1 phím ⇒ ứng viên có h += 3·kẹp(uốn − 0,05, ±0,3), rồi kẹp trong điểm của cặp ± 0,01 (chỉ đổi
  chỗ TRONG cặp). Mở rộng cho r/g/i (tr, ng, gi) làm hỏng từ rời giả (ta → tra, nang → ngang) — bỏ.

Trước = main sau commit nhịp (fe1dae6); số tập giữ lại in đậm:

| tập | trước | sau |
|---|---|---|
| nét thật chỉnh (341) top-1 / top-3 | 0,730 / 0,953 | 0,768 / 0,953 |
| **nét thật giữ lại (159) top-1 / top-3** | 0,774 / 0,937 | **0,780** / 0,937 |
| — giữ lại: Việt / Anh | 0,756 / 0,857 | 0,763 / 0,857 |
| — giữ lại: đúng cả DẤU (dạng + dấu mạnh nhất = mục tiêu) | 0,616 | 0,616 |
| cả 500: top-1 | 0,744 | 0,772 |
| từ rời giả test: tự nhiên / đều top-1 | 0,873 / 0,905 | 0,875 / 0,903 |
| câu giữ lại test (LM, bật EN): tự nhiên / đều top-1 | 0,882 / 0,914 | 0,882 / 0,913 |
| vuốt tuần tự cả câu test (n = 4 631): tự nhiên / đều | 0,8933 / 0,9136 | 0,8927 / 0,9125 |
| — cùng, tập chỉnh (n = 2 389) | 0,8966 / 0,9326 | 0,8974 / 0,9334 |
| từ Anh sau từ Việt top-1 (tự nhiên / đều) | 0,886 / 0,864 | 0,886 / 0,864 |

Tuần tự cả câu test −3/−5 từ trên 4 631 (đều: của → chúa ×4 — đường giả nhiễu uốn ngẫu nhiên về h);
tập chỉnh +2. Độ trễ decode (đường tự nhiên, bật vs tắt uốn): JVM +5 %, iOS Debug simulator +4 %.

**Dấu (Luyện vuốt hiện từ CÓ dấu, chấm theo dạng không dấu):** 16 % nét giữ lại đúng dạng nhưng
sai dấu (đấy → đây, nhỏ → nhớ, cầu → cậu, máy → mày…) — không phải lỗi decoder: `expand` đã xếp
dấu theo tần suất của CHÍNH âm tiết có dấu; từ rời không có ngữ cảnh thì dấu mạnh nhất luôn thắng
(mày 203 > máy 183 là thiên lệch phụ đề của OpenSubtitles). Các "lỗi" dạng chi→chi, cam→cam trong
danh sách lỗi là lỗi dấu này, không phải decoder.

Còn sai trên tập giữ lại: chưa → của ×4 (nét thẳng), chọn → con ×4, cho → có ×2, trả → ta ×2
(thẳng hàng — chỉ ngữ cảnh gỡ được), chú → chỉ ×2, trượt vài từ Anh (qua→wits, own→owen, good→fog/
golf, felt→left). Có ngữ cảnh (vuốt tuần tự): chưa cuối câu hỏi ("…đài loan chưa") và "không cho"
→ "không có" vẫn thua LM — việc của trọng số LM, chưa đụng.

### Liên tục ngôn ngữ — đang gõ tiếng Anh thì từ kế là tiếng Anh (28/09/2026, `SwipeLangContext.prior(kinds)`)

Ngữ cảnh = ngôn ngữ ≤ 3 từ trước con trỏ (từ đang soạn + vòng 3 từ đã chốt, gõ hay vuốt; **không
xoá ở dấu câu** — câu sau của đoạn tiếng Anh vẫn là tiếng Anh; xoá khi đổi ô / chữ trước con trỏ đổi
từ ngoài; chỉ ghi khi bật vuốt + vuốt tiếng Anh). Mỗi từ: `classify` (nhãn "vừa vuốt ra tiếng Anh" >
dấu tiếng Việt > từ mượn trung tính > EnglishContextWords > từ điển Việt/Anh; trùng cả hai = trung
tính). Mạch Anh s = Σ 0,6^i trên từ Anh, đi từ gần ra xa, dừng ở từ Việt đầu tiên: s ≥ 1 ⇒ bias
0,2 + 0,5·(min(s, 2) − 1) (một / hai / ba từ Anh: 0,2 / 0,5 / 0,68), margin 0; 0 < s < 1 (từ Anh
cách từ trung tính) nội suy từ DEFAULT. Không có từ nào rõ ngôn ngữ, hoặc mạch Việt ⇒ đúng DEFAULT
(−0,9 / 0,3) ⇒ từ rời không đổi. Chế độ Tiếng Anh (vuốt phím cách) vẫn `onlyEnglishPrior`.

**Mạch Việt không cộng thêm**: DEFAULT đã nghiêng Việt; quét viMargin/viBias 0,1…0,8 (dev) chỉ +0,1
điểm câu Việt (lỗi ngôn ngữ trong câu Việt chỉ còn 5/1 160 từ) mà −1,4…−7 điểm từ Anh chen sau từ
Việt ⇒ 0 (khớp lần thử trước với bias −1,2…−1,5). Chỉnh trên dev; decay 0,4/0,8, enGain 0,3…1,2,
enBias 0…0,4: cao hơn thì câu Anh +0,3 mà từ Việt sau từ Anh −2…−5.

Tập (`Fixtures/swipe-lang-sentences.txt`, `Scripts/gen-swipe-lang-eval.py`): 1 200 câu tiếng Anh
Tatoeba 3–8 từ (chỉ a–z trong enlexicon, không tên riêng; [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/),
© các thành viên Tatoeba, `downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2`
09/2026) + 573 câu trộn (93 câu tự soạn kiểu chat/công sở, câu Việt giữ lại ghép câu Anh hai chiều,
câu Việt chèn một từ Anh hay chen); câu Việt = bigram-heldout. Tách dev/test cố định; đoạn văn = 3
câu liền cùng tập (câu 2–3 chỉ có ngữ cảnh NGÔN NGỮ của câu trước, LM thì mất như thật). Vuốt tuần tự
như bàn phím (`SwipeLangTuneTests`, ngữ cảnh = từ đã giải mã, sửa từ trước, bật vuốt tiếng Anh,
layout iPhone), tập kiểm thử, top-1 đường tự nhiên / đều:

| tập (test) | trước | sau |
|---|---|---|
| câu Việt thuần (n = 1 184) | 84,2 / 87,4 | 84,1 / 87,3 |
| **câu Anh thuần** (n = 3 160) | 86,3 / 89,0 | **91,8 / 94,4** |
| — từ đầu câu 2–3 của đoạn Anh (n = 311) | 61,8 / 63,5 | **95,2 / 99,0** |
| — từ Anh sau từ Anh trong câu | 90,6 / 93,4 | 93,0 / 95,6 |
| câu trộn, cả câu (n = 2 164) | 82,6 / 86,7 | 83,5 / 87,2 |
| — từ Anh ngay sau từ Việt | 77,8 / 81,8 | 78,3 / 81,8 |
| — từ Việt ngay sau từ Anh | 71,0 / 73,1 | 70,4 / 71,0 |
| — từ Anh sau từ Anh | 90,5 / 93,7 | 92,4 / 95,2 |
| từ rời: nét thật giữ lại / giả tự nhiên / giả đều | 0,780 / 0,875 / 0,903 | y hệt |

Giá phải trả: từ Việt đầu tiên sau một mạch Anh dài (−0,6 / −2,1 điểm; "…the house bạn" → "ban").
Lỗi còn lại trong câu Anh phần lớn là Anh↔Anh (our→or, too→to, in→on — cần LM tiếng Anh), lỗi
ngôn ngữ trong câu Anh giảm 135 → 75 (dev). Chi phí: ≤ 3 lần `classify` (tra nhị phân) mỗi cú vuốt,
một phép thêm vào mảng 3 phần tử mỗi từ chốt khi bật vuốt; tắt vuốt = 0.
Chạy lại: `SWIPE_LANG_TUNE=1 SWIPE_LANG_CFGS='old;base' [SWIPE_TEST=1] ./gradlew --offline
:keyboard:test --tests '*SwipeLangTuneTests*' --rerun -i | grep LANG`.

## CommonSyllables.swift — âm tiết thường gặp (engine, 30/10/2026)

`TelexCore/Sources/TelexCore/CommonSyllables.swift` (port: `EnglishWordLists.kt`,
`windows/engine/src/generated_tables.hpp`) = danh sách khoá Telex của 3.788 âm tiết có dấu có
tần suất `vnlexicon.bin` ≥ 100 (≤ 3 chữ cái) hoặc ≥ 20 (dài hơn). Chỉ là ngưỡng trên số tần suất
của vnlexicon.bin — không thêm nguồn mới, cùng giấy phép/ghi công với vnlexicon.bin. Sinh bằng
`python3 Scripts/gen-common-syllables.py`. Dùng cho luật viết tắt toàn chữ HOA và luật giữ từ
gõ sai một chữ.

## enlexicon.bin — từ điển tiếng Anh cho gõ vuốt (giai đoạn 3)

- File: `iOS/Keyboard/Resources/enlexicon.bin`, `android/app/src/main/assets/enlexicon.bin`
  (y hệt nhau, ~180 KB, 20.000 từ chữ thường a–z + tần suất 1 byte).
- Sinh bởi: `Scripts/gen-enlexicon.py` (python3 stdlib).
  ```
  python3 Scripts/gen-enlexicon.py --download <thư_mục_tạm>
  python3 Scripts/gen-enlexicon.py <thư_mục_tạm>
  ```
- Dùng cho: gõ vuốt giai đoạn 3 (vuốt ra từ tiếng Anh xen trong câu Việt), công tắc
  "Vuốt từ tiếng Anh".
- Dùng thêm (18/10/2026) làm NGUỒN SINH bảng `TelexCore/Sources/TelexCore/EnglishFreezePrefixes.swift`
  (eager English restore: "goog" thay vì "gôg" giữa từ) — `swift run -c release gen-freeze-prefixes
  ../iOS/Keyboard/Resources/enlexicon.bin Sources/TelexCore/EnglishFreezePrefixes.swift` (từ TelexCore/),
  rồi `android/telexcore/scripts/gen-wordlists.py` + `windows/engine/tools/gen_tables.py`. Engine không
  nạp enlexicon.bin lúc chạy: bảng ~1.000 tiền tố (~6 KB, hằng số trong binary).
- 18/10/2026: `SUPPLEMENT` trong script (từ công nghệ / AI / tài chính / y tế + viettelex, telex: kubernetes,
  stablecoin, paracetamol…) — như từ mượn của repo, nằm NGOÀI 20.000 ⇒ bảng chỉ thêm (20.051 từ). Sinh lại cũng
  kéo theo "ll"/"ve" (đuôi rút gọn đã có trong EnglishContextWords từ trước, bảng cũ chưa sinh lại) và bỏ
  "landlords" (đuôi lấp Wikipedia). Từ nhạy cảm chỉ đọc khối `set` của SensitiveWords.swift.

### Nguồn

1. **Google Books Ngram Corpus** (phiên bản 20200217, sách xuất bản 2010–2019), qua danh
   sách đã làm sạch của dự án **google-books-ngram-frequency** (orgtre):
   `ngrams/1grams_english.csv` và `ngrams/1grams_english-fiction.csv`, mỗi file 10.000 từ
   phổ biến nhất kèm số lần xuất hiện. Ghim commit
   `6a72a4d96a2c36717479e9e9bf4e24260b3dbdae`.
   - Giấy phép: **Creative Commons Attribution 3.0 Unported (CC BY 3.0)** — cả bộ dữ liệu
     Google Books Ngram lẫn nội dung repo orgtre. Cho phép dùng thương mại, sửa đổi, phân
     phối lại; điều kiện: ghi công.
   - Ghi công: *"Google Books Ngram Viewer data, © Google, CC BY 3.0
     (https://books.google.com/ngrams); cleaned lists by orgtre/google-books-ngram-frequency
     (https://github.com/orgtre/google-books-ngram-frequency), CC BY 3.0."*
   - Chúng tôi đã sửa đổi: lọc, gộp hai danh sách, quy tần suất về thang 1 byte.
2. **wikipedia-word-frequency** (Ilya Semenov): `results/enwiki-2023-04-13.txt` — tần suất từ
   trong Wikipedia tiếng Anh. Chỉ dùng để BỔ SUNG từ phổ biến không có trong danh sách sách
   (google, facebook, website…) và lấy tần suất cho nguồn 3. Ghim commit
   `798ea9062d6e5aed1fa87deeeda1cd99d5b37903`.
   - Giấy phép: **MIT** (Copyright (c) 2015 Ilya Semenov) —
     https://github.com/IlyaSemenov/wikipedia-word-frequency. Chỉ dùng số đếm (dữ kiện
     thống kê), không chứa văn bản Wikipedia.
3. **Dữ liệu của chính repo**: các bảng `neutralLoanwords` / `words` / `restoreOnly` trong
   `TelexCore/Sources/TelexCore/EnglishContextWords.swift` (từ mượn/tên app hay chen trong
   câu Việt: wifi, login, zalo, shopee…) — luôn có mặt trong từ điển.

### Lọc & chuẩn hoá

- Chỉ giữ `^[a-z]{2,}$`; bỏ từ tục/xúc phạm/tình dục thô (danh sách trong script + các từ
  ASCII của `iOS/Keyboard/SensitiveWords.swift`).
- Phần bổ sung từ Wikipedia: ≥ 3 chữ, không trùng dạng không dấu của âm tiết Việt (loại
  tên riêng tiếng Việt như tran, nguyen), không phải số La Mã; lấy theo hạng tới khi đủ
  20.000 từ tổng.
- Tần suất: tỉ lệ token quy về cùng thang với `vnlexicon.bin` (255·ln(count)/ln(max) trên
  corpus OpenSubtitles tiếng Việt ~26,4 triệu token) để decoder so hai từ điển trên một thang. (Số đó là
  của hermitdave 2018; vnlexicon thật dùng bản 2016 — chênh ~5 byte, GIỮ vì ngưỡng đã chỉnh trên thang
  này, xem mục vnlexicon.)

## FUTO Swipe

**futoswipe.bin — encoder FUTO Swipe cho gõ vuốt (THỬ NGHIỆM, mặc định tắt).**

`iOS/Keyboard/Resources/futoswipe.bin` = `android/app/src/main/assets/futoswipe.bin` (1,27 MB,
sha256 `59e41b22…3f089`), kèm `futoswipe-LICENSE.md` (thông báo sửa đổi + nguyên văn giấy phép)
ở cùng thư mục — cả hai được đóng gói vào app. Chỉ đọc khi bật công tắc **Thử nghiệm → Gõ vuốt →
Mô hình neural gõ vuốt** (Keys.SWIPE_FUTO / KeyboardSettings.swipeFuto, mặc định TẮT).
**Powered by FUTO Swipe.**

### Nguồn

| Thành phần | Bản dùng | Giấy phép | Dùng thế nào |
|---|---|---|---|
| [futo-org/futo-swipe](https://huggingface.co/futo-org/futo-swipe) `honorable_sturgeon/model_fp32.pte` (encoder TCN 635K tham số; bài [arXiv 2606.25247](https://arxiv.org/abs/2606.25247)) | revision `18328c30…` (26/06/2026), sha256 `725242ba…1fbaf` | **FUTO Model Weights License 1.0** | weights → fp16 (Derivative Model đã sửa) |
| Decoder `magic_macaw`, context LM `hungry_jellyfish` (cùng repo) | — | cùng giấy phép | KHÔNG dùng (chỉ tiếng Anh/QWERTY) |
| [swipe-library](https://gitlab.futo.org/keyboard/swipe-library) (runtime C++/Kotlin của FUTO) | — | **GPL-3.0** | KHÔNG dùng, không chép code — repo MIT |
| Schema flatbuffer ExecuTorch/XNNPACK (`program.fbs`, `runtime_schema.fbs`) | v1.2.0 | BSD-3-Clause | chỉ để đọc định dạng `.pte` trong Scripts/futo-swipe (không kèm file schema) |

### Giấy phép — kết luận (đọc LICENSE.md 27/09/2026)

Dùng trong app thương mại, đóng gói và phân phối lại (kể cả trong repo công khai) **ĐƯỢC PHÉP**,
với điều kiện:

- Quyền: *"non-exclusive, royalty-free, worldwide, non-sublicensable, non-transferable license to
  use, copy, distribute, make available, and prepare Derivative Models of the Weights for any
  purpose"* ⇒ được commit `futoswipe.bin` vào repo và đóng gói vào app; KHÔNG được cấp lại
  (sublicense) ⇒ giấy phép MIT của VietTelex **không** áp lên file này (ghi rõ trong
  `futoswipe-LICENSE.md`); người nhận nhận quyền trực tiếp từ FUTO theo bản giấy phép kèm theo.
- Ghi công bắt buộc: *"You may use the Weights or any Derivative Model for any purpose, including in
  commercial products and services, provided that you display a visible notice to end users stating
  that the product is powered by "FUTO Swipe" technology … such as within the product's settings,
  about screen … Failure to include this notice is a material breach"* ⇒ dòng "powered by FUTO
  Swipe" ở mục **Giới thiệu** (iOS + Android) và trong mô tả công tắc. Luôn hiện, kể cả khi công
  tắc tắt (model vẫn nằm trong app).
- Tên/nhãn hiệu: *"… solely as required by the attribution notice … You may not use the name …
  to suggest a relationship"* ⇒ công tắc đặt tên trung tính ("Mô hình neural gõ vuốt"), "FUTO
  Swipe" chỉ xuất hiện trong câu ghi công; ghi rõ không liên kết/không được FUTO bảo trợ.
- Derivative Model: *"If you distribute a Derivative Model, you must ensure that anyone who receives
  it also receives a copy of these terms … prominent notice … that the model is derived from FUTO
  Swipe … If you modify the Weights, you must include … a prominent notice stating that you have
  modified them"* ⇒ fp16 + đổi bố cục = đã sửa: `futoswipe-LICENSE.md` (đi kèm file trong repo
  VÀ trong bundle/APK) nói rõ nguồn, sha256, cách sửa, và chứa nguyên văn giấy phép;
  `Scripts/futo-swipe/README.md` cũng ghi.
- *"Inference code, source code, and datasets distributed alongside the Weights are governed by
  their own separate licenses"* ⇒ runtime FUTO (GPL) không được kéo theo; suy luận tự viết.
- Điều khoản bằng sáng chế: kiện FUTO về bằng sáng chế ⇒ mất giấy phép. Công bố nghiên cứu dùng
  weights phải trích "FUTO Swipe Model".

### Kiến trúc (đọc từ đồ thị .pte, Scripts/futo-swipe/interp.py)

Đầu vào 64 điểm (x, y chuẩn hoá theo vùng phím chữ 0–1; resample theo thời gian 60 Hz rồi 64 điểm)
→ 8 kênh: x, y, vx, vy (Savitzky–Golay bậc 1, 7 điểm, đệm lặp biên), ax, ay (SG bậc 2),
√(vx²+vy²+1e-8), độ cong = SG bậc 1 của góc hướng atan2 đã unwrap (kẹp ±2) → conv 8→128 k7 +
hardswish → 5 khối (dwconv k7 dilation 1/2/3/5/8 "same" → pw 128→512 → GLU sigmoid(a)·b → GRN
(√mean_t x² + 1e-6, chia trung bình kênh) → pw 256→128 → SE 128→32→128 + residual) → adapter conv
k2 stride 2 (128→256, 64→32 bước) → λ = sigmoid(lin 256→1) ("ý định"), hệ số DCT 8×8 (lin 256→64)
→ logit phím = Σ hệ số·cos(π·u·x_phím)·cos(π·v·y_phím) → log_softmax trên phím + ln λ, blank =
ln(1−λ), kẹp ≥ −100. Không phụ thuộc layout (tâm phím là đầu vào). Tự viết lại: python
(`mine.py`), Swift (`FutoSwipeModel.swift`, vDSP_mmul), Kotlin (`FutoSwipeModel.kt`, khối 4×2).

Kiểm: `mine.py` (weights fp32) vs thông dịch đồ thị gốc: max |Δlog-prob| ≈ 4e-6; fp16 ≈ 0,04–0,08
(greedy giống hệt). Swift / Kotlin vs python trên fixture chung `futo-swipe-fixture.txt`: max |Δ| ≈
1e-4 (đường thường), 3–5e-3 (đường "computer" có đoạn gần đứng yên — góc hướng nhạy).

### Decoder (VietTelex, `FutoSwipe.swift` / `FutoSwipe.kt`)

CTC Viterbi trên chuỗi phím đã gộp chữ lặp của từ vựng hiện có (1.666 dạng Việt không dấu + 20k từ
Anh khi bật), duyệt theo tiền tố (dùng lại cột CTC tiền tố chung, cắt nhánh bằng cận max_t α).
Mặc định **ensemble**: điểm SHARK2 (hình học + tần suất + ngữ cảnh UserLangModel/trigram + phân xử
Việt/Anh) + β·(âm học − âm học tốt nhất), β = 0,1 (tune trên dev), pool = top-16 SHARK2 ∪ top-4 âm
học. Chế độ FUTO một mình (A·âm học + λ·tần suất + ngữ cảnh) giữ trong code để đo.

### Đo (27/09/2026, JVM + simulator, `FutoSwipeEvalTests.kt` / `FutoSwipeTests.swift`, VT_SLOW_TESTS)

Model học từ vuốt THẬT tiếng Anh; đường vuốt ở đây là GIẢ nên số có thể khác thật. Hai kiểu đường:
**nhịp** = FutoSim (minimum-jerk: chậm dần tới phím như tay người), **đều** = SwipeSim hiện có
(tốc độ không đổi, không có nhịp — FUTO dựa nhiều vào nhịp nên bị thiệt).

Câu giữ lại Tatoeba (bigram-heldout, dev = chuỗi %12==0, test = %12==6, n≈1.040 âm tiết, có LM
trigram):

| test | SHARK2 | FUTO một mình | ensemble β=0,1 |
|---|---|---|---|
| nhịp — không dấu top-1 | 0,966 | 0,970 | **0,985** |
| nhịp — có dấu top-1 / top-3 | 0,913 / 0,963 | 0,913 / 0,964 | **0,927** / 0,964 |
| nhịp + bật vuốt tiếng Anh (n=521) — có dấu top-1 | 0,916 | 0,921 | **0,927** |
| đều — không dấu top-1 | 0,967 | 0,884 | 0,964 |
| đều — có dấu top-1 / top-3 | 0,911 / 0,961 | 0,837 / 0,904 | 0,909 / 0,960 |

iOS (Swift) cùng tập test, nhịp: SHARK2 0,913 · FUTO 0,908 · ensemble 0,927 (khớp Kotlin).

Từ rời (500 dạng Việt phổ biến, không ngữ cảnh) top-1 theo độ dài dạng gộp 2/3/4/5+ chữ — nhịp:
SHARK2 0,92/0,89/0,88/0,90 · FUTO 0,94/0,86/0,92/0,90 · ensemble 0,95/0,91/0,94/0,97; đều: SHARK2
0,88/0,90/0,90/0,94 · FUTO 0,85/0,76/0,66/0,59 · ensemble 0,91/0,91/0,82/0,83. Tiếng Anh (500 từ,
prior đang gõ Anh) top-1 — nhịp: SHARK2 0,956 · FUTO 0,946 · ensemble 0,960; đều: 0,960 · 0,820 ·
0,914.

**Thiên lệch tiền nghiệm tiếng Anh:** greedy CTC (không từ điển) trên đường nhịp có tỉ lệ lỗi ký
tự tiếng Việt ≈ 0,09–0,15 so với tiếng Anh ≈ 0,04–0,10 cùng độ dài (gấp ~1,5–2 lần); cặp chữ hay
mất nhất là đặc trưng Việt: hi, ng, uo, hu, ch, ho, ie, th (h trong nh/ch/th, nguyên âm đôi uo/ie
đi qua phím kề). Vì vậy chỉ dùng encoder làm KÊNH PHỤ trọng số nhỏ (β=0,1) cạnh SHARK2 + từ điển
Việt, không thay SHARK2. (Nhận xét người dùng Reddit "FUTO vuốt tiếng Việt rất tệ" là với decoder
cũ + từ điển AOSP; ở đây không tái hiện được mức đó nhờ ràng buộc từ vựng Việt + LM.)

**Độ trễ** (máy dev đang tải nặng, số thật sẽ khác): encoder Swift −O simulator ≈ 3,7 ms, cả
decode ensemble ≈ 4,9 ms; JVM ≈ 14 ms/lần (Android ART dự kiến chậm hơn — decode chạy trên luồng
chính lúc nhấc tay ⇒ có thể tụt 1–2 khung hình; cần đo trên máy thật). SHARK2 ≈ 0,1–0,4 ms.
**RAM** khi bật: weights Float 2,54 MB + scratch ≈ 0,37 MB (file mmap 1,27 MB chỉ lúc nạp); nhả
khi ẩn bàn phím / cảnh báo bộ nhớ (iOS didReceiveMemoryWarning, Android onTrimMemory). Công tắc
tắt: không tạo đối tượng, không đọc file — đường gõ vuốt y như cũ. Kích thước app +1,27 MB.

### Tái tạo

`sh Scripts/futo-swipe/build.sh` (python3 stdlib + curl): tải `.pte` theo revision + kiểm sha256 →
`convert.py` → `verify.py` → chép asset iOS/Android → sinh lại fixture. Kết quả byte-giống bản commit.

## vnlexicon.bin — danh sách âm tiết + tần suất

`iOS/Keyboard/Resources/vnlexicon.bin` = `android/app/src/main/assets/vnlexicon.bin` (VNL2, 150.700 byte,
7.184 âm tiết + tần suất 1 byte; bố cục ở docstring `Scripts/gen-vnlexicon.py`). Danh sách âm tiết: gist
hieuthi (raw `7d729de4…`, maintainer đã rà soát 27/09/2026 — được sử dụng tự do).

**Tái tạo (18/10/2026, giai đoạn 2).** `gen-vnlexicon.py` nay ghi thẳng VNL2 (`--out`) và vá bảng
`firstCharTop` trong `VNLexicon2.swift` / `VNLexicon2.kt` (`--patch-sources`). Bản cũ tái tạo **trùng từng
byte** từ hieuthi + hermitdave/FrequencyWords `content/2016/vi/vi_50k.txt` (commit `b4618471`) — KHÔNG phải
bản 2018 như từng ghi (2018 lệch tần suất; `gen-enlexicon.py` N_VI/CMAX_VI là số của bản 2018).

**Tần suất từ corpus trộn (giai đoạn 2).** Thay thiên lệch phụ đề OpenSubtitles 2016 (mày 203 > máy 183,
cám 182 ≈ cảm 196) bằng số đếm unigram có trọng số trên chính các luồng id của vnlm.bin
(`gen-syllable-lm.py unigram`), cùng lọc/chuẩn hoá teencode/bỏ câu tục của mục "Nguồn hội thoại":

| Nguồn | phần khối lượng | ghi chú |
|---|---|---|
| OpenSubtitles v2024 | 50 % | chạy lại `lm-chat-prep.py opus --short-cap 1e12 --min-syllables 1`: KHÔNG giới hạn câu ngắn ("xin chào", "vâng", "chào" — trần 8 lần/câu của vnlm.bin kéo chúng xuống: chào 194 → 168) |
| FineWeb-2 (lát diễn đàn) | 30 % | luồng của vnlm.bin |
| Tatoeba | 15 % | |
| Wikimedia | 5 % | chỉ để âm tiết hiếm không về 1 |

Thang giữ như bản cũ (token-rate): c' = c·17.011.917/Σc, f = min(255, int(255·ln c' / ln 479.988)) (tổng /
max của hermitdave 2016) ⇒ ngưỡng 0–255 ở mọi nền tảng và thang enlexicon giữ nghĩa. Từ tục bị nguồn hội
thoại bỏ cả câu (lm-chat-prep VULGAR + vãi, vú, ngu, dái, cu) lấy max(cũ, mới) (`--keep-vulgar-from`):
không thì cứt 130 → 8, vãi 126 → 114 — gõ vuốt khi TẮT lọc không ra được. Chọn trên tập DEV (lưới: trọng số
vnlm.bin 60 % văn viết / 25 % / 15 %; 35 / 40 / 25; chỉ hội thoại; hội thoại + 5 % Wikimedia): càng nhiều hội
thoại càng tốt cho dev Tatoeba/FineWeb, OpenSubtitles dev ±0,1; giữ 5 % Wikimedia.

| âm tiết | 2016 | mới | | âm tiết | 2016 | mới |
|---|---|---|---|---|---|---|
| máy / mày | 183 / 203 | **188 / 186** | | cảm / cám | 196 / 182 | **203 / 160** |
| chào / vâng | 194 / 188 | 188 / 185 | | phím / việt | 87 / 120 | 120 / 175 |
| hắn / ngài | 210 / 190 | 191 / 174 | | tôi / không | 255 / 253 | 238 / 242 |

Phân vị tần suất (10/25/50/75/90 %): 7/27/73/119/156 → 4/41/82/126/161; số âm tiết ≥ 150: 849 → 1.044. Kho
âm tiết GIỮ 7.184 (không âm tiết phổ thông nào thiếu; mẫu 27,6 tr token OpenSubtitles: ngoài kho chỉ còn
thán từ ừm 67/tr, suỵt 26/tr, alô 20/tr, hừm 17/tr, đếch 14/tr + rác mã hoá — Phil quyết có thêm không).

Vì id trong vnlexicon xếp theo (dạng không dấu, tần suất giảm) nên id đổi ⇒ vnlm.bin dựng lại
(`gen-syllable-lm.py remap` đổi id các luồng .ids cũ — tương đương chạy lại `ids`, tách âm tiết không phụ
thuộc tần suất); mô hình y hệt (463.463 bigram / 398.822 trigram, 1.991.768 byte), chỉ lexHash + thứ tự id đổi.

    W=…   # luồng .ids của mục "Nguồn hội thoại" (vnlexicon CŨ) + opusfull.ids:
    $D /repo/Scripts/lm-chat-prep.py opus /w/vi.txt.gz --out /w/ids/opusfull --visolex /w/dictionary.json \
        --short-cap 1e12 --min-syllables 1
    E="--weight viwiki=0.026 --weight viwikibooks=0.026 --weight viwikiquote=0.026 --weight viwikisource=0.026 --weight viwikivoyage=0.026"
    $D /repo/Scripts/gen-syllable-lm.py unigram --lexicon OLD.bin --out /w/uni.tsv viwiki.ids viwikibooks.ids \
        viwikiquote.ids viwikisource.ids viwikivoyage.ids tatoeba.ids opusfull.ids fineweb.dt.ids $E \
        --share opusfull=0.5 --share fineweb=0.3
    python3 Scripts/gen-vnlexicon.py syllables.txt --counts $W/uni.tsv --keep-vulgar-from OLD.bin \
        --out iOS/Keyboard/Resources/vnlexicon.bin --patch-sources        # OLD.bin = vnlexicon.bin ở commit 05051963
    cp iOS/Keyboard/Resources/vnlexicon.bin android/app/src/main/assets/
    $D /repo/Scripts/gen-syllable-lm.py remap --old /w/OLD.bin --new /repo/iOS/Keyboard/Resources/vnlexicon.bin \
        --out-dir /w/ids-new /w/ids/*.ids      # rồi count-np + build như mục "Nguồn hội thoại" trên /w/ids-new

Kiểm: dựng lại vnlm.bin cũ từ dump/luồng tải lại 18/10/2026 ra **trùng từng byte** bản 05051963.

**Giấy phép.** Tần suất mới suy ra từ cùng nguồn với vnlm.bin ⇒ vnlexicon.bin (phần tần suất) và SeedData
theo **CC BY-SA 4.0** với cùng thông báo ghi công của vnlm.bin (mục trên); 11 tần suất từ tục giữ từ bản cũ
(hermitdave/FrequencyWords, CC BY-SA 4.0). Danh sách âm tiết: gist hieuthi như trước.

**Ngưỡng 0–255 chỉnh lại trên DEV** (đo MỘT lần trên kiểm thử, bảng dưới):
- AutoCorrect (iOS/Android) minFreq 170 → **175** (margin 30): DEV P 98,7 % (170: 98,0; cũ 98,8), R 27,0 % (cũ 26,8).
- TypoFix tiếng Anh (macOS/Linux/Windows) minFreq 140 → **135**: DEV R 36,0 % (140: 35,4; cũ 35,9), oan trên
  tập giữ nguyên 20 → 14, EN P 95,2 % (cũ 95,4).
- Giữ: TypoFix tiếng Việt 150/80 (vẫn tốt nhất lưới DEV: P 97,3 / R 22,4 %, cũ 97,0 / 22,3), prefersEnglish
  150/80/60, SwipeVocab (bảng chat, nắc 140, sàn nhạy cảm 150, gõ tắt 120/100), λ tần suất gõ vuốt / Thêm dấu.
  Gõ vuốt tiếng Anh (SwipeLangTune DEV): câu Anh y hệt, câu trộn +1,2–1,7, câu Việt +1,4–1,7 điểm.
- enlexicon.bin KHÔNG đổi: đổi N_VI/CMAX_VI sang số 2016 "đúng thang" làm DEV tệ hơn (TypoFix Anh R 35,4 →
  34,5 %, Việt P 97,3 → 96,8 %) — ngưỡng Anh/Việt đã chỉnh trên thang hiện tại.
- emoji.bin (SKEN) không đổi: chỉ dùng dạng không dấu của vnlexicon (section folded y hệt).

## SeedData — seed ban đầu của UserLangModel (18/10/2026)

`iOS/Keyboard/SeedData.swift` sinh bởi `Scripts/gen-seed-data.py` (stdlib) từ số đếm hội thoại (Tatoeba 20 % /
OpenSubtitles `opusfull` 50 % / FineWeb 30 %; `gen-syllable-lm.py unigram --bigram-out --bigram-min 20`) +
lớp chọn tay `Scripts/seed-curated.txt` (teencode/chat, ~105 từ tiếng Anh cap ≤ 18, tên riêng/họ/đệm, hệ điều
hành, từ nhạy cảm cho SwipeVocab, cặp hội thoại của seed cũ — anh ơi, ăn chưa…; `[pin]` em 50 > anh 49 > tôi
48; `[exclude]` tom — tên trong câu Tatoeba). Phần corpus: 800 âm tiết + 600 cặp có PMI ≥ 1 (lưới DEV: 500/380,
800/600, 1200/900 · PMI 0/1/2; 1200/900 chỉ +0,05), trọng số 50·(c/c_max)^0,3 (khớp bảng cũ). 1.139 unigram /
933 bigram (cũ 882 / 509). Rồi: `android/keyboard/scripts/export-ios-data.py` (seed.tsv 17,0 → 27,0 KB),
`Scripts/gen-seed-next.sh`, `windows/app/tools/gen_seed_unigrams.py`, `windows/app/tools/gen_prediction_golden.sh`.
Seed cũ (OpenSubtitles2018) có "cám ơn" 25 — nay chỉ "cảm ơn".

    python3 Scripts/gen-seed-data.py --unigrams $W/uni-chatfull.tsv --bigrams $W/bi-chatfull.tsv --n-uni 800 --n-bi 600

Chỉ sửa lớp chọn tay / SensitiveWords (không có U/B.tsv): `python3 Scripts/gen-seed-data.py --corpus-from-seed` giữ
nguyên khối corpus của SeedData.swift (dừng nếu từ mới lọc nằm trong khối đó). 18/10/2026 (sau giai đoạn 2): thêm
từ/cặp tục–tình dục–chửi thường gặp (bú lồn, địt nhau, đéo biết, đầu buồi…; viết tắt ViSoLex cmm/đmm/loz…; tiếng Anh
motherfucker, bullshit, holy shit…) — từ tục đều vào SensitiveWords (ẩn khi bật lọc); cặp toàn từ thường (thằng chó,
óc chó, lăng nhăng, hãm hiếp, sờ chim…) hiện cho mọi người, trọng số thấp; thêm "you"/"it" để thank you, love you,
damn it… hiện được. 1.181 unigram / 1.000 bigram; keyprior.bin sinh lại (từ ASCII của seed).

Cùng ngày (sau đó): khối `[sensitive-bigram]` của seed-curated.txt — cặp chửi/tục/tình dục/chê ngoại hình ghép từ hai
TỪ THƯỜNG (thằng chó, sờ chim, nâng bi, kích dục, như cột…) vừa vào seed vừa sinh bảng **SensitivePairs**
(`SensitiveWords.pairs` Swift/Kotlin, `windows/app/core/sensitive_pairs.inc`): lọc bật ⇒ không gợi ý từ sau ngay sau từ
trước, cặp không thưởng ngữ cảnh (vuốt, xếp gợi ý, Thêm dấu). Thêm các lô tiếng lóng / Gen Z / tài chính / y tế chỉ
khi vnlm.bin chưa đoán (hạng > 3), kèm cặp NEO (nước ngoài, bóng đá, ví dụ…) để cặp lóng không chiếm ô đầu sau từ rất
thường. `--check` so file đã commit. 1.222 unigram / 1.281 bigram. Sau đó Phil bỏ lọc "con chó", "con gà", "óc chó",
"như heo", "như bò", "như lợn" (nghĩa đen quá thường): "con chó" còn từ corpus, "óc chó" (hạt) thành cặp [bigram]
thường, bốn cặp còn lại bỏ khỏi seed ⇒ 1.222 unigram / 1.277 bigram.

19/10/2026: khối `[sensitive-trigram]` / `[trigram]` của seed-curated.txt — chuỗi chửi BA từ (địt con mẹ, ngu như chó,
óc bã đậu, bố tiên sư, thằng/con/đồ mất dạy, tiên sư bố, mẹ kiếp mày, đồ ăn hại, im mồm đi…). KHÔNG vào SeedData; generator
sinh vào cùng khối GENERATED hai bảng: `SensitiveWords.chains` ("từ1 từ2" → từ3, trọng-số > 0 — chỉ khi thanh gợi ý
iOS người dùng mới + máy tính, TẮT lọc, chưa đoán từ3 ở hạng ≤ 3) và `SensitiveWords.triples` (bộ ba của
[sensitive-trigram] mà lọc theo từ / cặp chưa chặn); Windows `kSeedChains` / `kSensitiveTriples` trong
sensitive_pairs.inc. Từ kế tiếp: chuỗi đứng ngay sau bộ ba người dùng đã gõ (`SuggestRank.nextFill(chain:)`,
WordPrediction / Predict.swift / word_prediction.cpp); chuỗi cũng vào tập ngữ cảnh (xếp gợi ý đang gõ, vuốt). BẬT lọc ⇒
`SensitiveWords.filter(_:after:prev2:enabled:)` / `dropPairs(…prev2:)` bỏ từ3 sau đúng hai từ (từ kế tiếp, hoàn thành
từ, phương án vuốt, ngữ cảnh vuốt) — cặp cuối là cụm thường nên vẫn hiện ("như chó", "mất dạy", "bã đậu", "khốn nạn").
"như chó" vì thế bỏ khỏi [sensitive-bigram] và khỏi seed (⇒ 1.276 bigram). Thêm dấu không đổi (chỉ cặp). `--check`
so cả hai bảng.

### Đo trước / sau giai đoạn 2 (tập KIỂM THỬ, JVM; "trước" = main 18/10/2026 sau giai đoạn 1)

| | trước | sau |
|---|---|---|
| Thêm dấu heldout — âm tiết / câu đúng hết | 97,27 / 85,3 % | **97,53 / 86,3 %** |
| Thêm dấu + seed UserLangModel | 97,25 % | **97,51 %** |
| Từ kế tiếp top-1 / top-3 (người dùng mới) | 24,04 / 40,35 % | **26,07 / 42,37 %** |
| Đang gõ slot1 / 3 slot | 87,11 / 95,69 % | **89,68 / 96,43 %** |
| Phím tiết kiệm | 58,84 % | **60,04 %** |
| Học dần: kế tiếp top-1 / top-3 · slot1 · phím | 24,73 / 41,01 · 89,11 · 59,25 % | 25,83 / 42,11 · 89,81 · 59,97 % |
| Gõ chạm SuggestBigram (seed + bigram): slot1 / 3 slot / kế tiếp top-3 | 0,851 / 0,948 / 0,285 | 0,879 / 0,960 / 0,323 |
| Gõ vuốt heldout top-1 / top-3 | 90,6 / 96,9 % | 90,7 / 96,9 % |
| Câu trộn Việt–Anh top-1 / top-3 (n = 270) | 218 / 269 | 222 / 269 |
| Vuốt xen gõ + sửa theo từ gõ | 94,92 % | 95,39 % |
| Vuốt tuần tự + sửa chung cặp | 92,74 % | 93,61 % |
| AutoCorrect (Android TouchSim) P / R | 97,1 / 23,5 % | 97,2 / 24,4 % |
| TypoFix tiếng Việt (macOS) P / R | 97,2 / 23,6 % | 97,8 / 23,6 % |
| TypoFix tiếng Anh (macOS) P / R; oan tập giữ nguyên | 97,5 / 38,7 %; 20 | 97,8 / 38,5 %; 14 |
| Kiểm thử OpenSubtitles (4.000 câu): Thêm dấu / kế top-1 / slot1 / vuốt top-1 | 94,29 / 19,02 / 83,18 / 87,43 | 94,17 / 19,44 / 85,30 / 87,19 |
| Kiểm thử FineWeb (4.000 câu): Thêm dấu / kế top-1 / slot1 / vuốt top-1 | 92,91 / 20,09 / 80,55 / 84,75 | 93,40 / 21,23 / 83,64 / 85,08 |
| chat-cases.txt (52 câu; 6 câu Phil) | 44 / 52 (6 / 6) | 45 / 52 (6 / 6) |
| An toàn — Thêm dấu / vuốt ra từ tục (heldout + safety-cases + 2 tập kiểm thử) | 1 / 0 | 0 / 0 |

Giá phải trả: tập OpenSubtitles (nguồn tần suất cũ) Thêm dấu −0,12, vuốt −0,24 điểm. Cỡ: vnlexicon 150.700 B,
vnlm.bin 1.991.768 B, enlexicon 183.469 B, keyprior.bin 568.925 B (không đổi); seed.tsv 17.002 → 27.036 B,
SeedData.swift 25,6 → 40,9 KB (computed var, chỉ dựng khi seed), SeedNextData.swift 10,3 KB. RAM: mmap như cũ.
Cặp chọn tay mà vnlm.bin + tần suất mới tự giải khi tắt bảng: 30 (thêm "rảnh chưa"; giai đoạn 1: 29) — chưa bỏ.

Đổi hành vi cần Phil xem: "co dau" đứng một mình về lại "cô dâu" (giai đoạn 1: "có dấu"); add-tones.txt: cám ơn →
**cảm ơn**, ăn phô → **phở**, mấy giờ rồi bắn → **bạn**. Vuốt tắt lọc (SwipeVocabTests): đụ → Dù (trước Đủ),
vú → Vụ, dâm → Đảm, "Ngu" rơi khỏi thanh gợi ý (ngữ 129 → 162), "mò cu" → Mơ chứ (cặp chọn tay không áp
được: "cu" hạng 8 trong dạng "cu"), "sờ cu" → So cứ. iOS: vuốt "nay" + "mai" nay ra "Ngày mai" (chip ↩︎ trả lại).
Gợi ý macOS "tôi hi": "tôi hiểu" là cặp seed nên học "tôi hiền" 5 lần chưa vượt (test đổi sang "anh hi").

## emoji.bin — bàn phím emoji: bộ emoji, tìm kiếm tiếng Việt, kaomoji

`iOS/Keyboard/Resources/emoji.bin` = `android/app/src/main/assets/emoji.bin` (~349 KB:
1.914 emoji Emoji 17.0, 6.493 khoá tìm tiếng Việt, 5.136 khoá tiếng Anh, 260 mã cờ ISO,
136 kaomoji). Sinh bởi `Scripts/gen-emoji-data.py` (python3 stdlib, tự tải nguồn về
`~/.cache/viettelex-emoji/`); không sửa tay.

Khoá tiếng Anh (section SKEN, thêm 14/10/2026: gõ "Japan"/"pizza" ra emoji trên thanh gợi ý
và ô tìm) đã lọc nhiễu tiếng Việt: bỏ khoá một từ < 3 chữ, trùng âm tiết Việt không dấu
(danh sách âm tiết lấy từ `vnlexicon.bin`, xem mục vnlexicon ở trên) hoặc là tiền tố của âm
tiết đó, và cụm gồm toàn âm tiết Việt. Mã nước ISO 3166-1 alpha-2 (section FLG2) lấy từ
chính chuỗi regional-indicator của emoji cờ (không phải dữ liệu ngoài), thêm bí danh "UK" → 🇬🇧;
chỉ tra khi gõ IN HOA vì 65/259 mã trùng âm tiết Việt (la, ma, to, do, ca, co…).

| Nguồn | Bản dùng | Giấy phép | Dùng cho |
|---|---|---|---|
| [Unicode emoji-test.txt](https://unicode.org/Public/17.0.0/emoji/emoji-test.txt) | Emoji 17.0 (2025-08-04) | [Unicode License v3](https://www.unicode.org/license.txt) | danh sách, thứ tự, phiên bản emoji |
| [CLDR annotations vi](https://github.com/unicode-org/cldr/tree/release-48/common/annotations) + annotationsDerived vi | CLDR release-48 | Unicode License v3 | tên / từ khoá tiếng Việt để tìm |
| [CLDR annotations en](https://github.com/unicode-org/cldr/blob/release-48/common/annotations/en.xml) + [annotationsDerived en](https://github.com/unicode-org/cldr/blob/release-48/common/annotationsDerived/en.xml) | CLDR release-48 | Unicode License v3 | tên / từ khoá tiếng Anh (kể cả tên nước "flag: Japan" → "japan") để tìm + gợi ý khi gõ |
| EmojiSuggest (khoá gợi ý emoji sẵn có, `emojisuggest.bin`) | trong repo | MIT (dự án) | từ khoá tiếng Việt biên soạn |
| Kaomoji / bảng ký hiệu | biên soạn tay trong script | MIT (dự án) | tab ^‿^ |

Unicode License v3 cho phép dùng, sửa, phân phối (kể cả thương mại) miễn kèm thông báo
bản quyền "Copyright © 1991-2025 Unicode, Inc." và điều khoản giấy phép
(https://www.unicode.org/license.txt). emoji.bin là dữ liệu biến đổi (lọc, gộp, fold không
dấu, đóng gói nhị phân) từ các file trên.

## mixed-typing.tsv — corpus mô phỏng gõ câu trộn Việt–Anh (30/10/2026)

`TelexCore/Corpus/mixed-typing.tsv` (~120 KB, 2.333 câu, 15.543 từ) sinh bởi
`Scripts/gen-mixed-typing-corpus.py` (stdlib, tất định). Chỉ dùng để ĐO engine
(`mixed-eval`, `MixedTypingGoldenTests` — docs/REGRESSION.md mục "Mô phỏng gõ câu trộn");
**không đóng gói vào app**. Mỗi dòng mang nhãn ngôn ngữ từng từ (e/v).

| Nhóm | Nguồn | Giấy phép |
|---|---|---|
| `vi` | câu tiếng Việt [Tatoeba](https://tatoeba.org) đã có trong repo (`iOS/KeyboardTests/Fixtures/bigram-heldout.txt`, lấy 1/3 theo hash) + câu chat có dấu tự soạn (`chat-cases.txt` cột phải) | [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/) (Tatoeba) / MIT (tự soạn) |
| `en` | câu tiếng Anh Tatoeba (`swipe-lang-sentences.txt` loại `en`, lấy 1/2 theo hash) | CC BY 2.0 FR |
| `mix` | câu trộn của `swipe-lang-sentences.txt` loại `mix`: tự soạn + ghép câu Tatoeba Việt/Anh + chèn một từ Anh vào câu Tatoeba Việt | CC BY 2.0 FR (phần Tatoeba) / MIT |
| `tech`, `collide`, `teen` | tự soạn cho dự án: `TelexCore/Corpus/mixed-typing-handwritten.txt` (306 câu chat công việc/lập trình, 110 câu có từ Anh trùng phím âm tiết Việt — gồm các câu cur± của `gen-retro-english-eval.py`, 50 câu teencode) | MIT (cùng mã nguồn) |

Ghi công Tatoeba: "Câu từ Tatoeba (https://tatoeba.org), © các thành viên Tatoeba, CC BY 2.0 FR" —
có trong dòng đầu file corpus. CC BY 2.0 FR cho phép sửa/ghép (ghép câu, chuyển chữ thường) và dùng
thương mại khi ghi công; không có ShareAlike. Tách `val`/`test` theo `sha1(câu) % 3` (test = 0, ~1/3),
**tập test khoá**: chỉnh luật engine chỉ nhìn val; diff từng từ của test chỉ in khi thêm `--unlock-test`.
