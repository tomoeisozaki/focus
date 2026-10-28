#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Focus.app and zips it for a GitHub release.
# Usage: ./release.sh
set -e
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
APP="dist/Focus.app"
ZIP="dist/Focus-${VERSION}-macOS.zip"

rm -rf build dist
mkdir -p build "$APP/Contents/MacOS"

for ARCH in arm64 x86_64; do
  echo "Compiling for ${ARCH}..."
  swiftc -parse-as-library -O -target "${ARCH}-apple-macosx13.0" main.swift -o "build/Focus-${ARCH}"
done
lipo -create -output "$APP/Contents/MacOS/Focus" build/Focus-arm64 build/Focus-x86_64
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Created ${ZIP}"
lipo -archs "$APP/Contents/MacOS/Focus"
shasum -a 256 "$ZIP"
