# VietTelex — Regression suite (độ chính xác)

Bộ test đối chiếu engine với **`telex_test_suite.csv`** (9.091 ca hợp lệ, bundled trong
`TelexCore/Tests/TelexCoreTests/Resources/`): từ tiếng Việt, từ tiếng Anh, và các
chuỗi phím nhập nhằng giữa hai thứ tiếng.

```bash
cd TelexCore && swift test --filter SuiteRegression
```

Harness (`SuiteRegressionTests.swift`) replay đúng như controller thật: chữ cái thì
compose, mọi ký tự khác (space, số, dấu câu) là **word boundary** → commit từ rồi
in ký tự đó. Nhờ vậy `ipv4`, `vieejt-nam`, `xin chaof!` đều round-trip đúng.
Cài đặt khi đo: `liveSpellCheck` ON (mặc định app), `freeMarking` OFF (xem
*Ghi chú* cuối trang).

## 4 bucket

| Bucket | Nghĩa | Ngưỡng |
|---|---|---|
| `transform` | Từ **Việt** phải ra đúng dạng có dấu (`vieejt` → việt) | **100%, exact** — hỏng 1 ca là fail build |
| `keep_as_typed` | Từ **Anh** engine không transform → phải giữ nguyên | **100%, exact** |
| `restore_raw` | Từ **Anh** BỊ transform → boundary phải khôi phục chuỗi phím gốc | **floor** (không được tụt) |
| `ambiguous_needs_context` | Compose ra âm tiết Việt hợp lệ NHƯNG chuỗi phím cũng là từ Anh (`his` → hí) — chỉ context (từ trước là tiếng Anh) mới lật được | **floor** |

Hai bucket tiếng Anh là **aspirational**: engine không mang từ điển tiếng Anh đầy
đủ (xem *Vì sao không 100%*), nên chốt sàn thay vì đòi tuyệt đối. Cải thiện được
thì nâng sàn ngay trong test.

## Kết quả

| Ngày | Version | transform | keep_as_typed | restore_raw | ambiguous (có context) | Ghi chú |
|---|---|---|---|---|---|---|
| 2026-07-25 | 1.4.16-dev | 400/400 | 362/362 | 6.790/7.282 (93,2%) | 632/1.047 (60,4%) | baseline sau khi chuẩn hoá harness theo boundary + mở rộng whitelist context |
| 2026-07-25 | 1.4.16-dev | 400/400 | 362/362 | 6.803/7.282 (93,4%) | 632/1.047 | fix free-marking bóp méo dù có cancel (`excess` → êcs) |
| 2026-07-26 | 1.4.16-dev | 400/400 | 362/362 | 7.212/7.282 (99,0%) | 632/1.047 | luật hình dạng tone-cancel + refresh bảng collision (438 → 498 từ) |
| 2026-07-26 | 1.4.16-dev | **400/400** | **362/362** | **7.201/7.282 (98,9%)** | **632/1.047** | **bỏ luật restore cho phím-đôi-kề-nhau (field report `tessted`), bù bằng từ điển sinh từ chính suite (498 → 757 từ)** |

Latency không đổi qua đợt 2026-07-26 (release build, cùng máy): **0,138 µs/phím**
(Việt) / 0,150 (Anh) / 0,007 (passthrough) — nằm trong dao động run-to-run của
[`BENCHMARKS.md`](BENCHMARKS.md). Bộ nhớ thêm: 3 Int trong parse state; tra từ điển
chỉ chạy ở **boundary của từ có cancel**, không nằm trên hot path.

## Đợt 2026-07-26: nhóm "tone-cancel ăn mất chữ"

Nhóm lỗi lớn nhất còn lại của `restore_raw`: từ tiếng Anh có **phụ âm-thanh gấp
đôi** (`ss ff rr xx jj`) — phím 1 bỏ dấu, phím 2 huỷ dấu và rơi mất 1 chữ:
`office` → ofice, `possess` → posess, `current` → curent.

Không thể chỉ "cancel thì luôn giữ nguyên": người dùng cũng **cố ý** gõ phím đôi
để escape (`gooogle` → google, `DDDR` → DDR, `hoass` → hoas). Hai tín hiệu cấu
trúc phân biệt được, **không cần từ điển**:

