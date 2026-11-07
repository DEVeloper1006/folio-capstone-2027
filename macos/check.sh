#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
bash macos/build.sh
node work/mode_contract_test.js
node work/keyboard_model_test.js
xcrun swiftc -swift-version 6 macos/Assistant.swift macos/MathMode.swift macos/Workspace.swift macos/WorkspaceCheck.swift -o work/workspace-check
work/workspace-check
build/Folio.app/Contents/MacOS/Folio --self-test
if [[ $# -gt 0 ]]; then
  xcrun swiftc -swift-version 6 macos/Assistant.swift macos/MathMode.swift macos/AssistantCheck.swift -o work/assistant-check
  work/assistant-check "$1"
  xcrun swiftc -swift-version 6 macos/Assistant.swift macos/MathMode.swift macos/ModeCheck.swift -o work/mode-check
  work/mode-check "$1"
  build/Folio.app/Contents/MacOS/Folio --self-test --live-modes --live-assistant --model "$1"
fi
