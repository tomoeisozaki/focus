#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Fokus.app and zips it for a GitHub release.
# Usage: ./release.sh
set -e
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
APP="dist/Fokus.app"
ZIP="dist/Fokus-${VERSION}-macOS.zip"

rm -rf build dist
mkdir -p build "$APP/Contents/MacOS"

for ARCH in arm64 x86_64; do
  echo "Compiling for ${ARCH}..."
  swiftc -parse-as-library -O -target "${ARCH}-apple-macosx13.0" main.swift -o "build/Fokus-${ARCH}"
done
lipo -create -output "$APP/Contents/MacOS/Fokus" build/Fokus-arm64 build/Fokus-x86_64
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Created ${ZIP}"
lipo -archs "$APP/Contents/MacOS/Fokus"
shasum -a 256 "$ZIP"
