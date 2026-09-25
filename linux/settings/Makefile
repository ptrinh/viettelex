# viettelex-settings — cài đặt không cần build (Python + PyGObject).
#   make check                    chạy unit test (không cần GTK)
#   make install DESTDIR=… PREFIX=/usr
PREFIX ?= /usr/local
DESTDIR ?=
PYTHON ?= python3
DATA := ../packaging/data
SHARE := $(DESTDIR)$(PREFIX)/share
ICON_SIZES := 16 22 24 32 48 64 128 256 512

.PHONY: all check install uninstall
all:
	$(PYTHON) -m py_compile viettelex_settings/*.py

check:
	$(PYTHON) -m unittest discover -s tests -v

install: all
	install -Dm755 viettelex-settings $(DESTDIR)$(PREFIX)/bin/viettelex-settings
	install -d $(SHARE)/viettelex-settings/viettelex_settings
	install -m644 viettelex_settings/*.py $(SHARE)/viettelex-settings/viettelex_settings/
	install -Dm644 $(DATA)/com.viettelex.Settings.desktop $(SHARE)/applications/com.viettelex.Settings.desktop
	install -Dm644 $(DATA)/com.viettelex.Settings.metainfo.xml $(SHARE)/metainfo/com.viettelex.Settings.metainfo.xml
	for s in $(ICON_SIZES); do \
	  install -Dm644 $(DATA)/icons/hicolor/$${s}x$${s}/apps/viettelex.png \
	    $(SHARE)/icons/hicolor/$${s}x$${s}/apps/viettelex.png; done

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/viettelex-settings
	rm -rf $(SHARE)/viettelex-settings
	rm -f $(SHARE)/applications/com.viettelex.Settings.desktop $(SHARE)/metainfo/com.viettelex.Settings.metainfo.xml
	for s in $(ICON_SIZES); do rm -f $(SHARE)/icons/hicolor/$${s}x$${s}/apps/viettelex.png; done
