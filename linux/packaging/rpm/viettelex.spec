# VietTelex — gói RPM (Fedora, Enterprise Linux 9/10 = Rocky/Alma/RHEL).
#
# Build bằng linux/packaging/build-rpm.sh (container theo distro, xem packaging/RPM.md).
# Nguồn = tarball do rpm/build-in-container.sh dàn (TelexCore/ + linux/ + file iOS dùng chung).
#
# Engine Swift (libtelexcore.so + viettelex-text-tool) build trước bằng toolchain Swift chính
# thức (ảnh swift:rhel-ubi9, glibc 2.34 ⇒ chạy trên EL9, EL10 và Fedora) rồi truyền vào qua
#   --define "vt_swift_dir /path/chứa/libtelexcore.so+viettelex-text-tool"
# Không có vt_swift_dir ⇒ CMake tự gọi `swift build` (cần swift trên PATH).
#
# Fcitx5: EPEL 9/10 không có fcitx5 ⇒ trên EL chỉ có engine IBus (bcond fcitx5 tắt).

%if 0%{?rhel}
%bcond_with fcitx5
%else
%bcond_without fcitx5
%endif

# Engine Swift dựng sẵn: dwz/debugedit không hiểu DWARF do swiftc sinh (giống override_dh_dwz
# bên Debian) ⇒ không tách gói debuginfo.
%global debug_package %{nil}
# libtelexcore.so nằm ở thư mục riêng, không phải thư viện hệ thống: không quảng bá
# "libtelexcore.so()(64bit)" ra ngoài, frontend phụ thuộc gói libviettelex-core theo tên.
%global __provides_exclude_from ^%{_libdir}/viettelex/.*$
%global __requires_exclude ^libtelexcore\\.so.*$

Name:           viettelex
Version:        %{vt_version}
Release:        1%{?dist}
Summary:        Vietnamese input method (Telex, VNI) - full install
License:        MIT
URL:            https://viettelex.com
Source0:        viettelex-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(ibus-1.0)
BuildRequires:  python3
BuildRequires:  desktop-file-utils
BuildRequires:  appstream
%if %{with fcitx5}
BuildRequires:  extra-cmake-modules
BuildRequires:  fcitx5-devel
# Addon test (testfrontend/testim/testui .so) nằm trong gói fcitx5 của Fedora.
BuildRequires:  fcitx5
%endif
# %%check: test IBus thật (ibus-daemon + PyGObject) và GnomeAppMonitor (dbus-daemon).
BuildRequires:  ibus
BuildRequires:  dbus-daemon
BuildRequires:  python3-gobject-base

Requires:       libviettelex-core = %{version}-%{release}
Requires:       viettelex-settings = %{version}-%{release}
%if %{with fcitx5}
Requires:       (viettelex-fcitx5 = %{version}-%{release} or viettelex-ibus = %{version}-%{release})
%else
Requires:       viettelex-ibus = %{version}-%{release}
%endif
Recommends:     viettelex-text-tools = %{version}-%{release}

%global vt_desc VietTelex types Vietnamese exactly like its macOS version: Telex, Simple\
Telex, VNI, free tone placement, Quick Telex, live spell-check, automatic\
English restore and context-aware decisions.

%description
%{vt_desc}

This metapackage installs the typing engine, the settings application, the
text tools and one input method frontend (Fcitx5 where available, otherwise
IBus).

%package -n libviettelex-core
Summary:        VietTelex Vietnamese input method - typing engine
Requires:       hicolor-icon-theme

%description -n libviettelex-core
%{vt_desc}

This package contains libtelexcore, the shared typing engine (Swift, built
with a static Swift runtime) used by the Fcitx5 and IBus frontends, installed
in a private directory, and the input-method status icons.

%package text-tools
Summary:        VietTelex Vietnamese input method - text tools for the selection
Enhances:       viettelex-ibus
%if %{with fcitx5}
Enhances:       viettelex-fcitx5
%endif

%description text-tools
%{vt_desc}

This package adds "Tools..." to the input method menu (add tones to
unaccented text, UPPERCASE, lowercase, Title Case, Sentence case, remove
tones) and computes the suggestions shown next to the caret (math results,
money format, typo fixes, dates). It contains the viettelex-text-tool helper
and its dictionaries.

%if %{with fcitx5}
%package fcitx5
Summary:        VietTelex Vietnamese input method - Fcitx5 addon
Requires:       libviettelex-core%{?_isa} = %{version}-%{release}
Requires:       fcitx5
Recommends:     viettelex-settings = %{version}-%{release}
Recommends:     viettelex-text-tools%{?_isa} = %{version}-%{release}
Recommends:     fcitx5-gtk
Recommends:     fcitx5-qt
Recommends:     fcitx5-configtool

%description fcitx5
%{vt_desc}

This package contains the Fcitx5 input method addon (recommended: runs inside
the fcitx5 process for the lowest latency). After installing, add
"Vietnamese (VietTelex)" in the Fcitx5 configuration.
%endif

