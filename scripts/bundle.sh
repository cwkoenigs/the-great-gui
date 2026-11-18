#!/bin/sh
# Build the app and wrap it as build/the-great-gui.app, signed with the identity this Mac has.
#   CONFIG=debug|release (release)  BUNDLE_ID (com.cwkoenigs.the-great-gui)  SIGN_IDENTITY (- = ad-hoc)
# Keychain ties access to the identifier plus the signing certificate: with ad-hoc signing every rebuild is
# a new app to Keychain and it asks again. A self-signed code-signing certificate made once in Keychain
# Access, passed as SIGN_IDENTITY, keeps the identity stable (DECISIONS local-004).
set -e
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
BUNDLE_ID="${BUNDLE_ID:-com.cwkoenigs.the-great-gui}"
# the identity: the environment, else the git-ignored .sign-identity file, else ad-hoc
SIGN_IDENTITY="${SIGN_IDENTITY:-$(head -1 .sign-identity 2>/dev/null || true)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/GreatGUI/Version.swift 2>/dev/null)"
[ -n "$VERSION" ] || { echo "✗ no version in Sources/GreatGUI/Version.swift (static let string = \"…\")" >&2; exit 1; }
# The commit this bundle is built from, "+changes" when the tree is not clean: what Settings and great-gui version show.
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"
[ -z "$COMMIT" ] || [ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] || COMMIT="$COMMIT+changes"
MIN_OS="$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1/p' Package.swift)"

swift build -c "$CONFIG" --product GreatGUI
APP=build/the-great-gui.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/GreatGUI" "$APP/Contents/MacOS/the-great-gui"
# SwiftPM resource bundles (the example registry) live beside the binary; the app finds them in Resources.
for b in ".build/$CONFIG"/*.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# The icon is committed; assets/make-icon.sh redraws it.
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>the-great-gui</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>the-great-gui</string>
  <key>CFBundleDisplayName</key><string>the-great-gui</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>GreatGUICommit</key><string>${COMMIT}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_OS}.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "✓ app  $APP · ${BUNDLE_ID} · signed with ${SIGN_IDENTITY}$( [ "$SIGN_IDENTITY" = "-" ] && echo ' (ad-hoc)' )"
