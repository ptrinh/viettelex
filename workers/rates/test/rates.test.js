import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as P from "../src/parse.js";
import { fmtInt, fmtDec, fmtTime, usdLine, tudoLine, vangLine, btcLine } from "../src/format.js";
import { firstValid, handle } from "../src/index.js";

const fx = (f) => readFileSync(new URL(`./fixtures/${f}`, import.meta.url), "utf8");
const NOW = Date.UTC(2026, 10, 8, 7, 5); // 14:05 08/11/2026 giờ VN

// ---- định dạng ----

test("số kiểu Việt và kiểu Anh", () => {
  assert.equal(fmtInt(26312.4), "26.312");
  assert.equal(fmtInt(2345678900), "2.345.678.900");
  assert.equal(fmtInt(26312.4, true), "26,312");
  assert.equal(fmtDec(148.5), "148,5");
  assert.equal(fmtDec(150), "150,0");
  assert.equal(fmtDec(136.35), "136,35");
  assert.equal(fmtDec(1234.5, 1, 2, true), "1,234.5");
});

test("giờ Việt Nam", () => {
  assert.equal(fmtTime({ ms: NOW }), "14:05 08/11/2026");
  assert.equal(fmtTime({ ms: Date.UTC(2026, 10, 7), dateOnly: true }), "ngày 07/11/2026");
  // 23:30 UTC = 06:30 hôm sau ở VN
  assert.equal(fmtTime({ ms: Date.UTC(2026, 11, 31, 23, 30) }), "06:30 01/01/2027");
});

// ---- USD giữa thị trường ----

test("fawaz currency-api", () => {
  const d = P.parseFawaz({ date: "2026-11-07", usd: { vnd: 25618.18536598, eur: 0.86 } });
  assert.equal(usdLine(d), "1 USD = 25.618 ₫ (giá giữa thị trường, ngày 07/11/2026)");
  assert.throws(() => P.parseFawaz({ date: "2026-11-07", usd: { vnd: 0.00004 } }), P.ParseError);
  assert.throws(() => P.parseFawaz({ date: "2026-11-07", usd: {} }), P.ParseError);
});

test("coinbase exchange-rates", () => {
  const d = P.parseCoinbaseRates({ data: { currency: "USD", rates: { VND: "25633.233113" } } }, NOW);
  assert.equal(usdLine(d), "1 USD = 25.633 ₫ (giá giữa thị trường, 14:05 08/11/2026)");
  assert.throws(() => P.parseCoinbaseRates({ data: { currency: "EUR", rates: { VND: "27000" } } }, NOW));
});

// ---- USD tự do ----

test("tygiausd.org", () => {
  const d = P.parseTygiausd(fx("tygiausd.html"), NOW);
  assert.deepEqual([d.buy, d.sell], [25900, 25950]);
  assert.equal(tudoLine(d), "USD tự do: mua 25.900 ₫ – bán 25.950 ₫ (14:05 08/11/2026)");
});

test("chogia.vn", () => {
  const d = P.parseChogia(fx("chogia-usd.html"), NOW);
  assert.deepEqual([d.buy, d.sell], [25855, 25955]);
});

test("USD tự do: số rác bị chặn", () => {
  const html = fx("tygiausd.html");
  assert.throws(() => P.parseTygiausd(html.replace("25,900", "259"), NOW), P.ParseError);          // ngoài khoảng
  assert.throws(() => P.parseTygiausd(html.replace("25,950", "25,000"), NOW), P.ParseError);       // mua > bán
  assert.throws(() => P.parseTygiausd("<html>đổi giao diện</html>", NOW), P.ParseError);
  assert.throws(() => P.parseChogia("không có gì", NOW), P.ParseError);
});

// ---- Vàng ----

test("PNJ: nghìn đồng/chỉ → triệu/lượng", () => {
  const d = P.parsePnj(JSON.parse(fx("pnj.json")));
  assert.deepEqual(d.bar, { buy: 138_000_000, sell: 141_000_000 });
  assert.deepEqual(d.ring, { buy: 136_300_000, sell: 140_300_000 });
  assert.equal(vangLine(d),
    "Vàng SJC: mua 138,0 – bán 141,0 triệu/lượng · Nhẫn 9999 PNJ: mua 136,3 – bán 140,3 triệu/lượng (12:29 07/11/2026)");
});

test("PNJ: thiếu nhẫn vẫn trả vàng miếng; đơn vị lạ bị chặn", () => {
  const j = JSON.parse(fx("pnj.json"));
  j.data = j.data.filter((r) => r.masp === "SJC");
  const d = P.parsePnj(j);
  assert.equal(d.ring, null);
  assert.equal(vangLine(d), "Vàng SJC: mua 138,0 – bán 141,0 triệu/lượng (12:29 07/11/2026)");
  // nếu PNJ đổi sang đồng/lượng (138000000) ⇒ ×10000 vượt khoảng ⇒ lỗi, không chèn số sai
  j.data[0] = { ...j.data[0], giamua: 138_000_000, giaban: 141_000_000 };
  assert.throws(() => P.parsePnj(j), P.ParseError);
});

