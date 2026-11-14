# Delta

Delta is a browser with native platform shells: SwiftUI, AppKit, and WKWebView on macOS; WinForms and WebView2 on Windows; and GTK 3 and WebKitGTK on Linux. Browser settings, bookmarks, history, and open tabs are stored in the platform's user-data directories. Website login sessions are provided by the embedded browser engine's persistent profile.

## Build and launch

```sh
chmod +x build-app.sh
./build-app.sh
open Delta.app
```

The build script creates an Intel-only `Delta.app` in the project directory.
The bundle includes a generated Delta app icon.
Delta can open local `.html`, `.htm`, and `.xhtml` files from File → Open HTML File (⌘O), by entering a local file URL, or by opening an HTML document from Finder. Relative CSS, JavaScript, and image files in the HTML document's folder are available to that page.

## Windows 10/11 x64

The Windows app is in `Platforms/Delta.CrossPlatform`. It uses .NET 8 WinForms and Microsoft Edge WebView2. WebView2 Evergreen Runtime is required; install the official Microsoft runtime if it is not already present:
<https://developer.microsoft.com/microsoft-edge/webview2/>

On Windows, install the .NET 8 SDK and WiX v4 CLI (`dotnet tool install --global wix --version 4.*`), then run:

```powershell
.\Packaging\Windows\build.ps1
```

The script publishes a self-contained `Delta.exe` in `.build/windows-publish` and creates a per-user `.msi`. Website cookies and login state stay in `%APPDATA%\Delta\WebView2`; browser data is stored in `%APPDATA%\Delta\browser-state.json`. The executable checks for WebView2 when starting and gives the official runtime installation link if it is missing.

## Linux

The Linux app is in `Platforms/Linux` and uses GTK 3 with WebKitGTK 4.1 (or 4.0 on older distributions). Install Python 3, PyGObject, GTK 3, and the matching WebKitGTK typelib/runtime:

```sh
# Ubuntu 24.04 / Debian releases with WebKitGTK 4.1
sudo apt install python3 python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1 libwebkit2gtk-4.1-0

# Ubuntu 22.04 / Linux Mint 21 (WebKitGTK 4.0)
sudo apt install python3 python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.0 libwebkit2gtk-4.0-37

# Fedora
sudo dnf install python3 python3-gobject gtk3 webkit2gtk4.1
```

Run from the checkout with `python3 Platforms/Linux/delta.py`. On Debian-based systems, `bash Packaging/build-linux-packages.sh` creates a `.deb`; when installed, `rpmbuild` and `appimage-builder` are used if present to create `.rpm` and AppImage packages. The AppImage depends on the system graphics stack and WebKit sandbox compatibility; test it on the target distribution before redistribution. User data is stored under the standard XDG locations (`~/.config/delta`, `~/.local/share/delta`, and `~/.cache/delta`).

## Cross-platform notes

The native browser engines and platform user profiles are intentionally separate; website logins work through each engine's cookies and are not synchronized between operating systems. The offline pixel game is a local bundled HTML file and makes no network requests. The existing macOS target remains unchanged.

The macOS DMG can be created on macOS with `bash Packaging/build-macos-dmg.sh`. The current macOS build script produces an Intel app; Apple Silicon and Windows/Linux runtime behavior require testing on those operating systems before claiming platform certification.

## Publishing an update

Push the source to `danielkrvideo-stack/Delta`, then push a version tag to publish an Intel release:

```sh
git tag v0.1.1
git push origin v0.1.1
```

GitHub Actions builds `Delta-macos-intel.zip` and its SHA-256 checksum. Delta checks the latest public GitHub release and offers updates from the browser toolbar. Installers must be stored in a folder the current macOS user can modify; `/Applications` may require administrator permissions.
