// Bộ đọc (parser) thuần cho từng nguồn: nhận body đã tải, trả số đã chuẩn hoá hoặc ném lỗi.
// Mọi số đều qua kiểm tra khoảng (sanity) để trang nguồn đổi giao diện không làm chèn số rác.
//
// Thời điểm: { ms, dateOnly } — ms là epoch UTC; dateOnly = nguồn chỉ cho ngày (không giờ).

const VN_OFFSET_MS = 7 * 3600 * 1000; // Asia/Ho_Chi_Minh, không có giờ mùa hè

export class ParseError extends Error {}

function fail(msg) { throw new ParseError(msg); }

/** "25,900" / "25.900" / "138.000" → 25900 / 138000 (chỉ dùng cho số nguyên có dấu phân cách nghìn). */
export function digitsInt(s) {
  const d = String(s).replace(/[^\d]/g, "");
  if (!d) fail(`không có số: ${s}`);
  return Number(d);
}

/** "dd/mm/yyyy hh:mm[:ss]" giờ Việt Nam → epoch ms. */
export function vnDateTimeToMs(day, month, year, hour = 0, minute = 0, second = 0) {
  const ms = Date.UTC(+year, +month - 1, +day, +hour, +minute, +second) - VN_OFFSET_MS;
  if (!Number.isFinite(ms)) fail("thời điểm không hợp lệ");
  return ms;
}

export function inRange(n, lo, hi, what) {
  if (typeof n !== "number" || !Number.isFinite(n) || n < lo || n > hi) fail(`${what} ngoài khoảng: ${n}`);
  return n;
}

// ---- Khoảng hợp lệ ----
export const USD_VND = [15_000, 60_000];
export const GOLD_VND_PER_LUONG = [30_000_000, 600_000_000];
export const BTC_USD = [1_000, 10_000_000];

function checkBuySell(buy, sell, [lo, hi], maxSpreadRatio, what) {
  inRange(buy, lo, hi, `${what} mua`);
  inRange(sell, lo, hi, `${what} bán`);
  if (buy > sell) fail(`${what}: mua > bán`);
  if ((sell - buy) / sell > maxSpreadRatio) fail(`${what}: chênh lệch mua/bán bất thường`);
  return { buy, sell };
}

// ---- USD giữa thị trường ----

/** fawazahmed0 currency-api: {"date":"2026-11-07","usd":{"vnd":25618.18,...}} */
export function parseFawaz(json) {
  const rate = json?.usd?.vnd;
  inRange(rate, ...USD_VND, "USD/VND");
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(json.date ?? "");
  if (!m) fail("thiếu ngày");
  return { rate, time: { ms: Date.UTC(+m[1], +m[2] - 1, +m[3]), dateOnly: true } };
}

/** Coinbase public exchange-rates: {"data":{"currency":"USD","rates":{"VND":"25633.23",...}}} */
export function parseCoinbaseRates(json, nowMs) {
  if (json?.data?.currency !== "USD") fail("sai đồng gốc");
  const rate = Number(json.data.rates?.VND);
  inRange(rate, ...USD_VND, "USD/VND");
  return { rate, time: { ms: nowMs } };
}

// ---- USD tự do ----

/** tygiausd.org trang chủ: hàng "USD chợ đen" với 2 ô <td>mua</td><td>bán</td>. */
export function parseTygiausd(html, nowMs) {
  const i = html.indexOf("USD chợ đen</h3>");
  if (i < 0) fail("không thấy hàng USD chợ đen");
  const cells = [...html.slice(i, i + 600).matchAll(/<td class="text-right">\s*([\d.,]+)/g)].map((m) => digitsInt(m[1]));
  if (cells.length < 2) fail("thiếu ô mua/bán");
  return { ...checkBuySell(cells[0], cells[1], USD_VND, 0.05, "USD tự do"), time: { ms: nowMs } };
}

/** chogia.vn/ngoai-te/usd-cho-den/: câu "đang được mua vào là <span class="price ">25.855</span> và bán ra là <span ...>25.955</span>" */
export function parseChogia(html, nowMs) {
  const m = /mua vào là\s*<span[^>]*>\s*([\d.,]+)\s*<\/span>\s*và bán ra là\s*<span[^>]*>\s*([\d.,]+)/.exec(html);
  if (!m) fail("không thấy câu mua/bán");
  return { ...checkBuySell(digitsInt(m[1]), digitsInt(m[2]), USD_VND, 0.05, "USD tự do"), time: { ms: nowMs } };
}

// ---- Vàng (VND/lượng) ----

