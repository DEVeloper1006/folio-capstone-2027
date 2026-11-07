#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/build/Folio.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources/editor"
xcrun swiftc -swift-version 6 -target arm64-apple-macosx13.0 \
  macos/Folio.swift macos/Assistant.swift macos/MathMode.swift macos/Workspace.swift -o "$bundle/MacOS/Folio" -framework Cocoa -framework WebKit
cp macos/Info.plist "$bundle/Info.plist"
cp outputs/desktop.html outputs/tokens.css outputs/native.css outputs/math-modes.js "$bundle/Resources/editor/"
cp -R outputs/vendor "$bundle/Resources/editor/"
codesign --force --sign - "$PWD/build/Folio.app"
printf '%s\n' "$PWD/build/Folio.app"
