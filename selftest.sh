#!/bin/bash
# Selbsttest der Kompressionslogik gegen ein echtes PDF.
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
[ -n "$1" ] || { echo "Nutzung: ./selftest.sh datei.pdf"; exit 1; }
SDK="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
[ -d "$SDK" ] || SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
BIN="$(mktemp -d)/selftest"
env -u SDKROOT xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -target arm64-apple-macos14.0 -o "$BIN" \
  Sources/Models.swift Sources/Ghostscript.swift Sources/Runner.swift Tests/SelfTest.swift
"$BIN" "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