%package ibus
Summary:        VietTelex Vietnamese input method - IBus engine
Requires:       libviettelex-core%{?_isa} = %{version}-%{release}
Requires:       ibus
Recommends:     viettelex-settings = %{version}-%{release}
Recommends:     viettelex-text-tools%{?_isa} = %{version}-%{release}
Recommends:     ibus-gtk3
Recommends:     ibus-gtk4

%description ibus
%{vt_desc}

This package contains the IBus engine (IBus is the default input method
framework of Fedora Workstation/GNOME and of Enterprise Linux). After
installing, run "ibus restart" and add Vietnamese > VietTelex under
Settings > Keyboard > Input Sources.

%package settings
Summary:        VietTelex Vietnamese input method - settings application
BuildArch:      noarch
Requires:       python3
Requires:       python3-gobject
Requires:       gtk4
Requires:       libadwaita
Requires:       hicolor-icon-theme
Recommends:     (viettelex-fcitx5 or viettelex-ibus)

%description settings
%{vt_desc}

This package contains viettelex-settings, a GTK4/libadwaita application to
change typing options, shortcuts (abbreviations) and per-application typing
modes, and to guide you through enabling VietTelex in Fcitx5 or IBus.
Updates arrive through dnf (or rpm-ostree on Fedora Atomic desktops).

%prep
%autosetup -n viettelex-%{version}

%build
%cmake -S linux \
    -DVT_BUILD_FCITX5=%{?with_fcitx5:ON}%{!?with_fcitx5:OFF} \
    -DVT_BUILD_IBUS=ON -DVT_BUILD_TESTS=ON \
    %{?vt_swift_dir:-DVT_CORE_LIB=%{vt_swift_dir}/libtelexcore.so -DVT_TEXT_TOOL=%{vt_swift_dir}/viettelex-text-tool}
%cmake_build
%make_build -C linux/settings PYTHON=%{python3}

%install
%cmake_install
%make_install -C linux/settings PREFIX=%{_prefix} PYTHON=%{python3}
# Cập nhật một chạm (apt/dpkg + polkit) không áp dụng cho RPM: bỏ, app báo "cập nhật bằng dnf".
rm -rf %{buildroot}%{_libexecdir}/viettelex %{buildroot}%{_datadir}/polkit-1
rm -rf %{buildroot}%{_includedir} %{buildroot}%{_libdir}/pkgconfig %{buildroot}%{_libdir}/cmake
install -Dm644 linux/packaging/data/icons/hicolor/scalable/status/*.svg -t \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/status/
install -Dm644 linux/packaging/debian/viettelex-settings.1 %{buildroot}%{_mandir}/man1/viettelex-settings.1
# Dấu cài đặt cho app: nguồn cập nhật là dnf / rpm-ostree (viettelex_settings/updater.py).
echo rpm > %{buildroot}%{_datadir}/viettelex-settings/install-method

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/com.viettelex.Settings.desktop
appstreamcli validate --no-net %{buildroot}%{_datadir}/metainfo/com.viettelex.Settings.metainfo.xml
make -C linux/settings check PYTHON=%{python3}
# ibus_smoke gắn engine vào từng context bằng IBus.InputContext.set_engine(); IBus của Red Hat
# (EL10 1.5.32, Fedora 1.5.34) giữ context theo engine toàn cục nên harness không gắn được
# (engine vẫn được kiểm khi cài: rpm/smoke-install.sh → ibus list-engine). EL9 (1.5.25) chạy đủ.
%if 0%{?fedora} || 0%{?rhel} >= 10
%ctest --exclude-regex ibus_smoke
%else
%ctest
%endif

%files
%license LICENSE

%files -n libviettelex-core
%license LICENSE
%dir %{_libdir}/viettelex
%{_libdir}/viettelex/libtelexcore.so
%{_datadir}/icons/hicolor/scalable/status/viettelex*.svg

%files text-tools
# Cũng sở hữu thư mục riêng (libviettelex-core cũng vậy — rpm cho phép): gói này cài được một
# mình (Enhances, không Requires core) nên không được để thư mục mồ côi khi gỡ.
%dir %{_libdir}/viettelex
%{_libdir}/viettelex/viettelex-text-tool
%{_datadir}/viettelex/

%if %{with fcitx5}
%files fcitx5
%{_libdir}/fcitx5/viettelex.so
%{_datadir}/fcitx5/addon/viettelex.conf
%{_datadir}/fcitx5/inputmethod/viettelex.conf
%endif

%files ibus
%{_libexecdir}/ibus-engine-viettelex
%{_datadir}/ibus/component/viettelex.xml

%files settings
%license LICENSE
%{_bindir}/viettelex-settings
%{_datadir}/viettelex-settings/
%{_datadir}/applications/com.viettelex.Settings.desktop
%{_datadir}/metainfo/com.viettelex.Settings.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/com.viettelex.Settings.png
%{_mandir}/man1/viettelex-settings.1*

%changelog
* %{vt_changelog_date} VietTelex Maintainers <maintainers@viettelex.invalid> - %{version}-1
- See https://github.com/ptrinh/viettelex/releases/tag/linux-v%{version}
