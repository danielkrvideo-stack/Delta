# Delta

Delta is a native macOS browser built with SwiftUI, AppKit, and WebKit. It supports Intel Macs and macOS 13 or later.

## Build and launch

```sh
chmod +x build-app.sh
./build-app.sh
open Delta.app
```

The build script creates an Intel-only `Delta.app` in the project directory.
The bundle includes a generated Delta app icon.

## Publishing an update

Push the source to `danielkrvideo-stack/Delta`, then push a version tag to publish an Intel release:

```sh
git tag v0.1.1
git push origin v0.1.1
```

GitHub Actions builds `Delta-macos-intel.zip` and its SHA-256 checksum. Delta checks the latest public GitHub release and offers updates from the browser toolbar. Installers must be stored in a folder the current macOS user can modify; `/Applications` may require administrator permissions.
