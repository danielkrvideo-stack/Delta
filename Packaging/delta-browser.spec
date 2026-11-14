Name:           delta-browser
Version:        0.1.0
Release:        1%{?dist}
Summary:        Delta web browser
License:        Proprietary
BuildArch:      x86_64
Source0:        delta-browser-%{version}.tar.gz
Requires:       python3 >= 3.10
Requires:       python3-gobject
Requires:       gtk3
Requires:       webkit2gtk4.1

%description
Delta browser using GTK and WebKitGTK.

%prep
%setup -q -n delta-browser-%{version}

%install
install -d %{buildroot}%{_libdir}/delta/Linux %{buildroot}%{_libdir}/delta/Shared
install -m 0755 Platforms/Linux/delta.py %{buildroot}%{_libdir}/delta/Linux/delta.py
install -m 0644 Platforms/Shared/dino.html %{buildroot}%{_libdir}/delta/Shared/dino.html
install -d %{buildroot}%{_bindir} %{buildroot}%{_datadir}/applications
install -d %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
install -m 0644 Platforms/Linux/delta.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/delta.svg
cat > %{buildroot}%{_bindir}/delta <<'EOF'
#!/bin/sh
exec /usr/bin/python3 %{_libdir}/delta/Linux/delta.py "$@"
EOF
chmod 0755 %{buildroot}%{_bindir}/delta
install -m 0644 Platforms/Linux/com.delta.browser.desktop %{buildroot}%{_datadir}/applications/com.delta.browser.desktop

%files
%{_bindir}/delta
%{_libdir}/delta/Linux/delta.py
%{_libdir}/delta/Shared/dino.html
%{_datadir}/applications/com.delta.browser.desktop
%{_datadir}/icons/hicolor/scalable/apps/delta.svg
