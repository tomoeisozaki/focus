#!/bin/bash
# Builds Focus.app and installs it to /Applications.
# Requires Xcode or the Xcode Command Line Tools (swiftc) on macOS 13 or later.
set -e
cd "$(dirname "$0")"

ARCH="$(uname -m)"   # arm64 or x86_64
rm -rf build
mkdir -p build/Focus.app/Contents/MacOS

echo "Compiling for ${ARCH}..."
swiftc -parse-as-library -O -target "${ARCH}-apple-macosx13.0" main.swift -o build/Focus.app/Contents/MacOS/Focus
cp Info.plist build/Focus.app/Contents/Info.plist
codesign --force --sign - build/Focus.app

echo "Installing to /Applications..."
pkill -x Focus 2>/dev/null || true
rm -rf /Applications/Focus.app
cp -R build/Focus.app /Applications/
open /Applications/Focus.app
echo "Done. Look for the timer icon in the menu bar."