/**
 * PNJ edge-api (JSON của chính trang pnj.com.vn): giá theo NGHÌN ĐỒNG / CHỈ.
 * {"updateDate":"07/11/2026 12:29:16","data":[{"masp":"SJC","giaban":14100,"giamua":13800},{"masp":"N24K",...}]}
 * 1 lượng = 10 chỉ ⇒ đồng/lượng = giá × 1000 × 10.
 */
export function parsePnj(json) {
  const rows = Array.isArray(json?.data) ? json.data : fail("thiếu data");
  const perLuong = (row, what) => {
    const buy = Number(row.giamua) * 10_000, sell = Number(row.giaban) * 10_000;
    return checkBuySell(buy, sell, GOLD_VND_PER_LUONG, 0.15, what);
  };
  const bar = rows.find((r) => r.masp === "SJC") ?? rows.find((r) => /miếng SJC/i.test(r.tensp ?? ""));
  if (!bar) fail("không thấy vàng miếng SJC");
  const ring = rows.find((r) => r.masp === "N24K") ?? rows.find((r) => /^Nhẫn.*999\.?9/i.test(r.tensp ?? ""));
  const t = /^(\d{1,2})\/(\d{1,2})\/(\d{4}) (\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(json.updateDate ?? "");
  if (!t) fail("thiếu updateDate");
  let ringVal = null;
  try { ringVal = ring ? perLuong(ring, "nhẫn") : null; } catch { ringVal = null; } // nhẫn hỏng thì vẫn trả vàng miếng
  return {
    bar: perLuong(bar, "SJC"),
    ring: ringVal,
    ringBrand: "PNJ",
    time: { ms: vnDateTimeToMs(t[1], t[2], t[3], t[4], t[5], t[6] ?? 0) },
  };
}

/**
 * giavang.org trang chủ (bảng giá SJC): "Cập nhật lúc 09:05:22 08/11/2026", khối "Giá vàng Miếng SJC" và
 * "Giá vàng Nhẫn SJC", mỗi khối 2 ô <span class="gold-price">138.000 <small class="gold-unit">x1000đ/lượng</small>.
 */
export function parseGiavangOrg(html) {
  const t = /Cập nhật lúc (\d{1,2}):(\d{2})(?::(\d{2}))? (\d{1,2})\/(\d{1,2})\/(\d{4})/.exec(html);
  if (!t) fail("thiếu giờ cập nhật");
  const block = (title, what) => {
    const i = html.indexOf(`>${title}</a></h2>`);
    if (i < 0) fail(`không thấy khối ${title}`);
    const cells = [...html.slice(i, i + 2500).matchAll(/class="gold-price">\s*([\d.,]+)\s*<small class="gold-unit">([^<]*)</g)];
    if (cells.length < 2) fail(`${title}: thiếu ô giá`);
    const mult = (unit) => {
      if (/x\s*1000\s*đ\s*\/\s*lượng/i.test(unit)) return 1000;
      if (/x\s*1000\s*đ\s*\/\s*chỉ/i.test(unit)) return 10_000;
      fail(`đơn vị lạ: ${unit}`);
    };
    return checkBuySell(digitsInt(cells[0][1]) * mult(cells[0][2]), digitsInt(cells[1][1]) * mult(cells[1][2]),
      GOLD_VND_PER_LUONG, 0.15, what);
  };
  let ring = null;
  try { ring = block("Giá vàng Nhẫn SJC", "nhẫn"); } catch { ring = null; }
  return {
    bar: block("Giá vàng Miếng SJC", "SJC"),
    ring,
    ringBrand: "SJC",
    time: { ms: vnDateTimeToMs(t[4], t[5], t[6], t[1], t[2], t[3] ?? 0) },
  };
}

// ---- BTC (USD) ----

/** Coinbase Exchange public ticker: {"price":"75624.96","time":"2026-11-08T02:08:13.87Z",...} */
export function parseCoinbaseTicker(json, nowMs) {
  const usd = Number(json?.price);
  inRange(usd, ...BTC_USD, "BTC/USD");
  const ms = Date.parse(json.time);
  return { usd, time: { ms: Number.isFinite(ms) ? ms : nowMs } };
}

/** Kraken public Ticker: {"error":[],"result":{"XXBTZUSD":{"c":["75632.3","0.0002"],...}}} */
export function parseKraken(json, nowMs) {
  if (json?.error?.length) fail(`kraken: ${json.error.join(",")}`);
  const r = json?.result && Object.values(json.result)[0];
  const usd = Number(r?.c?.[0]);
  inRange(usd, ...BTC_USD, "BTC/USD");
  return { usd, time: { ms: nowMs } };
}
