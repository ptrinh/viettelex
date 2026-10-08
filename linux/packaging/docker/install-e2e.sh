#!/bin/bash
# Chạy TRONG container Ubuntu sạch, với docs/install.sh mount ở /e2e/install.sh và kho APT
# thật (https://ptrinh.github.io/viettelex-apt/):
#   docker run --rm -v "$PWD/docs:/e2e:ro" -v "$PWD/linux/packaging/docker:/t:ro" \
#     ubuntu:24.04 bash /t/install-e2e.sh        (chạy từ gốc repo; thêm --platform linux/amd64 nếu cần)
# Kiểm: cài bằng user thường + sudo, chạy lại, --uninstall, --ibus, giữ IBus khi chạy lại,
# từ chối series/distro chưa hỗ trợ, nhận Mint (UBUNTU_CODENAME), từ chối khoá sai vân tay.
set -u
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release; S=$VERSION_CODENAME
FAILS=0; fail(){ echo "FAIL: $*"; FAILS=$((FAILS+1)); }
PK="viettelex libviettelex-core viettelex-fcitx5 viettelex-ibus viettelex-settings"
vers(){ dpkg-query -W -f='${Package}=${Version}(${db:Status-Abbrev}) ' $PK 2>/dev/null; echo; }
inst(){ dpkg-query -W -f='${db:Status-Abbrev}' $1 2>/dev/null | grep -q '^.i'; }
apt-get update -qq && apt-get install -y -qq curl sudo gnupg >/dev/null || exit 9
useradd -m u; echo 'u ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/u
echo "### [$S] 1) kho that, user thuong + sudo, --yes (mac dinh fcitx5)"
su u -c 'cat /e2e/install.sh | bash -s -- --yes' > /tmp/1.log 2>&1 || { tail -20 /tmp/1.log; fail "install"; }
grep -E '^\s+\$ |==>' /tmp/1.log | sed 's/\x1b\[[0-9;]*m//g'
vers; inst viettelex-fcitx5 || fail "no fcitx5"; inst viettelex-ibus && fail "ibus"
grep -q "Signed-By: /etc/apt/keyrings/viettelex.gpg" /etc/apt/sources.list.d/viettelex.sources || fail sources
grep -q fcitx5 /home/u/.xinputrc 2>/dev/null && echo "xinputrc: $(grep run_im /home/u/.xinputrc)" || fail "im-config"
echo "### 2) chay lai (idempotent)"
su u -c 'cat /e2e/install.sh | bash -s -- --yes' > /tmp/2.log 2>&1 || { tail -20 /tmp/2.log; fail "rerun"; }
grep -E "Xong" /tmp/2.log
echo "### 3) --uninstall"
su u -c 'cat /e2e/install.sh | bash -s -- --uninstall --yes' > /tmp/3.log 2>&1 || { tail /tmp/3.log; fail uninstall; }
vers | grep -q "(ii" && fail "still installed"; ls /etc/apt/sources.list.d/viettelex.sources /etc/apt/keyrings/viettelex.gpg 2>/dev/null && fail "repo left"
echo "### 4) --ibus (root, khong sudo)"
bash /e2e/install.sh --ibus --yes > /tmp/4.log 2>&1 || { tail /tmp/4.log; fail "ibus install"; }
vers; inst viettelex-ibus || fail "no ibus"; inst viettelex-fcitx5 && fail "fcitx5 pulled"
echo "### 5) chay lai khong co flag -> giu ibus"
bash /e2e/install.sh --yes > /tmp/5.log 2>&1 || fail "rerun ibus"; grep "Bộ khung gõ" /tmp/5.log | sed 's/\x1b\[[0-9;]*m//g'
inst viettelex-fcitx5 && fail "rerun switched to fcitx5"
bash /e2e/install.sh --uninstall --yes >/dev/null 2>&1
echo "### 6) he dieu hanh khong ho tro"
cp /etc/os-release /tmp/osr
sed -i 's/^VERSION_CODENAME=.*/VERSION_CODENAME=questing/; s/^UBUNTU_CODENAME=.*/UBUNTU_CODENAME=questing/' /etc/os-release
bash /e2e/install.sh --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -1; [ ${PIPESTATUS[0]} != 0 ] || fail "questing accepted"
printf 'ID=debian\nVERSION_CODENAME=forky\nPRETTY_NAME="Debian forky/sid"\n' > /etc/os-release
bash /e2e/install.sh --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -1; [ ${PIPESTATUS[0]} != 0 ] || fail "forky accepted"
# (bảng distro → series đầy đủ: linux/packaging/test-install-detect.sh)
printf 'ID=linuxmint\nID_LIKE="ubuntu debian"\nVERSION_CODENAME=wilma\nUBUNTU_CODENAME=%s\nPRETTY_NAME="Linux Mint 22"\n' $S > /etc/os-release
bash /e2e/install.sh --dry-run --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Kiểm tra kho|chữ ký"
cp /tmp/osr /etc/os-release
echo "### 7) chu ky gia -> tu choi"
sed 's/^APT_KEY_FPR=.*/APT_KEY_FPR="0000000000000000000000000000000000000000"/' /e2e/install.sh > /tmp/bad.sh
bash /tmp/bad.sh --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -1; ls /etc/apt/sources.list.d/viettelex.sources 2>/dev/null && fail "bad key accepted"
echo "### RESULT [$S] FAILS=$FAILS"
