#!/bin/bash
# Chạy TRONG container Ubuntu sạch (xem ../test-update.sh): cập nhật một chạm từ bản $OLD
# (/rel, tên asset GitHub) lên $NEW (/fake/dist + kho /fake/repo + /fake/stable.json) bằng
# helper viettelex-update + updater.run_update (pkexec giả = chạy thẳng bằng root), cả đường
# kho APT lẫn đường .deb; kiểm huỷ pkexec, apt bận, SHA256 sai, host lạ, metapackage, purge.
set -u
: "${OLD:?}" "${NEW:?}"
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release; S=$VERSION_CODENAME; A=$(dpkg --print-architecture)
FAILS=0; fail(){ echo "FAIL: $*"; FAILS=$((FAILS+1)); }
PK="libviettelex-core viettelex-fcitx5 viettelex-ibus viettelex-text-tools viettelex-settings viettelex"
# shellcheck disable=SC2046  # danh sách gói: tách từ là chủ ý
purge(){ dpkg --purge $(dpkg-query -W -f="\${Package} \${db:Status-Abbrev}\\n" $PK 2>/dev/null | awk "\$2 !~ /^u/ {print \$1}") >/dev/null; }
vers(){ dpkg-query -W -f='${Package}=${Version}(${db:Status-Abbrev}) ' $PK 2>/dev/null; echo; }
isver(){ v=$(dpkg-query -W -f='${Version}' $1 2>/dev/null); [ "$v" = "$2~${S}1" ] || fail "$1=$v (want $2)"; }
apt-get update -qq && apt-get install -y -qq ca-certificates curl python3 >/dev/null || exit 9
printf '#!/bin/sh\nexec "$@"\n' > /usr/local/bin/pkexec; chmod +x /usr/local/bin/pkexec
PY="import json,sys; sys.path.insert(0,'/src/linux/settings'); from viettelex_settings import updater as u; lin=json.load(open('/fake/stable.json'))['linux']"
install -Dm755 /src/linux/settings/viettelex-update /usr/libexec/viettelex/viettelex-update

echo "### [$S/$A] A) kho APT: $OLD -> $NEW"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://ptrinh.github.io/viettelex-apt/viettelex-archive-keyring.gpg > /etc/apt/keyrings/viettelex.gpg
cat > /etc/apt/sources.list.d/viettelex.sources <<EOT
Types: deb
URIs: https://ptrinh.github.io/viettelex-apt/
Suites: $S
Components: main
Signed-By: /etc/apt/keyrings/viettelex.gpg
EOT
apt-get update -qq; apt-get install -y -qq /rel/libviettelex-core_$OLD.${S}1_$A.deb /rel/viettelex-fcitx5_$OLD.${S}1_$A.deb /rel/viettelex-settings_$OLD.${S}1_all.deb >/tmp/a.log 2>&1 || { tail /tmp/a.log; fail "install $OLD"; }
vers
# kho local chưa có trong lists → helper phải tự update riêng kho VietTelex
sed -i 's#^URIs: .*#URIs: https://ptrinh.github.io/viettelex-apt/ file:/fake/repo/#' /etc/apt/sources.list.d/viettelex.sources
echo "Trusted: yes" >> /etc/apt/sources.list.d/viettelex.sources
echo "-- huỷ pkexec"
printf '#!/bin/sh\nexit 126\n' > /usr/local/bin/pkexec
python3 -c "$PY; print(u.run_update(lin, print))" | tail -1 | grep -q "huỷ" || fail "cancel msg"
printf '#!/bin/sh\nexec "$@"\n' > /usr/local/bin/pkexec
echo "-- apt bận"
python3 -c "import fcntl,time; f=open('/var/lib/dpkg/lock-frontend','w'); fcntl.lockf(f, fcntl.LOCK_EX); time.sleep(30)" & LP=$!; sleep 1
out=$(VT_LOCK_WAIT=2 python3 -c "$PY; print(u.run_update(lin, print))" | tail -1); echo "$out"
echo "$out" | grep -q "bận" || fail "lock msg"; kill $LP; wait $LP 2>/dev/null
isver viettelex-fcitx5 $OLD
echo "-- cập nhật thật (apt)"
out=$(python3 -c "$PY; print(u.run_update(lin, print))"); echo "$out" | tail -3
echo "$out" | tail -1 | grep -q "(True" || fail "apt run_update"
vers; for p in libviettelex-core viettelex-fcitx5 viettelex-settings; do isver $p $NEW; done
dpkg -s viettelex-ibus >/dev/null 2>&1 && fail "ibus bị cài thêm"
test -x /usr/libexec/viettelex/viettelex-update && test -f /usr/share/polkit-1/actions/org.viettelex.update.policy || fail "helper/policy missing"
echo "-- helper từ chối gói lạ"
/usr/libexec/viettelex/viettelex-update apt bash; [ $? = 2 ] || fail "whitelist"

