#!/usr/bin/env python3
# smoke_ibus.py — drives the real ibus-engine-viettelex through a real ibus-daemon via
# IBus.InputContext (what GTK/Qt IM modules use), simulating an app text buffer.
# Run through run-smoke.sh (private D-Bus session, test config dirs).
import os
import sys
import time

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

CFG = os.path.join(os.environ["XDG_CONFIG_HOME"], "viettelex")
checks = 0


def fail(msg):
    print("IBUS SMOKE FAIL:", msg, file=sys.stderr)
    sys.exit(1)


def expect(cond, msg):
    global checks
    checks += 1
    if not cond:
        fail(msg)


def pump(seconds=0.05):
    end = time.time() + seconds
    ctx = GLib.MainContext.default()
    while time.time() < end:
        while ctx.iteration(False):
            pass
        time.sleep(0.005)


class App:
    """A text field: `doc` is the text before the caret, `pre` the preedit."""

    def __init__(self, bus, name, surrounding=False):
        self.ic = bus.create_input_context(name)
        self.doc, self.pre, self.surrounding = "", "", surrounding
        caps = IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.FOCUS
        if surrounding:
            caps |= IBus.Capabilite.SURROUNDING_TEXT
        self.ic.set_capabilities(caps)
        self.ic.connect("commit-text", self._commit)
        self.ic.connect("update-preedit-text", self._preedit)
        self.ic.connect("hide-preedit-text", lambda ic: setattr(self, "pre", ""))
        self.ic.connect("delete-surrounding-text", self._delete)

    def _sync(self):
        if self.surrounding:
            n = len(self.doc)
            self.ic.set_surrounding_text(IBus.Text.new_from_string(self.doc), n, n)

    def _commit(self, ic, text):
        self.doc += text.get_text()
        self._sync()

    def _preedit(self, ic, text, cursor, visible):
        self.pre = text.get_text() if visible else ""
        attrs = text.get_attributes()
        self.pre_underline = None
        i = 0
        while attrs is not None and attrs.get(i) is not None:
            a = attrs.get(i)
            if a.get_attr_type() == IBus.AttrType.UNDERLINE:
                self.pre_underline = a.get_value()
            i += 1

    def _delete(self, ic, offset, n):
        assert offset == -n, (offset, n)
        self.doc = self.doc[: len(self.doc) - n]
        self._sync()

    def focus(self):
        self.ic.focus_in()
        self.ic.set_engine("viettelex")
        self._sync()
        pump(0.3)

    def key(self, keyval, ch=None, mods=0):
        handled = self.ic.process_key_event(keyval, 0, mods)
        self.ic.process_key_event(keyval, 0, mods | IBus.ModifierType.RELEASE_MASK)
        pump(0.02)
        if not handled and not (mods & IBus.ModifierType.CONTROL_MASK):
            if keyval == IBus.KEY_BackSpace:
                self.doc = self.doc[:-1]
            elif ch is not None:
                self.doc += ch
            self._sync()
            pump(0.01)
        return handled

    def type(self, s):
        for c in s:
            if c == "<":
                self.key(IBus.KEY_BackSpace)
            else:
                self.key(IBus.unicode_to_keyval(c), c)

    def screen(self):
        return self.doc + self.pre


class Term(App):
    """A GTK3 VTE terminal behind the IBus GTK3 module: no surrounding text, forwarded keys
    are applied in arrival order (gdk_event_put) and a forwarded printable key is committed
    by the module itself (IBUS_FORWARD_MASK → ibus_im_context_commit_event)."""

    def __init__(self, bus, name):
        super().__init__(bus, name)
        self.commits = 0
        self.forwarded = []
        self.ic.connect("forward-key-event", self._forward)

    def _commit(self, ic, text):
        self.commits += 1
        super()._commit(ic, text)

    def _forward(self, ic, keyval, keycode, state):
        self.forwarded.append((keyval, keycode, state))
        if state & IBus.ModifierType.RELEASE_MASK:
            return
        # a client sending our forwarded key back must not get it processed again
        expect(state & IBus.ModifierType.FORWARD_MASK, "forwarded key without FORWARD_MASK")
        if keyval == IBus.KEY_BackSpace:
            self.doc = self.doc[:-1]
        else:
            ch = IBus.keyval_to_unicode(keyval)
            expect(ch, f"forwarded non-text key {keyval:#x}")
            self.doc += ch


