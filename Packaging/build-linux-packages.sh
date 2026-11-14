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
  RPM_PACKAGE="$(find "$TOP/RPMS" -type f -name '*.rpm' -print -quit)"
  if [[ -z "$RPM_PACKAGE" ]]; then
    echo "RPM build completed without producing an RPM package." >&2
    exit 1
  fi
  cp "$RPM_PACKAGE" "$ROOT/Delta-linux-x86_64-$VERSION.rpm"
else
  echo "rpmbuild not installed; RPM build skipped." >&2
fi

if command -v appimage-builder >/dev/null 2>&1; then
  APPIMAGE_RECIPE="$ROOT/.build/appimage-builder.yml"
  sed "s/^    version: .*/    version: $VERSION/" \
    Packaging/appimage-builder.yml > "$APPIMAGE_RECIPE"
  DELTA_VERSION="$VERSION" appimage-builder --recipe "$APPIMAGE_RECIPE"
  APPIMAGE_PACKAGE="$(find "$ROOT" -maxdepth 4 -type f -name '*.AppImage' \
    ! -path "$ROOT/Delta-linux-x86_64-$VERSION.AppImage" -print -quit)"
  if [[ -z "$APPIMAGE_PACKAGE" ]]; then
    echo "AppImage build completed without producing an AppImage." >&2
    exit 1
  fi
  mv "$APPIMAGE_PACKAGE" "$ROOT/Delta-linux-x86_64-$VERSION.AppImage"
else
  echo "appimage-builder not installed; AppImage build skipped." >&2
fi
printf 'Created Debian package for %s.\n' "$ARCH"