test("giavang.org: x1000đ/lượng", () => {
  const d = P.parseGiavangOrg(fx("giavang-org.html"));
  assert.deepEqual(d.bar, { buy: 138_000_000, sell: 141_000_000 });
  assert.deepEqual(d.ring, { buy: 136_500_000, sell: 140_500_000 });
  assert.equal(vangLine(d),
    "Vàng SJC: mua 138,0 – bán 141,0 triệu/lượng · Nhẫn 9999 SJC: mua 136,5 – bán 140,5 triệu/lượng (09:05 08/11/2026)");
  assert.equal(vangLine(d, true),
    "SJC gold bar: buy 138.0 – sell 141.0 million VND/tael · 9999 ring (SJC): buy 136.5 – sell 140.5 million VND/tael (09:05 08/11/2026 GMT+7)");
  assert.throws(() => P.parseGiavangOrg(fx("giavang-org.html").replaceAll("x1000đ/lượng", "USD/oz")), P.ParseError);
});

// ---- BTC ----

test("BTC: coinbase/kraken × USD/VND", () => {
  const c = P.parseCoinbaseTicker({ price: "75624.96", time: "2026-11-08T07:05:13.87Z" }, 0);
  assert.equal(btcLine(c, 25618.18), "1 BTC = 1.937.374.000 ₫ (≈ 75.625 USD, 14:05 08/11/2026)");
  const k = P.parseKraken({ error: [], result: { XXBTZUSD: { c: ["75632.3", "0.0002"] } } }, NOW);
  assert.equal(k.usd, 75632.3);
  assert.throws(() => P.parseKraken({ error: ["EGeneral:Too many requests"] }, NOW));
  assert.throws(() => P.parseCoinbaseTicker({ price: "0.5" }, NOW));
});

// ---- chuỗi dự phòng + HTTP ----

const ok = (body) => new Response(typeof body === "string" ? body : JSON.stringify(body));
const src = (name, parse = (b) => b) => ({ name, url: `https://x/${name}`, read: (r) => r.json(), parse });

test("firstValid: nguồn đầu lỗi ⇒ dùng nguồn sau", async () => {
  const fetchImpl = async (u) => (u.endsWith("/a") ? new Response("x", { status: 500 }) : ok({ v: 2 }));
  const got = await firstValid([src("a"), src("b")], { fetchImpl, hedgeMs: 1000, deadlineMs: 2000 });
  assert.equal(got.source, "b");
});

test("firstValid: parse lỗi cũng chuyển nguồn; tất cả lỗi ⇒ null", async () => {
  const bad = () => { throw new P.ParseError("x"); };
  const fetchImpl = async () => ok({});
  assert.equal(await firstValid([src("a", bad), src("b", bad)], { fetchImpl, hedgeMs: 1000, deadlineMs: 2000 }), null);
});

test("firstValid: nguồn đầu treo ⇒ hedge sang nguồn sau, hết hạn ⇒ null", async () => {
  const hang = () => new Promise(() => {});
  const fetchImpl = async (u) => (u.endsWith("/a") ? hang() : ok({ v: 1 }));
  const got = await firstValid([src("a"), src("b")], { fetchImpl, hedgeMs: 20, deadlineMs: 500 });
  assert.equal(got.source, "b");
  assert.equal(await firstValid([src("a")], { fetchImpl: hang, hedgeMs: 20, deadlineMs: 50 }), null);
});

test("HTTP: mọi nguồn lỗi ⇒ 200 + câu báo (Android bỏ body khi ≥400)", async () => {
  const fetchImpl = async () => new Response("down", { status: 503 });
  const res = await handle(new Request("https://viettelex.com/api/vang"), null, { fetchImpl, cache: null });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "text/plain; charset=utf-8");
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.equal(res.headers.get("cache-control"), "no-store");
  assert.equal(await res.text(), "Chưa lấy được giá vàng, thử lại sau.");
});

test("HTTP: /api/usd thành công và đường dẫn lạ ⇒ 404", async () => {
  const fetchImpl = async () => ok({ date: "2026-11-07", usd: { vnd: 25618.18 } });
  const res = await handle(new Request("https://viettelex.com/api/usd"), null, { fetchImpl, cache: null });
  assert.equal(await res.text(), "1 USD = 25.618 ₫ (giá giữa thị trường, ngày 07/11/2026)");
  assert.match(res.headers.get("cache-control"), /max-age=60/);
  const nf = await handle(new Request("https://viettelex.com/api/nope"), null, { fetchImpl, cache: null });
  assert.equal(nf.status, 404);
});

test("HTTP: /api/btc ghép giá BTC với tỷ giá", async () => {
  const fetchImpl = async (u) => u.includes("coinbase.com/products")
    ? ok({ price: "75624.96", time: "2026-11-08T07:05:13Z" })
    : ok({ date: "2026-11-07", usd: { vnd: 25618.18 } });
  const res = await handle(new Request("https://viettelex.com/api/btc"), null, { fetchImpl, cache: null });
  assert.equal(await res.text(), "1 BTC = 1.937.374.000 ₫ (≈ 75.625 USD, 14:05 08/11/2026)");
});
