#!/usr/bin/env python3
"""Tóm tắt signpost bàn phím từ một bản ghi xctrace (iOS/docs/KEYBOARD-STARTUP.md).

    xcrun xctrace record --device <UDID> --instrument os_signpost --all-processes \
        --time-limit 60s --output kb.trace
    xcrun xctrace export --input kb.trace \
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' > kb.xml
    python3 iOS/Scripts/signpost-summary.py kb.xml [--process VietTelexKeyboard] [--list]

Ghép Begin/End theo (tiến trình, tên, identifier) — bảng `os-signpost` (sự kiện thô) có ở mọi
bản Instruments; bảng khoảng tổng hợp thì đổi tên theo phiên bản. In: số lần, trung vị, P90, max
(ms) theo tên khoảng; `appear` tách theo thông điệp mở (cold / warm / reshow). `--list` in
từng khoảng `appear` theo thời gian (kèm mốc `height`).
"""
import sys
import xml.etree.ElementTree as ET

FIELDS = ("time", "thread", "process", "event-type", "scope", "identifier", "name",
          "format-string", "backtrace", "subsystem", "category", "message")


def rows(path):
    ids = {}
    tree = ET.parse(path)
    for node in tree.getroot().iter("node"):
        for row in node.iter("row"):
            vals = []
            for el in row:
                if "ref" in el.attrib:
                    el = ids.get(el.attrib["ref"], el)
                elif "id" in el.attrib:
                    ids[el.attrib["id"]] = el
                    for sub in el.iter():
                        if "id" in sub.attrib:
                            ids[sub.attrib["id"]] = sub
                if el.tag == "sentinel":
                    vals.append(None)
                elif el.tag == "event-time":
                    vals.append(int(el.text))
                else:
                    vals.append(el.attrib.get("fmt", el.text))
            yield dict(zip(FIELDS, vals))


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p * (len(xs) - 1))))]


def main():
    args = sys.argv[1:]
    sub = "com.viettelex.ios.keyboard"
    if "--subsystem" in args:
        i = args.index("--subsystem"); sub = args[i + 1]; del args[i:i + 2]
    proc = None   # chuỗi con của tên tiến trình (vd "VietTelexKeyboard" — bỏ tiến trình test)
    if "--process" in args:
        i = args.index("--process"); proc = args[i + 1]; del args[i:i + 2]
    listing = "--list" in args
    args = [a for a in args if a != "--list"]
    open_ = {}
    out = {}
    timeline = []
    seen = set()   # bản ghi có thể chứa cùng một sự kiện hai lần (khác scope) — bỏ trùng
    for r in rows(args[0]):
        if r.get("subsystem") != sub or (proc and proc not in (r.get("process") or "")):
            continue
        dedup = (r["time"], r["process"], r["name"], r["identifier"], r["event-type"])
        if dedup in seen:
            continue
        seen.add(dedup)
        key = (r["process"], r["name"], r["identifier"])
        et = r["event-type"]
        if et == "Begin":
            open_[key] = r
        elif et == "End" and key in open_:
            b = open_.pop(key)
            ms = (r["time"] - b["time"]) / 1e6
            name = r["name"]
            if name == "appear":
                name = "appear " + (b.get("message") or "").strip()
            out.setdefault(name, []).append(ms)
            if r["name"] == "appear":
                timeline.append((b["time"], f"appear {(b.get('message') or '').strip():7s} {ms:7.1f} ms  pid {b['process']}"))
        elif et == "Event" and r["name"] == "height":
            timeline.append((r["time"], f"  height {(r.get('message') or '').strip()}"))
    print(f"{'khoảng':28s} {'n':>4s} {'trung vị':>9s} {'P90':>8s} {'max':>8s}  (ms)")
    for name in sorted(out):
        xs = out[name]
        print(f"{name:28s} {len(xs):4d} {pct(xs, .5):9.1f} {pct(xs, .9):8.1f} {max(xs):8.1f}")
    if listing:
        for _, s in sorted(timeline):
            print(s)


if __name__ == "__main__":
    main()