def main():
    IBus.init()
    bus = IBus.Bus()
    for _ in range(100):
        if bus.is_connected():
            break
        time.sleep(0.1)
        bus = IBus.Bus()
    expect(bus.is_connected(), "no ibus-daemon")

    # 1. preedit (default): underlined composition, committed at the boundary
    a = App(bus, "gedit")
    a.focus()
    expect(a.ic.get_engine() is not None and a.ic.get_engine().get_name() == "viettelex", "engine not set")
    a.type("vieej")
    expect(a.pre == "việ" and a.doc == "", f"preedit {a.pre!r} doc {a.doc!r}")
    # "Gạch chân chữ đang gõ" is off by default: an explicit UNDERLINE_NONE attribute
    expect(a.pre_underline == IBus.AttrUnderline.NONE, f"preedit underline {a.pre_underline!r}")
    a.type("t nam ")
    expect(a.doc == "việt nam ", f"doc {a.doc!r}")
    a.type("google ")
    expect(a.doc.endswith("google "), f"auto-restore {a.doc!r}")

    # 2. Ctrl+Space: English, keys reach the app literally; again → Vietnamese
    expect(a.key(IBus.KEY_space, " ", IBus.ModifierType.CONTROL_MASK), "hotkey not consumed")
    a.type("vieejt ")
    expect(a.doc.endswith("vieejt "), f"english {a.doc!r}")
    a.key(IBus.KEY_space, " ", IBus.ModifierType.CONTROL_MASK)
    a.type("dduwowcj")
    expect(a.pre == "được", f"preedit {a.pre!r}")

    # 3. focus out: the word is committed (PREEDIT_COMMIT mode), not swallowed, not doubled
    a.ic.focus_out()
    pump(0.2)
    expect(a.doc.endswith("được") and not a.doc.endswith("đượcđược") and a.pre == "",
           f"focus-out {a.doc!r} pre {a.pre!r}")
    a.focus()

    # 4. reset (click / caret move) also keeps the word
    a.type(" vieej")
    a.ic.reset()
    pump(0.2)
    expect(a.doc.endswith(" việ") and a.pre == "", f"reset {a.doc!r} pre {a.pre!r}")

    # 5. password field: literal
    a.ic.set_content_type(IBus.InputPurpose.PASSWORD, 0)
    pump()
    a.type(" vieejt")
    expect(a.doc.endswith(" vieejt") and a.pre == "", f"password {a.doc!r}")
    a.ic.set_content_type(IBus.InputPurpose.FREE_FORM, 0)
    pump()

    # 6. live settings: VNI + shortcut + "no underline" (surrounding) without restart
    os.makedirs(CFG, exist_ok=True)
    with open(CFG + "/shortcuts.yml.tmp", "w") as f:
        f.write("ko: không\n")
    os.rename(CFG + "/shortcuts.yml.tmp", CFG + "/shortcuts.yml")
    with open(CFG + "/config.toml.tmp", "w") as f:
        f.write('[typing]\ninput_method = "vni"\n[general]\ndisplay_mode = "surrounding"\n')
    os.rename(CFG + "/config.toml.tmp", CFG + "/config.toml")
    pump(0.4)

    b = App(bus, "org.gnome.texteditor", surrounding=True)
    b.focus()
    b.type("vie65t ko ")
    expect(b.doc == "việt không ", f"surrounding {b.doc!r}")
    expect(b.pre == "", "surrounding mode must not show preedit")
    b.type("toa1n<")  # tone re-placed on ⌫ through delete_surrounding
    expect(b.doc == "việt không tóa", f"surrounding ⌫ {b.doc!r}")

    # App identity (terminal policy, per-app Vi/En memory) needs IBus >= 1.5.28 focus_in_id.
    if IBus.MAJOR_VERSION * 10000 + IBus.MINOR_VERSION * 100 + IBus.MICRO_VERSION >= 10528:
        # 7. terminal stays preedit even with surrounding enabled
        t = App(bus, "kitty", surrounding=True)
        t.focus()
        t.type("vie65")
        expect(t.pre == "việ", f"terminal preedit {t.pre!r}")
        t.type(" ")
        # 8. per-app Vi/En memory
        t.key(IBus.KEY_space, " ", IBus.ModifierType.CONTROL_MASK)  # kitty → English
        t.ic.focus_out()
        pump()
        b.focus()
        b.doc = ""
        b._sync()
        b.type("a1")
        expect(b.screen() == "á", f"texteditor still Vietnamese {b.screen()!r}")  # empty field: preedit until proven
        b.ic.focus_out()
        pump()
        t.focus()
        t.doc = ""
        t.type("a1")
        expect(t.doc == "a1" and t.pre == "", f"kitty remembered English {t.doc!r} {t.pre!r}")
        with open(os.path.join(os.environ["XDG_STATE_HOME"], "viettelex", "app-state")) as f:
            expect("kitty\ten" in f.read(), "app-state not persisted")

        # 9. Direct mode: a GTK3 terminal — tones fixed with forwarded BackSpace + forwarded
        #    text, never commit_text / delete_surrounding / preedit (no underline at all)
        d = Term(bus, "gtk3-im:gnome-terminal-server")
        d.focus()
        d.ic.set_content_type(IBus.InputPurpose.TERMINAL, 0)
        pump()
        d.type("vie65t ")  # config above is VNI
        expect(d.doc == "việt " and d.pre == "", f"direct {d.doc!r} pre {d.pre!r}")
        d.type("toa1n<")
        expect(d.doc == "việt tóa", f"direct ⌫ {d.doc!r}")
        expect(d.commits == 0, f"direct used commit_text {d.commits}")
        expect(any(k == IBus.KEY_BackSpace for k, _c, _s in d.forwarded), "no forwarded BackSpace")
        # our forwarded keys coming back (FORWARD_MASK) are passed through untouched
        n = len(d.forwarded)
        expect(not d.ic.process_key_event(IBus.KEY_BackSpace, 14, IBus.ModifierType.FORWARD_MASK),
               "forwarded BackSpace consumed")
        expect(not d.ic.process_key_event(ord("a"), 30, IBus.ModifierType.FORWARD_MASK), "forwarded key consumed")
        pump()
        expect(len(d.forwarded) == n, "forwarded key re-processed")
        # GTK4 module (forwarded BackSpace never reaches the widget): stays preedit
        g4 = Term(bus, "gtk4-im:ptyxis")
        g4.focus()
        g4.ic.set_content_type(IBus.InputPurpose.TERMINAL, 0)
        pump()
        g4.type("vie65")
        expect(g4.pre == "việ" and not g4.forwarded, f"gtk4 terminal {g4.pre!r} {g4.forwarded!r}")
    print(f"ibus smoke: {checks} checks passed (IBus {IBus.MAJOR_VERSION}.{IBus.MINOR_VERSION}.{IBus.MICRO_VERSION})")


main()
