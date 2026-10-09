#!/bin/bash
set -e

# ─── Configuration ───────────────────────────────────────────────
VERSION="${VERSION:-1.1.0}"
IDENTIFIER="com.isdelnorte.nomusic"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
STAGING="$BUILD_DIR/staging"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"

: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP (e.g. 'Developer ID Application: Name (TEAMID)')}"
: "${DEVELOPER_ID_INSTALLER:?Set DEVELOPER_ID_INSTALLER (e.g. 'Developer ID Installer: Name (TEAMID)')}"
# Notarization credentials live in the login Keychain, never in .env. Create the profile once
# with the App Store Connect API key (.p8), which is also backed up outside this Mac:
#   xcrun notarytool store-credentials isdelnorte-notary \
#     --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER_ID>
NOTARY_PROFILE="${NOTARY_PROFILE:-isdelnorte-notary}"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
    echo "Error: Keychain profile '$NOTARY_PROFILE' not found or invalid. Create it with:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --key <AuthKey.p8> --key-id <KEYID> --issuer <ISSUER_ID>" >&2
    exit 1
fi

echo "==> Building NoMusic $VERSION"

# ─── Clean ────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$STAGING/usr/local/bin" "$STAGING/Library/LaunchAgents" "$PKG_SCRIPTS"

# ─── Compile universal binary ─────────────────────────────────────
echo "==> Compiling arm64..."
swiftc "$SCRIPT_DIR/nomusic.swift" -o "$BUILD_DIR/nomusic-arm64" -O \
    -target arm64-apple-macosx11.0

echo "==> Compiling x86_64..."
swiftc "$SCRIPT_DIR/nomusic.swift" -o "$BUILD_DIR/nomusic-x86_64" -O \
    -target x86_64-apple-macosx10.15

echo "==> Creating universal binary..."
lipo -create "$BUILD_DIR/nomusic-arm64" "$BUILD_DIR/nomusic-x86_64" \
    -output "$STAGING/usr/local/bin/nomusic"
chmod +x "$STAGING/usr/local/bin/nomusic"

# ─── Sign the binary ──────────────────────────────────────────────
echo "==> Signing binary..."
codesign --sign "$DEVELOPER_ID_APP" \
    --options runtime \
    --entitlements "$SCRIPT_DIR/entitlements.plist" \
    --timestamp \
    "$STAGING/usr/local/bin/nomusic"

# ─── LaunchAgent (system-wide, from the shared template) ──────────
sed "s|__NOMUSIC_BIN__|/usr/local/bin/nomusic|" "$SCRIPT_DIR/$IDENTIFIER.plist" \
    > "$STAGING/Library/LaunchAgents/$IDENTIFIER.plist"
chmod 644 "$STAGING/Library/LaunchAgents/$IDENTIFIER.plist"

# ─── Build Uninstaller.app ────────────────────────────────────────
echo "==> Building Uninstaller.app..."
UNINSTALLER="$STAGING/Applications/NoMusic Uninstaller.app/Contents"
mkdir -p "$UNINSTALLER/MacOS"
cp "$SCRIPT_DIR/uninstaller/Info.plist" "$UNINSTALLER/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$UNINSTALLER/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$UNINSTALLER/Info.plist"
cp "$SCRIPT_DIR/uninstaller/uninstall" "$UNINSTALLER/MacOS/uninstall"
chmod +x "$UNINSTALLER/MacOS/uninstall"

echo "==> Signing Uninstaller.app..."
codesign --sign "$DEVELOPER_ID_APP" \
    --options runtime \
    --timestamp \
    --deep \
    "$STAGING/Applications/NoMusic Uninstaller.app"

# ─── Prepare pkg scripts ──────────────────────────────────────────
cp "$SCRIPT_DIR/scripts/preinstall" "$PKG_SCRIPTS/preinstall"
cp "$SCRIPT_DIR/scripts/postinstall" "$PKG_SCRIPTS/postinstall"
chmod +x "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"

# ─── Build component pkg ──────────────────────────────────────────
echo "==> Building component package..."
pkgbuild \
    --root "$STAGING" \
    --scripts "$PKG_SCRIPTS" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location / \
    "$BUILD_DIR/NoMusic-component.pkg"

# ─── Build distribution pkg ───────────────────────────────────────
echo "==> Building distribution package..."
sed "s|__VERSION__|$VERSION|" "$SCRIPT_DIR/distribution.xml" > "$BUILD_DIR/distribution.xml"
productbuild \
    --distribution "$BUILD_DIR/distribution.xml" \
    --resources "$SCRIPT_DIR/pkg-resources" \
    --package-path "$BUILD_DIR" \
    "$BUILD_DIR/NoMusic-unsigned.pkg"

# ─── Sign the pkg ─────────────────────────────────────────────────
echo "==> Signing package..."
productsign \
    --sign "$DEVELOPER_ID_INSTALLER" \
    "$BUILD_DIR/NoMusic-unsigned.pkg" \
    "$BUILD_DIR/NoMusic-$VERSION.pkg"

# ─── Notarize ─────────────────────────────────────────────────────
echo "==> Submitting for notarization..."
xcrun notarytool submit "$BUILD_DIR/NoMusic-$VERSION.pkg" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$BUILD_DIR/NoMusic-$VERSION.pkg"

# ─── Cleanup intermediates ────────────────────────────────────────
rm -rf "$STAGING" "$PKG_SCRIPTS"
rm -f "$BUILD_DIR/nomusic-arm64" "$BUILD_DIR/nomusic-x86_64"
rm -f "$BUILD_DIR/NoMusic-component.pkg" "$BUILD_DIR/NoMusic-unsigned.pkg" "$BUILD_DIR/distribution.xml"

echo ""
echo "==> Done! Package ready at: build/NoMusic-$VERSION.pkg"
