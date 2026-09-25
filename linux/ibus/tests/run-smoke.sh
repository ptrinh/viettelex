#!/bin/sh
# Headless IBus smoke test: private D-Bus session + ibus-daemon (no panel, no X) with a
# component XML pointing at the freshly built engine, driven by smoke_ibus.py.
# Usage: run-smoke.sh /path/to/ibus-engine-viettelex
set -eu
engine=$(readlink -f "$1")
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d /tmp/vt-ibus-XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/component" "$work/config" "$work/state" "$work/cache"
cat > "$work/component/viettelex.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<component>
  <name>org.freedesktop.IBus.VietTelex</name>
  <description>VietTelex (test)</description>
  <exec>$engine --ibus</exec>
  <version>0</version><author>test</author><license>MIT</license><textdomain>viettelex</textdomain>
  <engines><engine>
    <name>viettelex</name><language>vi</language><license>MIT</license><author>test</author>
    <icon>viettelex</icon><layout>default</layout><longname>VietTelex</longname>
    <description>test</description><rank>0</rank>
  </engine></engines>
</component>
XML
export IBUS_COMPONENT_PATH="$work/component"
export XDG_CONFIG_HOME="$work/config" XDG_STATE_HOME="$work/state" XDG_CACHE_HOME="$work/cache"
export HOME="$work"
exec dbus-run-session -- sh -c '
  ibus-daemon --panel=disable --emoji-extension=disable --config=disable --cache=none --replace --daemonize
  python3 "'"$here"'/smoke_ibus.py"; rc=$?
  ibus exit >/dev/null 2>&1 || true
  exit $rc'