| Dạng cancel | Ví dụ | Quyết định |
|---|---|---|
| **Phím đôi KỀ NHAU** (tone `ss`/`ff`… hoặc mark `aaa`/`ooo`/`ddd`/`ww`), ở bất kỳ đâu trong từ | `tessted` → tested · `Deffault` → Default · `gooogle` → google · `DDDR` → DDR · `hoass` → hoas · `iss` → is | **GIỮ composed** — what you see is what you commit |
| Phím tone **vươn ngược** (phím thanh bị huỷ nằm cách vài chữ) | `hosts` · `asks` · `discs` · `buses` | **RESTORE** raw |
| Bất kỳ dạng nào, nhưng **raw có trong từ điển** | `office` · `possess` · `message` · `class` | **RESTORE** raw (từ điển thắng tất cả) |
| Mark doubler huỷ mũ để **dấu thanh treo**, rồi liveSpellCheck freeze **gập** dấu đó về chữ thường (`tonesFolded`, 26/09/2026) | `cheese` · `geese` · `reference` · `cosaaa` | **RESTORE** raw (từng chốt `chese`/`refrence` — mất chữ) |

Nguyên tắc: escape thật **luôn** là phím đôi kề nhau, còn cancel vươn ngược thì
không bao giờ là escape → đó là tín hiệu cấu trúc duy nhất dùng được.

**Lần thử sai đã revert (ghi lại để không lặp):** ban đầu tôi cho *mọi* cancel giữa
từ restore raw (đưa restore_raw lên 99,0%), nhưng bàn phím của escape và của phụ âm
đôi tiếng Anh **giống hệt nhau** — `tessted` → tested (người dùng cố ý) không phân
biệt được với `office` → ofice (engine ăn mất chữ). Field report 2026-07-26 (`tessted`
bị đổi thành `tessted` sau space) chứng minh luật đó sai hướng: chỉ **từ điển** được
quyền lật, còn lại phải tôn trọng cái đang hiện trên màn hình.

Chi tiết trong `shouldRestoreRaw()` (`TelexEngine.swift`), golden test
`testAdjacentDoubleKeepsWhatTheScreenShows` + `testReachBackToneCancelRestoresWithoutDict`.

