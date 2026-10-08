// Trang tải (vi + en dùng chung). Không thư viện ngoài.
// - Tab nền tảng: tự chọn theo máy; ép bằng ?os=linux hoặc #linux (tên cũ #mac/#win vẫn nhận).
// - Phiên bản + link lấy từ /stable.json; lỗi mạng → nút giữ link trang Releases.
(function () {
  "use strict";
  var EN = document.documentElement.lang === "en";
  var S = EN ? {
    copy: "Copy", copied: "Copied ✓", auto: "Picked for your device: %s.",
    latest: "latest", none: "Could not load the list — see GitHub Releases.",
    names: { ios: "iPhone & iPad", android: "Android", macos: "macOS", windows: "Windows", linux: "Linux", web: "Web" },
    series: { jammy: "Ubuntu 22.04 (jammy)", noble: "Ubuntu 24.04 (noble)", resolute: "Ubuntu 26.04 (resolute)",
      bookworm: "Debian 12 (bookworm)", trixie: "Debian 13 (trixie)" }
  } : {
    copy: "Chép", copied: "Đã chép ✓", auto: "Tự chọn theo máy bạn: %s.",
    latest: "mới nhất", none: "Không tải được danh sách — xem GitHub Releases.",
    names: { ios: "iPhone & iPad", android: "Android", macos: "macOS", windows: "Windows", linux: "Linux", web: "Web" },
    series: { jammy: "Ubuntu 22.04 (jammy)", noble: "Ubuntu 24.04 (noble)", resolute: "Ubuntu 26.04 (resolute)",
      bookworm: "Debian 12 (bookworm)", trixie: "Debian 13 (trixie)" }
  };
  var OS = ["ios", "android", "macos", "windows", "linux", "web"];
  var ALIAS = { mac: "macos", osx: "macos", darwin: "macos", win: "windows", win32: "windows",
    iphone: "ios", ipad: "ios", ipados: "ios", ubuntu: "linux", deb: "linux",
    chromeos: "android", chromebook: "android", learn: "web", sdk: "web", js: "web", npm: "web" };
  function norm(v) {
    v = String(v || "").toLowerCase().replace(/^#/, "");
    v = ALIAS[v] || v;
    return OS.indexOf(v) >= 0 ? v : null;
  }
  function detect() {
    var uad = navigator.userAgentData;
    var s = ((uad && uad.platform) || navigator.platform || "") + " " + (navigator.userAgent || "");
    if (/iPhone|iPad|iPod/i.test(s)) return "ios";
    if (/Mac/i.test(s) && navigator.maxTouchPoints > 1) return "ios"; // iPadOS báo là Mac
    if (/Android|CrOS|Chrome OS/i.test(s)) return "android";         // Chromebook chạy app Android
    if (/Mac/i.test(s)) return "macos";
    if (/Win/i.test(s)) return "windows";
    if (/Linux|X11|BSD/i.test(s)) return "linux";
    return "macos";
  }

  // --- tab ---------------------------------------------------------------------
  var tabs = [].slice.call(document.querySelectorAll('[role="tab"]'));
  var note = document.getElementById("autonote");
  function select(os, opts) {
    opts = opts || {};
    tabs.forEach(function (t) {
      var on = t.getAttribute("data-os") === os;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      var p = document.getElementById(t.getAttribute("aria-controls"));
      if (p) p.hidden = !on;
      if (on && opts.focus) t.focus();
    });
    if (note) note.textContent = opts.auto ? S.auto.replace("%s", S.names[os]) : "";
    if (opts.url) {
      try { history.replaceState(null, "", location.pathname + "?os=" + os); } catch (e) {}
    }
  }
  tabs.forEach(function (t, i) {
    t.addEventListener("click", function () { select(t.getAttribute("data-os"), { url: true }); });
    t.addEventListener("keydown", function (e) {
      var k = e.key, j = -1;
      if (k === "ArrowDown" || k === "ArrowRight") j = (i + 1) % tabs.length;
      else if (k === "ArrowUp" || k === "ArrowLeft") j = (i - 1 + tabs.length) % tabs.length;
      else if (k === "Home") j = 0;
      else if (k === "End") j = tabs.length - 1;
      if (j < 0) return;
      e.preventDefault();
      select(tabs[j].getAttribute("data-os"), { focus: true, url: true });
    });
  });
  var q = null;
  try { q = new URLSearchParams(location.search).get("os"); } catch (e) {}
  var forced = norm(q) || norm(location.hash);
  select(forced || detect(), { auto: !forced });

  // --- chép lệnh -------------------------------------------------------------------
  function copyText(text, done) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { legacy(text); done(); });
    } else { legacy(text); done(); }
  }
  function legacy(text) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta);
  }
  document.querySelectorAll("[data-copy]").forEach(function (b) {
    b.addEventListener("click", function () {
      var v = b.getAttribute("data-copy");
      var text = v.charAt(0) === "#" ? (document.querySelector(v) || {}).textContent || "" : v;
      copyText(text, function () {
        b.textContent = S.copied;
        setTimeout(function () { b.textContent = S.copy; }, 1800);
      });
    });
  });

  // --- Windows ARM: đưa nút ARM64 lên trước ------------------------------------
  function preferArm() {
    var a = document.getElementById("winX64"), b = document.getElementById("winArm");
    if (!a || !b) return;
    // Cả hai là nút phụ (Microsoft Store là cách chính) — chỉ đổi thứ tự.
    a.parentNode.insertBefore(b, a);
  }
  try {
    var uad = navigator.userAgentData;
    if (uad && uad.getHighEntropyValues && /Win/i.test(uad.platform || "")) {
      uad.getHighEntropyValues(["architecture"]).then(function (v) { if (v.architecture === "arm") preferArm(); }, function () {});
    } else if (/Windows.*ARM/i.test(navigator.userAgent || "")) preferArm();
  } catch (e) {}

  // --- phiên bản + link theo stable.json -------------------------------------------------
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function setText(sel, v) { document.querySelectorAll(sel).forEach(function (el) { el.textContent = v; }); }
  function link(id, href, text) { var a = document.getElementById(id); if (!a) return; if (href) a.href = href; if (text) a.querySelector(".lbl").textContent = text; }
  function fail() {
    setText("[data-ver]", S.latest);
    var box = document.getElementById("debs");
    if (box) box.innerHTML = '<p class="note">' + esc(S.none) + "</p>";
  }
  fetch("/stable.json", { cache: "no-cache" }).then(function (r) {
    if (!r.ok) throw new Error(r.status);
    return r.json();
  }).then(function (d) {
    if (d.version) {
      setText('[data-ver="mac"]', d.version);
      link("macPkg", "https://github.com/ptrinh/viettelex/releases/download/v" + d.version + "/VietTelex-" + d.version + ".pkg",
        (EN ? "Download VietTelex-" : "Tải VietTelex-") + d.version + ".pkg");
    } else setText('[data-ver="mac"]', S.latest);

    var w = d.windows || {};
    setText('[data-ver="win"]', w.version || S.latest);
    if (w.x64) link("winX64", w.x64, (EN ? "Download " : "Tải ") + w.version + " · x64 (.msi)");
    if (w.arm64) link("winArm", w.arm64, (EN ? "Download " : "Tải ") + w.version + " · ARM64 (.msi)");
    if (w.notes && !EN) setText("#winNotes", w.notes);

    // Android: huy hiệu Google Play đã viết sẵn trong HTML; stable.json.android {version, apk} (nếu có) cập nhật nút APK.
    var an = d.android;
    if (an && an.apk) { link("apkBtn", an.apk, (EN ? "Download APK " : "Tải APK ") + (an.version || "")); setText('[data-ver="android"]', an.version || S.latest); }
    var l = d.linux, box = document.getElementById("debs");
    setText('[data-ver="linux"]', (l && l.version) || S.latest);
    if (l && l.notes && !EN) setText("#linuxNotes", l.notes);
    if (!box) return;
    if (!l || !l.sha256 || !l.download) { box.innerHTML = '<p class="note">' + esc(S.none) + "</p>"; return; }
    var groups = {};
    Object.keys(l.sha256).sort().forEach(function (n) {
      var m = n.match(/\.([a-z]+)1_(amd64|arm64|all)\.deb$/); if (!m) return;
      var arches = m[2] === "all" ? ["amd64", "arm64"] : [m[2]];
      arches.forEach(function (a) { var k = m[1] + " · " + a; (groups[k] = groups[k] || []).push(n); });
    });
    var html = "";
    Object.keys(groups).sort().forEach(function (k) {
      var parts = k.split(" · ");
      html += '<div class="tablewrap"><table><tr><th>' + esc((S.series[parts[0]] || parts[0]) + " · " + parts[1]) + " — " + esc(l.version) + "</th><th>SHA256</th></tr>";
      groups[k].forEach(function (n) {
        html += '<tr><td><a href="' + esc(l.download + n) + '" rel="noopener">' + esc(n) + '</a></td><td class="sha">' + esc(l.sha256[n]) + "</td></tr>";
      });
      html += "</table></div>";
    });
    box.innerHTML = html;
  }).catch(fail);
})();
