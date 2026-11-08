# viettelex-rates

Cloudflare Worker trên route `viettelex.com/api/*`, trả **một dòng chữ thuần** (`text/plain; charset=utf-8`)
để dùng làm "mẫu câu động" trên bàn phím iOS/Android: dán URL vào mẫu câu, bàn phím GET lúc chạm và chèn nguyên văn body
(tối đa 1000 byte).

| Đường dẫn | Ví dụ |
|---|---|
| `GET /api/usd` | `1 USD = 25.618 ₫ (giá giữa thị trường, ngày 07/11/2026)` |
| `GET /api/usd-tudo` | `USD tự do: mua 25.900 ₫ – bán 25.950 ₫ (09:11 08/11/2026)` |
| `GET /api/vang` | `Vàng SJC: mua 138,0 – bán 141,0 triệu/lượng · Nhẫn 9999 PNJ: mua 136,3 – bán 140,3 triệu/lượng (12:29 07/11/2026)` |
| `GET /api/btc` | `1 BTC = 1.937.205.000 ₫ (≈ 75.618 USD, 09:11 08/11/2026)` |

Thêm `?en=1` để lấy bản tiếng Anh. Giờ hiển thị là giờ Việt Nam (GMT+7) của thời điểm nguồn cập nhật
(nguồn có ghi giờ) hoặc của lúc Worker tải về (nguồn không ghi giờ). Nguồn chỉ có ngày ⇒ hiện `ngày dd/mm/yyyy`.

## Hành vi

- **Cache** (Cache API, theo từng đường dẫn): `usd` 1 giờ, `usd-tudo` và `vang` 10 phút, `btc` 90 giây.
  Mọi nguồn lỗi ⇒ dùng tạm bản cũ trong cache (`usd` ≤ 48 giờ, `usd-tudo`/`vang` ≤ 12 giờ, `btc` ≤ 30 phút);
  giờ trong câu vẫn là giờ của dữ liệu nên người đọc thấy được độ cũ.
- **Dự phòng**: các nguồn hỏi theo thứ tự ưu tiên; nguồn sau khởi động khi nguồn trước lỗi hoặc chậm quá 1,2 s.
  Mỗi nguồn tối đa 3 s, cả lượt tối đa 3,5 s (bàn phím chỉ chờ 4 s).
- **Kiểm tra số**: USD/VND 15.000–60.000, vàng 30–600 triệu/lượng, BTC 1.000–10.000.000 USD; mua ≤ bán, chênh lệch
  mua/bán hợp lý. Trang nguồn đổi giao diện ⇒ parser báo lỗi ⇒ chuyển nguồn, không bao giờ chèn số rác.
- **Lỗi luôn trả 200** với câu báo ngắn (`Chưa lấy được tỷ giá, thử lại sau.`, `Chưa lấy được giá vàng, thử lại sau.`,
  `Chưa lấy được giá BTC, thử lại sau.`), `Cache-Control: no-store`, header `X-Rates-Error: 1`.
  Lý do: Android (`HttpURLConnection.inputStream`) ném lỗi khi mã ≥ 400 và chèn lại chính URL; iOS chèn body bất kể mã.
  Chỉ mã 200 mới cho cả hai chèn câu báo thân thiện.
- Header: `Access-Control-Allow-Origin: *`, `Cache-Control: public, max-age=60` khi thành công,
  `X-Rates-Source` (nguồn đã dùng), `X-Rates-Cache` (`hit` / `miss` / `stale`).

## Nguồn dữ liệu và điều khoản

Kiểm tra ngày 08/11/2026. Không dùng nguồn nào cần API key.

**`/api/usd` — tỷ giá giữa thị trường**
1. [fawazahmed0/exchange-api](https://github.com/fawazahmed0/exchange-api) qua jsDelivr — JSON, giấy phép **CC0-1.0**, cập nhật hằng ngày (chỉ có ngày).
2. Cùng dữ liệu đó qua bản sao `latest.currency-api.pages.dev` (tác giả khuyến nghị làm dự phòng).
3. Coinbase `api.coinbase.com/v2/exchange-rates?currency=USD` — API công khai không cần khoá; giờ = lúc tải.

Đã loại: `open.er-api.com` (ExchangeRate-API open access) — điều khoản yêu cầu ghi nguồn và **cấm phân phối lại**
dữ liệu, mà Worker này chính là phân phối lại.

**`/api/usd-tudo` — USD tự do (chợ đen)**: không có nguồn chính thức/JSON, buộc phải đọc HTML.
1. `tygiausd.org` (trang chủ, bảng "USD chợ đen"). robots.txt cho phép `/` (chỉ cấm `/home/getdata`, `/home/Error`, `/Test`).
2. `chogia.vn/ngoai-te/usd-cho-den/` (câu "mua vào là … và bán ra là …"). robots.txt không cấm đường dẫn này.

Giờ = lúc Worker tải (các trang không ghi giờ cập nhật đủ chính xác). Mỗi trang bị tải tối đa ~1 lần/10 phút/vị trí cache.

**`/api/vang` — giá vàng trong nước (đồng/lượng, hiển thị triệu/lượng)**
1. PNJ `edge-api.pnj.io/ecom-frontend/v1/get-gold-price?zone=00` — JSON công khai mà chính pnj.com.vn dùng, không khoá.
   Giá theo **nghìn đồng/chỉ** ⇒ × 10.000 ra đồng/lượng. Lấy "Vàng miếng SJC 999.9" (`masp=SJC`) và
   "Nhẫn Trơn PNJ 999.9" (`masp=N24K`); giờ = `updateDate` của PNJ.
2. `giavang.org` (trang chủ: "Giá vàng Miếng SJC", "Giá vàng Nhẫn SJC", đơn vị `x1000đ/lượng`, giờ "Cập nhật lúc …").
   robots.txt cho phép tất cả.

Vì giá nhẫn khác nhau theo thương hiệu, câu ghi rõ `Nhẫn 9999 PNJ` hoặc `Nhẫn 9999 SJC`.
Không dùng trực tiếp `sjc.com.vn`: dịch vụ giá của SJC đang đứng sau trang thử thách chống bot, không gọi tự động được.

**`/api/btc`** — giá BTC/USD × tỷ giá giữa thị trường của `/api/usd`, làm tròn tới nghìn đồng.
1. Coinbase Exchange `api.exchange.coinbase.com/products/BTC-USD/ticker` (công khai, không khoá; giờ = giao dịch cuối).
2. Kraken `api.kraken.com/0/public/Ticker?pair=XBTUSD` (công khai, không khoá; giờ = lúc tải).

Đây là thông tin tham khảo, không phải báo giá giao dịch.

## Phát triển

```sh
cd workers/rates
node --test test/            # parser + định dạng + chuỗi dự phòng, fixture trong test/fixtures/
npx wrangler deploy --dry-run
CLOUDFLARE_ACCOUNT_ID=<tài khoản cá nhân> npx wrangler deploy
curl -s https://viettelex.com/api/vang
```

Không có bước build, không phụ thuộc npm. Trang nguồn đổi giao diện ⇒ cập nhật regex trong `src/parse.js`
và fixture tương ứng.
