#!/bin/sh
# Builds LayoutSwitcher.app next to this script.
set -e
cd "$(dirname "$0")"
# Xcode license not accepted -> fall back to Command Line Tools
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build -c release
APP="LayoutSwitcher.app/Contents"
rm -rf LayoutSwitcher.app && mkdir -p "$APP/MacOS"
cp .build/release/LayoutSwitcher "$APP/MacOS/"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.layoutswitcher</string>
<key>CFBundleName</key><string>LayoutSwitcher</string>
<key>CFBundleExecutable</key><string>LayoutSwitcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc (-) changes the code hash every
# build, so macOS forgets the app. Create the identity once in Keychain Access > Certificate Assistant >
# Create a Certificate (self-signed root, type Code Signing), named as below.
IDENTITY="LayoutSwitcher Local Signing"
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || { echo "No '$IDENTITY' certificate, signing ad-hoc"; IDENTITY=-; }
codesign --force -s "$IDENTITY" LayoutSwitcher.app
echo "Built $(pwd)/LayoutSwitcher.app"
