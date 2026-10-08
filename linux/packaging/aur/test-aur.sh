#!/bin/bash
# Kiểm AUR viettelex-bin trong container archlinux (amd64; trên Mac Apple silicon chạy qua
# Rosetta của OrbStack): makepkg bằng user thường (tải .deb thật từ GitHub Releases, kiểm
# sha256), .SRCINFO khớp `makepkg --printsrcinfo`, namcap, cài bằng pacman, rồi Fcitx5 phải
# thấy IM viettelex, IBus thấy engine, công cụ văn bản thêm dấu được. Không đẩy gì lên AUR.
#
#   linux/packaging/aur/test-aur.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" != --inner ]; then
  exec docker run --rm --platform linux/amd64 -v "$HERE:/aur:ro" archlinux:latest bash /aur/test-aur.sh --inner
fi

FAILS=0; fail(){ echo "FAIL: $*"; FAILS=$((FAILS+1)); }
# Sandbox tải của pacman 7 cần seccomp/landlock — hỏng trong container amd64 giả lập (Rosetta).
sed -i 's/^#DisableSandboxSyscalls/DisableSandboxSyscalls/; s/^#DisableSandboxFilesystem/DisableSandboxFilesystem/' /etc/pacman.conf
pacman -Syu --noconfirm --needed base-devel namcap sudo dbus python-gobject >/tmp/pacman.log 2>&1 \
  || { tail -20 /tmp/pacman.log; exit 9; }
useradd -m builder; echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
cp -r /aur/viettelex-bin /home/builder/pkg; chown -R builder: /home/builder/pkg
cd /home/builder/pkg

echo "### .SRCINFO == makepkg --printsrcinfo"
sudo -u builder makepkg --printsrcinfo | tee /tmp/srcinfo >/dev/null
diff -u .SRCINFO /tmp/srcinfo && echo "srcinfo: OK" || fail ".SRCINFO lệch (chạy bump.py)"

echo "### makepkg -s (user thường)"
sudo -u builder makepkg -s --noconfirm 2>&1 | tee /tmp/makepkg.log >/dev/null; [ "${PIPESTATUS[0]}" = 0 ] || { tail -30 /tmp/makepkg.log; fail makepkg; exit 1; }
grep -E "Validating|Passed|FAILED" /tmp/makepkg.log | head -12
PKG=$(find . -maxdepth 1 -name "viettelex-bin-*.pkg.tar.zst" ! -name "*-debug-*" -printf "%f\n" | head -1)
echo "built: $PKG"

echo "### namcap"
namcap PKGBUILD | tee /tmp/namcap-pkgbuild
namcap "$PKG" | tee /tmp/namcap-pkg
grep -E " E: " /tmp/namcap-pkgbuild /tmp/namcap-pkg && fail "namcap error"

echo "### pacman -U (kéo fcitx5 từ depends) + ibus"
{ pacman -U --noconfirm "$PKG" && pacman -S --noconfirm --needed ibus; } >/tmp/install.log 2>&1 \
  || { tail -20 /tmp/install.log; fail "pacman -U"; }
pacman -Q fcitx5 ibus viettelex-bin
pacman -Ql viettelex-bin | grep -E "fcitx5/viettelex.so|addon/viettelex.conf|ibus-engine|libtelexcore|text-tool|bin/viettelex-settings"
test -f /usr/share/fcitx5/addon/viettelex.conf || fail "addon conf"
test -f /usr/lib/fcitx5/viettelex.so || fail "addon .so"
grep -q "<exec>/usr/lib/ibus/ibus-engine-viettelex" /usr/share/ibus/component/viettelex.xml || fail "ibus exec path"
ldd /usr/lib/fcitx5/viettelex.so /usr/lib/ibus/ibus-engine-viettelex /usr/lib/x86_64-linux-gnu/viettelex/viettelex-text-tool \
  | grep "not found" && fail "thiếu thư viện"

export HOME=/tmp/h; mkdir -p "$HOME"
dbus-run-session -- bash -c '
  fail=0
  out=$(printf "toi di hoc" | /usr/lib/x86_64-linux-gnu/viettelex/viettelex-text-tool addTones 2>&1)
  if [ "$out" = "tôi đi học" ]; then echo "text-tool: OK"; else echo "text-tool: FAIL ($out)"; fail=1; fi
  fcitx5 --disable=wayland,xim,x11 >/tmp/f.log 2>&1 & sleep 6
  python3 - <<PY || fail=1
import sys
from gi.repository import Gio
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
p = Gio.DBusProxy.new_sync(bus, 0, None, "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1", None)
ims = [i[0] for i in p.call_sync("AvailableInputMethods", None, 0, 3000, None).unpack()[0]]
print("fcitx5:", "viettelex" in ims and "viettelex OK" or "viettelex MISSING")
sys.exit(0 if "viettelex" in ims else 1)
PY
  grep -i viettelex /tmp/f.log | head -5
  ibus-daemon -x -r --panel=disable >/tmp/i.log 2>&1 & sleep 5
  if ibus list-engine 2>/dev/null | grep -q "viettelex -"; then echo "ibus: viettelex OK"; else echo "ibus: viettelex MISSING"; fail=1; fi
  exit $fail' 2>/tmp/dbus.log || { tail -20 /tmp/dbus.log; fail "runtime"; }
python3 -c "import sys; sys.path.insert(0, '/usr/share/viettelex-settings'); import viettelex_settings as v; print('settings', v.VERSION)" \
  2>/dev/null || viettelex-settings --version 2>&1 | head -2 || true

echo "### pacman -R"
pacman -R --noconfirm viettelex-bin >/dev/null || fail "remove"
test ! -e /usr/lib/fcitx5/viettelex.so || fail "leftover"
echo "### RESULT FAILS=$FAILS"
[ "$FAILS" = 0 ]
