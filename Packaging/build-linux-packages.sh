#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${DELTA_VERSION:-0.1.0}"
ARCH="amd64"
STAGING="$ROOT/.build/linux-package"

cd "$ROOT"
rm -rf "$STAGING"
mkdir -p "$STAGING/DEBIAN" "$STAGING/usr/bin" \
  "$STAGING/usr/lib/delta/Linux" "$STAGING/usr/lib/delta/Shared" \
  "$STAGING/usr/share/applications" "$STAGING/usr/share/icons/hicolor/scalable/apps"
install -m 0755 Platforms/Linux/delta.py "$STAGING/usr/lib/delta/Linux/delta.py"
install -m 0644 Platforms/Shared/dino.html "$STAGING/usr/lib/delta/Shared/dino.html"
install -m 0644 Platforms/Linux/com.delta.browser.desktop "$STAGING/usr/share/applications/com.delta.browser.desktop"
install -m 0644 Platforms/Linux/delta.svg "$STAGING/usr/share/icons/hicolor/scalable/apps/delta.svg"
cat > "$STAGING/usr/bin/delta" <<'LAUNCHER'
#!/bin/sh
exec /usr/bin/python3 /usr/lib/delta/Linux/delta.py "$@"
LAUNCHER
chmod 0755 "$STAGING/usr/bin/delta"
sed "s/^Version:.*/Version: $VERSION/" Packaging/debian/control > "$STAGING/DEBIAN/control"
dpkg-deb --build --root-owner-group "$STAGING" "$ROOT/Delta-linux-$ARCH-$VERSION.deb"

if command -v rpmbuild >/dev/null 2>&1; then
  TOP="$ROOT/.build/rpm"
  mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
  SOURCE_DIR="$TOP/SOURCES/delta-browser-$VERSION"
  mkdir -p "$SOURCE_DIR"
  cp -R Platforms "$SOURCE_DIR/"
  tar -C "$TOP/SOURCES" -czf "$TOP/SOURCES/delta-browser-$VERSION.tar.gz" "delta-browser-$VERSION"
  rpmbuild -bb Packaging/delta-browser.spec \
    --define "_topdir $TOP" --define "version $VERSION" --define "release 1"
  find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$ROOT/" \;
else
  echo "rpmbuild not installed; RPM build skipped." >&2
fi

if command -v appimage-builder >/dev/null 2>&1; then
  DELTA_VERSION="$VERSION" appimage-builder --recipe Packaging/appimage-builder.yml
else
  echo "appimage-builder not installed; AppImage build skipped." >&2
fi
printf 'Created Debian package for %s.\n' "$ARCH"
