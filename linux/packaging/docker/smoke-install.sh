#!/bin/bash
# Chạy TRONG container Ubuntu sạch: cài mọi .deb trong /debs + fcitx5 + ibus, kiểm IM nạp được.
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq /debs/*.deb fcitx5 ibus python3-gi dbus >/tmp/apt.log 2>&1 \
  || { tail -20 /tmp/apt.log; echo "SMOKE FAIL: apt"; exit 1; }
export HOME=/tmp/h; mkdir -p "$HOME"
dbus-run-session -- bash -c '
  fail=0
  fcitx5 --disable=wayland,xim,x11 >/tmp/f.log 2>&1 & sleep 4
  python3 - <<PY || fail=1
import sys
from gi.repository import Gio
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
p = Gio.DBusProxy.new_sync(bus, 0, None, "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1", None)
ims = [i[0] for i in p.call_sync("AvailableInputMethods", None, 0, 3000, None).unpack()[0]]
print("fcitx5:", "viettelex" in ims and "viettelex OK" or "viettelex MISSING")
sys.exit(0 if "viettelex" in ims else 1)
PY
  ibus-daemon -x -r --panel=disable >/tmp/i.log 2>&1 & sleep 5
  if ibus list-engine 2>/dev/null | grep -q "viettelex -"; then echo "ibus: viettelex OK"; else echo "ibus: viettelex MISSING"; fail=1; fi
  [ $fail = 0 ] && echo "SMOKE OK" || echo "SMOKE FAIL"'
