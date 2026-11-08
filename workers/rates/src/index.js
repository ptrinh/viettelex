// viettelex.com/api/{usd,usd-tudo,vang,btc} — một dòng chữ thuần cho "mẫu câu động" của bàn phím di động
// (bàn phím GET lúc chạm, chèn nguyên body, tối đa 1000 byte). Nguồn + điều khoản: README.md.
//
// Lỗi LUÔN trả 200 + câu báo ngắn: Android (HttpURLConnection) ném lỗi với mã ≥ 400 rồi chèn chính URL,
// iOS chèn body bất kể mã — chỉ 200 mới cho cả hai chèn câu báo thân thiện.

import * as P from "./parse.js";
import { usdLine, tudoLine, vangLine, btcLine, ERRORS } from "./format.js";

const UA = "VietTelexRates/1.0 (+https://viettelex.com)";
const SOURCE_TIMEOUT_MS = 3000; // mỗi nguồn
const HEDGE_MS = 1200;          // nguồn sau bắt đầu nếu nguồn trước chưa xong sau chừng này
const DEADLINE_MS = 3500;       // bàn phím chờ 4 s; phải kịp trả câu báo lỗi trước đó

const json = (r) => r.json();
const text = (r) => r.text();

/** key → { ttl (độ tươi), stale (dùng tạm khi mọi nguồn lỗi), sources theo thứ tự ưu tiên } */
export const FEEDS = {
  usd: {
    ttl: 3600, stale: 48 * 3600,
    sources: [
      { name: "currency-api/jsdelivr", url: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json", read: json, parse: (b) => P.parseFawaz(b) },
      { name: "currency-api/pages.dev", url: "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json", read: json, parse: (b) => P.parseFawaz(b) },
      { name: "coinbase/exchange-rates", url: "https://api.coinbase.com/v2/exchange-rates?currency=USD", read: json, parse: (b, now) => P.parseCoinbaseRates(b, now) },
    ],
  },
  "usd-tudo": {
    ttl: 600, stale: 12 * 3600,
    sources: [
      { name: "tygiausd.org", url: "https://tygiausd.org/", read: text, parse: (b, now) => P.parseTygiausd(b, now) },
      { name: "chogia.vn", url: "https://chogia.vn/ngoai-te/usd-cho-den/", read: text, parse: (b, now) => P.parseChogia(b, now) },
    ],
  },
  vang: {
    ttl: 600, stale: 12 * 3600,
    sources: [
      { name: "pnj", url: "https://edge-api.pnj.io/ecom-frontend/v1/get-gold-price?zone=00", read: json, parse: (b) => P.parsePnj(b) },
      { name: "giavang.org", url: "https://giavang.org/", read: text, parse: (b) => P.parseGiavangOrg(b) },
    ],
  },
  btc: {
    ttl: 90, stale: 1800,
    sources: [
      { name: "coinbase/ticker", url: "https://api.exchange.coinbase.com/products/BTC-USD/ticker", read: json, parse: (b, now) => P.parseCoinbaseTicker(b, now) },
      { name: "kraken", url: "https://api.kraken.com/0/public/Ticker?pair=XBTUSD", read: json, parse: (b, now) => P.parseKraken(b, now) },
    ],
  },
};

async function trySource(src, fetchImpl, now) {
  const res = await fetchImpl(src.url, {
    headers: { "user-agent": UA, accept: "application/json,text/html;q=0.9,*/*;q=0.5" },
    signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS),
    cf: { cacheTtl: 0 },
  });
  if (!res.ok) throw new Error(`${src.name}: HTTP ${res.status}`);
  return { data: src.parse(await src.read(res), now()), source: src.name };
}

/**
 * Hỏi các nguồn theo thứ tự ưu tiên, kiểu "hedge": nguồn sau khởi động khi nguồn trước lỗi hoặc đã chờ
 * quá HEDGE_MS. Kết quả hợp lệ đầu tiên thắng; nguồn ưu tiên có lợi thế đi trước. Hết DEADLINE_MS ⇒ null.
 */