Bù lại bằng từ điển — `gen-english` có 2 thay đổi (nguyên liệu đầu vào là
[`google-10000-english`](https://github.com/first20hours/google-10000-english),
danh sách 10.000 từ tiếng Anh xếp theo tần suất):
- **Monotone**: bảng sinh ra là HỢP với bảng đang ship (luật mới cứu được từ nào thì
  vẫn giữ entry, vì cài đặt không mặc định như tắt bỏ dấu tự do / Simple Telex có thể
  vẫn cần).
- **Corpus bổ sung từ chính suite**: cột input của bucket `restore_raw`, **chỉ nhận từ
  ≥5 chữ** — từ ngắn là bãi mìn tiếng Việt (`cos`=có, `gif`=gì, `max`=mã) — vẫn đi qua
  đủ engine-check + junk + protect list (đợt này protect thêm `ướt`=worst, `lẩu`=laura).

Bảng: 438 → **757 từ** (~vài chục KB, tra `Set<String>` ở boundary).

## Vì sao không 100%

**`restore_raw` — 81/7.282 ca còn lại (1,1%), đều là "dictionary-only":**

- **Protect-list**: chuỗi phím tiếng Anh trùng ĐÚNG cách gõ Telex của một từ Việt
  thật → **tiếng Việt luôn thắng** (`won` = ươn, `worst` = ướt, `zoo` = zô,
  `gif` = gì). Chính sách, không phải bug.
- **Viết tắt / tên riêng**: `ross`, `ieee`, `usps`, `nginx`, `ddr`, `isp` — không
  từ điển nào phủ, và thêm vào sẽ nuốt cách gõ tiếng Việt.
- **Token 2–3 chữ trong chuỗi symbol**: `/usr/local/bin`, `os.path`, `arr[i]`,
  `MAX_SIZE` — mảnh `us`, `os`, `arr`, `max` compose thành âm tiết Việt hợp lệ.
- **Phụ âm đôi kề nhau ngoài từ điển**: `carr`, `cass`, `hajj`, `toff`, `arr`, `ruff`
  — không thể restore bằng luật vì trùng bàn phím với escape có chủ ý (xem trên).

**`ambiguous_needs_context` — 632/1.047 (1.047 dòng = 344 từ distinct):**

| Sub-case | Từ distinct | Ý nghĩa |
|---|---|---|
| `ctx_fixes` | 162 | Sai khi đứng riêng, **đúng khi trong mạch tiếng Anh** — feature làm việc |
| `ok_both` | 49 | Đã restore sẵn, không cần context |
| `ctx_misses` | 133 | Engine giữ tiếng Việt, không restore |
| `ctx_breaks` | **0** | Context chưa làm hỏng ca nào |

Từ 2026-07-26 whitelist context tách 2 lớp: `words` (mở được mạch tiếng Anh) và
`restoreOnly` — thán từ / từ chat (`wow`, `ok`, `hi`, `sorry`, `thanks`…) **được khôi
phục khi đang trong mạch tiếng Anh nhưng không bao giờ mở mạch**, vì người Việt dùng
chúng để mở câu tiếng Việt ("ok cám ơn", "wow đẹp quá"). Field report 2026-07-26:
"that's great wow" commit ra `wơ` trong Simple Telex (`w` literal + `ow` → ơ, và `wơ`
lại hợp lệ qua teencode w→qu = "quơ" nên validator không cứu).

Toàn bộ 133 ca `ctx_misses` là những dòng **chính suite ghi chú `never`** ("restore
sẽ làm từ Việt KHÔNG THỂ GÕ ĐƯỢC NỮA" — `bar` = bả, `car` = cả, `box` = bõ,
`bus` = bú, `max` = mã, `moon` = môn, `own` = ơn, `queen` = quên), tức cột
`expected` của suite tự mâu thuẫn với note của nó. Không có ca nào suite nói *nên*
restore mà engine bỏ sót → phần thiếu là **tranh chấp chính sách Việt-vs-Anh**, không
phải lỗi phủ context.

Bảng đánh giá tay cho nhóm ambiguous (mỗi từ distinct 1 dòng: output có/không
context, cờ whitelist/collision, note gốc của suite, mức ưu tiên review) sinh theo
yêu cầu — không commit vào repo vì là artifact review, không phải nguồn sự thật.

## Bộ suite này KHÔNG phủ tiếng Việt (và cách bịt)

Issue #29 (27/07: gõ `quyts` ra `quyts` thay vì `quýt`) lọt qua toàn bộ 9.091 ca —
đúng ra là phải lọt, vì:

- **Suite này là suite TIẾNG ANH.** Phần `transform` chỉ 400 dòng và gần hết là
  *chuỗi phím tiếng Anh → âm tiết Việt* (`of`→ò, `is`→í, `las`→lá): 4/5 dòng dài
  ≤5 ký tự, không có một từ qu- + coda nào. Nó đo "engine có khôi phục đúng tiếng
  Anh không", KHÔNG đo "engine gõ đúng tiếng Việt không".
- **`testComposeIsIdempotentOverValidCombos`** (TypingMatrixTests) có sinh
  `qu`×`uy`×`t`×`s`, nhưng nó `guard SyllableValidator.isValidSyllable(x)` — nên một
  **false-negative của validator tự miễn trừ chính nó**: ca hỏng bị *skip*, không bị
  *fail*. Bẫy tự-hoàn-thành.

Đã thêm **`testEveryOnsetRimeToneComposesAndSurvives`**: quét TOÀN BỘ
onset × rime × tone lấy trực tiếp từ bảng luật (~25.000 ca, +0,44s), gõ từng ca rồi
đòi (a) composed phải được coi là âm tiết Việt hợp lệ, (b) auto-restore không được
lật nó. Kỳ vọng lấy từ **bảng luật**, không hỏi engine/validator. Hai quy tắc quan
trọng: tone hợp lệ suy từ chính tả rime (coda tắc ⇒ chỉ sắc/nặng), và nguyên âm dùng
chung của glide được viết CẢ HAI cách (`qu`+`uyt` = `quyt`, một chữ u) — chỗ ambiguity
đó là nơi cả hai bug nằm.

Chạy ngược lại trên bản 1.4.16 (chưa fix): **62 ca fail**, gồm đúng nhóm
quýt/quỳnh/quých — tức bộ test này bắt được issue #29. Nó còn lộ ra **bug thứ hai
chưa ai báo**: `giếc` (cá giếc) và `giệc` bị split thành `gi` + `êc` (không phải rime)
mà không bao giờ được thử lại thành `g` + `iêc` (là rime) → cũng bị auto-restore về
chuỗi phím. Từ nay `isValidSyllable` thử MỌI cách đọc rồi mới kết luận, giống
`isValidPrefix` vốn đã làm.

## Ghi chú

- **`freeMarking` OFF khi đo**: bỏ dấu tự do reach-back rất mạnh, trong kiểu replay
  từng phím thô của harness nó bóp méo từ Anh nhiều nguyên âm đôi (`excess` → êcs)
  — không phản ánh cách gõ thật, và sẽ làm *thấp giả* tỉ lệ restore. Vài dòng
  multi_path mà nó fix không đáng đổi.
- **18 dòng non-defect đã bị gỡ khỏi suite**: suite-wrong (`giaj` → giạ, `uow` → uơ),
  undefined_behavior (expected `?`), lựa chọn spec/mixed-case (`ToAnS`), và một
  token hai âm tiết (`đôla`) — nhờ vậy bucket `transform` mới chốt được exact 100%.
- Suite gán mỗi biến thể hoa/thường là một dòng riêng (`ROSS` / `Ross` / `ross`),
  nên số dòng luôn lớn hơn số từ distinct khoảng 3×.

## Mô phỏng gõ câu trộn Việt–Anh (từ 30/10/2026)

Suite trên đo từng TỪ đứng riêng. Bộ này đo cả CÂU, gõ từng phím như người thật, để mọi thay
đổi luật (ngữ cảnh tiếng Anh, bảng collision, "Tự sửa từ phía trước", teencode) được chấm bằng số.

```bash
cd TelexCore && swift run -c release mixed-eval            # số đo 3 cấu hình + mẫu lỗi + diff (val)
swift run -c release mixed-eval --trace "this is"          # vết từng phím của câu chứa đoạn đó
swift run -c release mixed-eval --check                    # so golden, exit 1 nếu tụt
swift run -c release mixed-eval --write-golden             # chốt số mới (sau khi cải thiện)
swift test --filter MixedTypingTests                       # test golden (~6 s debug)
```
Tuỳ chọn khác: `--config default|retro|no-context`, `--diff-config`, `--lines N` (-1 = tất cả),
`--top N`, `--unlock-test`. Chạy cả corpus ~0,5 s (release).

**Corpus** — `TelexCore/Corpus/mixed-typing.tsv`, 2.333 câu / 15.543 từ, 6 nhóm: `vi` (Tatoeba +
chat có dấu), `en` (Tatoeba), `mix` (câu trộn), `tech` (chat dev tự soạn), `collide` (từ Anh trùng
phím âm tiết Việt), `teen` (teencode). Nguồn + giấy phép: [DATA-SOURCES.md](DATA-SOURCES.md) mục
"mixed-typing.tsv". Tách val/test theo hash câu; **test khoá** — chỉ chỉnh trên val (lệnh chỉ in
diff của val), test chỉ để báo số, golden giữ cả hai.

**Người gõ mô phỏng** (`TelexCore/Sources/MixedTyping/Typist.swift`, seed theo câu ⇒ tất định):
từ Việt gõ Telex (ươ = `uow` 55% / `uwow`; ư riêng đôi khi một phím `w`; chữ w thật = `ww`); phím
thanh cuối từ 75%, sau nguyên âm cuối của vần 13%, ngay sau nguyên âm mang dấu 12%; từ Anh gõ
nguyên văn; ~3% số từ có lỗi gõ (phím kề / chèn / đảo / lặp) — người gõ nhìn màn hình, thấy lệch
thì ⌫ tới khi khớp một tiền tố đúng rồi gõ lại (đi qua đường ⌫ của engine). Phím đi qua đúng API
controller macOS dùng (feed / backspace / commitText ở ranh giới / pendingRetroCorrection +
takeRetroCorrection trước ký tự ranh giới / noteBoundaryCharacter; hết câu = Enter → resetContext).
So từ không phân biệt VỊ TRÍ dấu thanh (hoà ≡ hòa — là cài đặt, không phải lỗi).

**Số đo** (càng thấp càng tốt; "overall" = trung bình KHÔNG trọng số của 6 nhóm):
- `lazy` — người gõ lười, không bao giờ bật/tắt bộ gõ: % từ sai, tách % từ Việt sai / % từ Anh sai.
- `toggle/100` — người gõ lý tưởng: trước mỗi từ, nếu gõ tiếp sẽ ra sai thì bật/tắt bộ gõ (tắt =
  phím đi thẳng, bật lại = resetContext). Khi tự sửa từ phía trước bật, "ra sai" xét sau tối đa 5 từ
  gõ tiếp (phép sửa ngược có thể chữa muộn). `ideal%` = từ vẫn sai ở cả hai chế độ.
- Latency từng lệnh engine trên cả corpus (chỉ có nghĩa ở `-c release`; máy bận thì dao động).

**Cấu hình**: `default` = mặc định app macOS (bỏ dấu tự do, kiểm tra chính tả, auto-restore + khôi
phục sớm, ngữ cảnh tiếng Anh BẬT, collision ưu tiên tiếng Việt, teencode TẮT — riêng nhóm `teen` bật,
"Tự sửa từ phía trước" TẮT = chỉ đề xuất, người gõ lười không bấm Tab); `retro` = như trên + tự sửa
từ phía trước BẬT (tự áp); `no-context` = "Quyết định theo ngữ cảnh" TẮT.

**Golden**: `TelexCore/Corpus/mixed-typing-golden.json` — mọi số đo × nhóm × split × cấu hình;
`MixedTypingGoldenTests` fail khi bất kỳ số nào tệ hơn golden quá 0,05 điểm % (nhỏ hơn một từ ở
mọi nhóm — mô phỏng tất định nên đổi một từ là thấy). Cải thiện ⇒ test in ra, chạy `--write-golden`
và thêm một dòng vào bảng dưới.

### Kết quả (val / test, overall = trung bình nhóm)

| Ngày | Cấu hình | lazy % | lazy VI % | lazy EN % | toggle/100 | ideal % |
|---|---|---|---|---|---|---|
| 2026-10-30 | `default` | 5,72 / 5,60 | 1,14 / 1,07 | 8,73 / 8,85 | 3,43 / 3,02 | 0,92 / 0,85 |
| 2026-10-30 | `retro` (tự sửa từ phía trước BẬT) | **3,76 / 3,37** | 1,14 / 1,07 | **5,52 / 5,00** | **2,20 / 1,69** | 0,93 / 0,85 |
| 2026-10-30 | `no-context` | 8,80 / 8,32 | 1,13 / 1,07 | 13,71 / 13,65 | 5,50 / 4,44 | 0,92 / 0,85 |

Theo nhóm (val, `default` → `retro`): `vi` 0 / 0 (3.385 từ Việt, kể cả lỗi gõ + ⌫, không từ nào sai);
`en` 4,33 → 1,86; `mix` 1,74 → 0,99; `tech` 1,41 → 1,41; `collide` 21,31 → 12,78; `teen` 5,50 → 5,50.
`lazy VI` ≠ 0 chỉ do nhóm `teen` ("wá" — xem dưới) và một câu ghép "… late ò ó o o" (ò → of sau mạch Anh).

Latency (release, M-series, máy đang chạy việc khác): phím chữ ~120 ns mean / ~1,2 µs p99.9 ở cả ba cấu
hình; phím RANH GIỚI ~1,1–1,2 µs mean / ~7,5–9 µs p99.9 khi ngữ cảnh + sửa ngược bật, so với ~0,4 µs /
~0,85 µs khi tắt — phần đắt là `retroRecord` (vài String mỗi lần chốt từ), vẫn xa ngưỡng cảm nhận.

### Mẫu lỗi hay gặp (val, `default`, người gõ lười) — định hướng việc tiếp

| # | Mẫu | Lần | Ghi chú (`retro` còn) |
|---|---|---|---|
| 1 | is → í | 46 | đầu câu / trước khi mạch Anh mở (18) |
| 2 | this → thí | 26 | như trên (14) |
| 3 | test → tét | 17 | từ mượn trong câu VIỆT — ngữ cảnh không cứu được (15) |
| 4 | did → đi | 15 | (2) |
| 5 | his → hí | 13 | (4) |
| 6 | how → hơ | 11 | (2) |
| 7 | there → thể | 9 | (1) |
| 8 | car → cả · wá → was | 6 · 6 | `wá` (teencode, nhóm teen): Telex chuẩn gõ `ww`+`as` nhưng escape `ww` đóng băng từ ⇒ không gõ ra được (chỉ Simple Telex) (4 · 6) |
| 9 | of → ò | 5 | (2) |
| 10 | borrowed → borowed · bus → bú · has → há · off → of · pass → pas · post → pót | 4 mỗi mẫu | phụ âm đôi bị huỷ dấu (rr/ff/ss) + từ nội dung trùng âm tiết (car/bus/box/bar/queen/post/must/busy) |

Nhóm lỗi: (a) từ chức năng Anh ở ĐẦU mạch (is/this/his/how/did/there/its/has/as/of) — sửa ngược
cứu được phần lớn; (b) từ mượn công nghệ trong câu Việt (test, post, down, pair) — cần chính sách
riêng, ngữ cảnh hai phía là Việt; (c) phụ âm đôi tiếng Anh bị nuốt (pass/off/boss/chess/kissed/
borrowed) — chỉ từ điển cứu được; (d) teencode chữ w không gõ được ở Telex chuẩn.
