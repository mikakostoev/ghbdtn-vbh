#!/bin/sh
# Builds LayoutSwitcher.app next to this script, for this Mac and signed with the local identity.
# release.sh overrides: OUT (where to put the app), UNIVERSAL=1 (Apple silicon + Intel), IDENTITY, VERSION.
set -e
cd "$(dirname "$0")"
# Xcode license not accepted -> fall back to Command Line Tools
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || export DEVELOPER_DIR=/Library/Developer/CommandLineTools
BUNDLE="${OUT:-.}/LayoutSwitcher.app"
APP="$BUNDLE/Contents"
rm -rf "$BUNDLE" && mkdir -p "$APP/MacOS"
if [ -n "$UNIVERSAL" ]; then
    # Both architectures land in the same products folder, so each is copied out before the next build.
    for arch in arm64 x86_64; do
        swift build -c release --triple "$arch-apple-macosx"
        cp "$(swift build -c release --triple "$arch-apple-macosx" --show-bin-path)/LayoutSwitcher" "$APP/MacOS/$arch"
    done
    lipo -create "$APP/MacOS/arm64" "$APP/MacOS/x86_64" -output "$APP/MacOS/LayoutSwitcher"
    rm "$APP/MacOS/arm64" "$APP/MacOS/x86_64"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/LayoutSwitcher" "$APP/MacOS/"
fi
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.layoutswitcher</string>
<key>CFBundleName</key><string>LayoutSwitcher</string>
<key>CFBundleExecutable</key><string>LayoutSwitcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc (-) changes the code hash every
# build, so macOS forgets the app. Create the identity once in Keychain Access > Certificate Assistant >
# Create a Certificate (self-signed root, type Code Signing), named as below.
IDENTITY="${IDENTITY:-LayoutSwitcher Local Signing}"
[ "$IDENTITY" = - ] || security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || { echo "No '$IDENTITY' certificate, signing ad-hoc"; IDENTITY=-; }
codesign --force -s "$IDENTITY" "$BUNDLE"
echo "Built $BUNDLE"