export function firstValid(sources, { fetchImpl = fetch, now = Date.now, hedgeMs = HEDGE_MS, deadlineMs = DEADLINE_MS, log = () => {} } = {}) {
  return new Promise((resolve) => {
    let done = false, next = 0, pending = 0, hedgeTimer = null;
    const finish = (v) => { if (done) return; done = true; clearTimeout(hedgeTimer); clearTimeout(deadline); resolve(v); };
    const deadline = setTimeout(() => finish(null), deadlineMs);
    const launch = () => {
      if (done || next >= sources.length) return;
      const src = sources[next++];
      pending++;
      clearTimeout(hedgeTimer);
      hedgeTimer = setTimeout(launch, hedgeMs);
      trySource(src, fetchImpl, now).then(finish, (e) => {
        log(`${src.name}: ${e?.message ?? e}`);
        pending--;
        if (next < sources.length) launch();
        else if (pending === 0) finish(null);
      });
    };
    launch();
  });
}

const cacheKey = (key) => `https://viettelex.com/__rates-cache/v1/${key}`;

/** Lấy dữ liệu một feed: cache tươi → nguồn → cache cũ (≤ stale) → null. */
export async function getFeed(key, { ctx, cache = globalThis.caches?.default, fetchImpl = fetch, now = Date.now } = {}) {
  const feed = FEEDS[key];
  let cached = null;
  try {
    const hit = cache && (await cache.match(cacheKey(key)));
    if (hit) cached = await hit.json();
  } catch { cached = null; }
  const age = cached ? (now() - cached.fetchedAt) / 1000 : Infinity;
  if (cached && age < feed.ttl) return { ...cached, cache: "hit" };

  const got = await firstValid(feed.sources, { fetchImpl, now, log: (m) => console.warn(`[${key}] ${m}`) });
  if (got) {
    const entry = { data: got.data, source: got.source, fetchedAt: now() };
    if (cache) {
      const put = cache.put(cacheKey(key), new Response(JSON.stringify(entry), {
        headers: { "content-type": "application/json", "cache-control": `public, max-age=${feed.stale}` },
      })).catch(() => {});
      ctx?.waitUntil ? ctx.waitUntil(put) : await put;
    }
    return { ...entry, cache: "miss" };
  }
  if (cached && age < feed.stale) return { ...cached, cache: "stale" };
  return null;
}

function reply(body, { status = 200, maxAge = 0, extra = {} } = {}) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "access-control-allow-origin": "*",
      "cache-control": maxAge > 0 ? `public, max-age=${maxAge}` : "no-store",
      "x-content-type-options": "nosniff",
      ...extra,
    },
  });
}

export async function handle(request, ctx, deps = {}) {
  const url = new URL(request.url);
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "GET, HEAD, OPTIONS", "access-control-max-age": "86400" } });
  }
  if (request.method !== "GET" && request.method !== "HEAD") return reply("Method not allowed", { status: 405 });

  const key = url.pathname.replace(/^\/api\//, "").replace(/\/+$/, "");
  if (!FEEDS[key]) return reply("Not found", { status: 404 });
  const en = ["1", "true", "yes"].includes(url.searchParams.get("en") ?? "");

  let line = null, meta = {};
  try {
    const main = await getFeed(key, { ctx, ...deps });
    if (main) {
      meta = { "x-rates-source": main.source, "x-rates-cache": main.cache };
      if (key === "usd") line = usdLine(main.data, en);
      else if (key === "usd-tudo") line = tudoLine(main.data, en);
      else if (key === "vang") line = vangLine(main.data, en);
      else if (key === "btc") {
        const fx = await getFeed("usd", { ctx, ...deps });
        if (fx) {
          line = btcLine(main.data, fx.data.rate, en);
          meta["x-rates-source"] += ` × ${fx.source}`;
        }
      }
    }
  } catch (e) {
    console.error(`[${key}] ${e?.stack ?? e}`);
    line = null;
  }
  if (!line) return reply(ERRORS[key][en ? 1 : 0], { extra: { "x-rates-error": "1" } });
  const body = new TextEncoder().encode(line).length <= 1000 ? line : line.slice(0, 300);
  return reply(request.method === "HEAD" ? null : body, { maxAge: 60, extra: meta });
}

export default {
  fetch: (request, env, ctx) => handle(request, ctx),
};
