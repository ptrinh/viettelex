// Key = path without the leading "/download/" (e.g. "windows/1.3.5/VietTelex-1.3.5-x64.msi").
// Not in R2 -> pass through to GitHub Pages, so nothing breaks before a file is uploaded.
export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") return fetch(request);
    const url = new URL(request.url);
    const key = decodeURIComponent(url.pathname.replace(/^\/download\//, ""));

    const obj = request.method === "HEAD"
      ? await env.FILES.head(key)
      : await env.FILES.get(key, { range: request.headers, onlyIf: request.headers });
    if (obj === null) return fetch(request);

    const headers = new Headers();
    obj.writeHttpMetadata(headers);
    headers.set("etag", obj.httpEtag);
    headers.set("accept-ranges", "bytes");
    headers.set("cache-control", "public, max-age=3600");
    headers.set("content-type", "application/x-msi");

    // onlyIf failed (If-None-Match / If-Modified-Since matched): R2 returns metadata only.
    if (request.method === "GET" && !("body" in obj)) return new Response(null, { status: 304, headers });

    const range = obj.range;
    if (request.method === "GET" && range && request.headers.has("range")) {
      const start = range.offset ?? obj.size - range.suffix;
      const length = range.length ?? obj.size - start;
      headers.set("content-range", `bytes ${start}-${start + length - 1}/${obj.size}`);
      headers.set("content-length", String(length));
      return new Response(obj.body, { status: 206, headers, encodeBody: "manual" });
    }
    headers.set("content-length", String(obj.size));
    return new Response(request.method === "HEAD" ? null : obj.body, { status: 200, headers, encodeBody: "manual" });
  },
};
