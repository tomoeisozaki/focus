#!/bin/bash
# Builds Fokus.app and installs it to /Applications.
# Requires Xcode or the Xcode Command Line Tools (swiftc) on macOS 13 or later.
set -e
cd "$(dirname "$0")"

ARCH="$(uname -m)"   # arm64 or x86_64
rm -rf build
mkdir -p build/Fokus.app/Contents/MacOS

echo "Compiling for ${ARCH}..."
swiftc -parse-as-library -O -target "${ARCH}-apple-macosx13.0" main.swift -o build/Fokus.app/Contents/MacOS/Fokus
cp Info.plist build/Fokus.app/Contents/Info.plist
codesign --force --sign - build/Fokus.app

echo "Installing to /Applications..."
pkill -x Fokus 2>/dev/null || true
rm -rf /Applications/Fokus.app
cp -R build/Fokus.app /Applications/
open /Applications/Fokus.app
echo "Done. Look for the timer icon in the menu bar."