echo "### B) đường .deb (không kho): $OLD IBus -> $NEW"
purge; rm -f /etc/apt/sources.list.d/viettelex.sources; apt-get update -qq
install -Dm755 /src/linux/settings/viettelex-update /usr/libexec/viettelex/viettelex-update
apt-get install -y -qq /rel/libviettelex-core_$OLD.${S}1_$A.deb /rel/viettelex-ibus_$OLD.${S}1_$A.deb /rel/viettelex-settings_$OLD.${S}1_all.deb >/tmp/b.log 2>&1 || { tail /tmp/b.log; fail "install old debs"; }
install -Dm755 /src/linux/settings/viettelex-update /usr/libexec/viettelex/viettelex-update
vers
mkdir -p /srv/gh; for f in /fake/dist/*/*.deb; do cp "$f" "/srv/gh/$(basename "$f" | tr '~' '.')"; done
cp -r /srv/gh /srv/bad; echo junk >> /srv/bad/viettelex-ibus_$NEW.${S}1_$A.deb
(cd /srv && python3 -m http.server 8000 --bind 127.0.0.1 >/dev/null 2>&1 &) ; sleep 1
echo "-- SHA256 sai"
out=$(python3 -c "$PY; lin['download']='http://127.0.0.1:8000/bad/'; print(u.run_update(lin, print, allowed_prefix='http://127.0.0.1:8000/'))" | tail -1); echo "$out"
echo "$out" | grep -q "SHA256" || fail "sha msg"; isver viettelex-ibus $OLD
echo "-- host lạ bị chặn (không prefix)"
out=$(python3 -c "$PY; lin['download']='http://127.0.0.1:8000/gh/'; print(u.run_update(lin, print))" | tail -1); echo "$out"
echo "$out" | grep -q "không hợp lệ" || fail "prefix"
echo "-- cập nhật thật (.deb)"
out=$(python3 -c "$PY; lin['download']='http://127.0.0.1:8000/gh/'; print(u.run_update(lin, print, allowed_prefix='http://127.0.0.1:8000/'))"); echo "$out" | tail -3
echo "$out" | tail -1 | grep -q "(True" || fail "deb run_update"
vers; for p in libviettelex-core viettelex-ibus viettelex-settings; do isver $p $NEW; done
dpkg -s viettelex-fcitx5 >/dev/null 2>&1 && fail "fcitx5 bị cài thêm"
ls /tmp/viettelex-update.* /tmp/viettelex-upd-* 2>/dev/null && fail "temp left"

echo "### C) metapackage"
purge; apt-get autoremove -y -qq >/dev/null
printf 'Types: deb\nURIs: file:/fake/repo/\nSuites: %s\nComponents: main\nTrusted: yes\n' $S > /etc/apt/sources.list.d/viettelex.sources
apt-get update -qq
apt-get install -y -qq viettelex >/tmp/c1.log 2>&1 || { tail /tmp/c1.log; fail "meta default"; }
vers; dpkg -s viettelex-fcitx5 >/dev/null 2>&1 || fail "meta default không kéo fcitx5"
isver viettelex-text-tools "$NEW"   # Recommends: apt mặc định cài
dpkg -s viettelex-ibus >/dev/null 2>&1 && fail "meta default kéo ibus"
purge; apt-get autoremove -y -qq >/dev/null
apt-get install -y -qq viettelex viettelex-ibus >/tmp/c2.log 2>&1 || { tail /tmp/c2.log; fail "meta ibus"; }
vers; dpkg -s viettelex-fcitx5 >/dev/null 2>&1 && fail "meta+ibus vẫn kéo fcitx5"
echo "-- purge sạch"
dpkg -L $PK 2>/dev/null | sort -u > /tmp/files
purge || fail purge
left=$(while read f; do [ -f "$f" ] && echo "$f"; done </tmp/files); [ -z "$left" ] || { echo "$left"; fail "leftover"; }
ls -d /usr/libexec/viettelex /usr/share/viettelex-settings 2>/dev/null && fail "leftover dir"
echo "### RESULT [$S/$A] FAILS=$FAILS"
