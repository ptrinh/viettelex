// Dựng dòng chữ trả về cho bàn phím. Tiếng Việt: chấm phân cách nghìn, phẩy thập phân, giờ Việt Nam.
// en = true: dạng tiếng Anh (phẩy nghìn, chấm thập phân).

const VN_OFFSET_MS = 7 * 3600 * 1000;
const pad = (n) => String(n).padStart(2, "0");

export function fmtInt(n, en = false) {
  const s = String(Math.round(Math.abs(n))).replace(/\B(?=(\d{3})+(?!\d))/g, en ? "," : ".");
  return n < 0 ? "-" + s : s;
}

/** Số thập phân: ít nhất `min`, nhiều nhất `max` chữ số sau dấu phẩy (bỏ số 0 thừa phía sau). */
export function fmtDec(n, min = 1, max = 2, en = false) {
  let [i, f = ""] = n.toFixed(max).split(".");
  f = f.replace(/0+$/, "");
  while (f.length < min) f += "0";
  const int = fmtInt(Number(i), en);
  return f ? `${int}${en ? "." : ","}${f}` : int;
}

/** { ms, dateOnly } → "14:05 08/11/2026" (giờ Việt Nam) hoặc "ngày 08/11/2026". */
export function fmtTime(time, en = false) {
  if (time.dateOnly) {
    const d = new Date(time.ms);
    const ds = `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
    return en ? ds : `ngày ${ds}`;
  }
  const d = new Date(time.ms + VN_OFFSET_MS);
  const s = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())} ${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
  return en ? `${s} GMT+7` : s;
}

export function usdLine({ rate, time }, en = false) {
  return en
    ? `1 USD = ${fmtInt(rate, true)} VND (mid-market, ${fmtTime(time, true)})`
    : `1 USD = ${fmtInt(rate)} ₫ (giá giữa thị trường, ${fmtTime(time)})`;
}

export function tudoLine({ buy, sell, time }, en = false) {
  return en
    ? `USD free market (Vietnam): buy ${fmtInt(buy, true)} – sell ${fmtInt(sell, true)} VND (${fmtTime(time, true)})`
    : `USD tự do: mua ${fmtInt(buy)} ₫ – bán ${fmtInt(sell)} ₫ (${fmtTime(time)})`;
}

const trieu = (vnd, en) => fmtDec(vnd / 1_000_000, 1, 2, en);

export function vangLine({ bar, ring, ringBrand, time }, en = false) {
  if (en) {
    let s = `SJC gold bar: buy ${trieu(bar.buy, true)} – sell ${trieu(bar.sell, true)} million VND/tael`;
    if (ring) s += ` · 9999 ring (${ringBrand}): buy ${trieu(ring.buy, true)} – sell ${trieu(ring.sell, true)} million VND/tael`;
    return `${s} (${fmtTime(time, true)})`;
  }
  let s = `Vàng SJC: mua ${trieu(bar.buy)} – bán ${trieu(bar.sell)} triệu/lượng`;
  if (ring) s += ` · Nhẫn 9999 ${ringBrand}: mua ${trieu(ring.buy)} – bán ${trieu(ring.sell)} triệu/lượng`;
  return `${s} (${fmtTime(time)})`;
}

/** BTC: giá USD × tỷ giá giữa thị trường; VND làm tròn tới nghìn đồng. */
export function btcLine({ usd, time }, usdVnd, en = false) {
  const vnd = Math.round((usd * usdVnd) / 1000) * 1000;
  return en
    ? `1 BTC = ${fmtInt(vnd, true)} VND (≈ ${fmtInt(usd, true)} USD, ${fmtTime(time, true)})`
    : `1 BTC = ${fmtInt(vnd)} ₫ (≈ ${fmtInt(usd)} USD, ${fmtTime(time)})`;
}

export const ERRORS = {
  usd: ["Chưa lấy được tỷ giá, thử lại sau.", "Exchange rate unavailable, try again later."],
  "usd-tudo": ["Chưa lấy được tỷ giá, thử lại sau.", "Exchange rate unavailable, try again later."],
  vang: ["Chưa lấy được giá vàng, thử lại sau.", "Gold price unavailable, try again later."],
  btc: ["Chưa lấy được giá BTC, thử lại sau.", "BTC price unavailable, try again later."],
};
