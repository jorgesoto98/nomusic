# NoMusic .pkg Installer — Implementation Plan

> **Histórico.** Este plan se ejecutó para la versión 1.0.0 (commit `9600202`) y no se
> mantiene al día. El 2026-10-09 cambió el diseño: el LaunchAgent ya no se escribe en
> `~/Library/LaunchAgents` desde `postinstall`, sino que va en el payload en
> `/Library/LaunchAgents`, generado desde la plantilla compartida. El código de abajo de
> `preinstall`, `postinstall`, `uninstall` y `build-pkg.sh` ya no es el vigente. Para el
> diseño actual, ver `../specs/2026-04-01-pkg-installer-design.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a signed, notarized .pkg installer so non-technical users can install NoMusic with a double-click.

**Architecture:** Build script compiles a universal binary, bundles it with install scripts and an Uninstaller.app into a .pkg, then signs and notarizes it. The .pkg installs the binary to `/usr/local/bin/`, sets up the LaunchAgent in the user's home, and places an Uninstaller in `/Applications/`.

**Tech Stack:** Swift (swiftc), pkgbuild, productbuild, productsign, codesign, notarytool, stapler, lipo, osascript.

**Design change from spec:** Binary installs to `/usr/local/bin/nomusic` instead of `~/.local/bin/nomusic`. This is cleaner for .pkg since it's a standard system location writable by root, and eliminates `$HOME` substitution in the plist's `ProgramArguments`. The existing `install.sh` keeps its `~/.local/bin/` approach for manual installs.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/preinstall` | Create | Stop existing LaunchAgent before installation |
| `scripts/postinstall` | Create | Set up LaunchAgent plist, register and start agent |
| `uninstaller/Info.plist` | Create | App bundle metadata for Uninstaller.app |
| `uninstaller/uninstall` | Create | Bash script that performs uninstallation with confirmation dialogs |
| `pkg-resources/welcome.html` | Create | Welcome page shown in the .pkg installer wizard |
| `distribution.xml` | Create | Controls .pkg wizard UI, OS requirements, architecture |
| `build-pkg.sh` | Create | Master build script: compile, package, sign, notarize |
| `.gitignore` | Modify | Add `build/` directory |
| `README.md` | Modify | Add .pkg download instructions for non-technical users |

---

### Task 1: Create pkg install scripts

**Files:**
- Create: `scripts/preinstall`
- Create: `scripts/postinstall`

- [ ] **Step 1: Create `scripts/preinstall`**

```bash
#!/bin/bash
# preinstall — runs as root before .pkg payload is extracted
# Stops existing NoMusic LaunchAgent if present

CONSOLE_USER=$(stat -f "%Su" /dev/console)
CONSOLE_UID=$(id -u "$CONSOLE_USER")

launchctl bootout "gui/$CONSOLE_UID/com.isdelnorte.nomusic" 2>/dev/null || true

exit 0
```

- [ ] **Step 2: Create `scripts/postinstall`**

This script runs as root after the .pkg payload is installed. It sets up the LaunchAgent for the logged-in user.

```bash
#!/bin/bash
# postinstall — runs as root after .pkg payload is extracted
# Binary is already at /usr/local/bin/nomusic (installed by pkg payload)
# This script creates the LaunchAgent plist and starts the service

CONSOLE_USER=$(stat -f "%Su" /dev/console)
CONSOLE_HOME=$(dscl . -read /Users/"$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')
CONSOLE_UID=$(id -u "$CONSOLE_USER")

AGENTS_DIR="$CONSOLE_HOME/Library/LaunchAgents"
PLIST_NAME="com.isdelnorte.nomusic.plist"

mkdir -p "$AGENTS_DIR"

# Generate plist pointing to the system-wide binary location
cat > "$AGENTS_DIR/$PLIST_NAME" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.isdelnorte.nomusic</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/nomusic</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLIST

chown "$CONSOLE_USER" "$AGENTS_DIR/$PLIST_NAME"

launchctl bootstrap "gui/$CONSOLE_UID" "$AGENTS_DIR/$PLIST_NAME"

sleep 1
if launchctl print "gui/$CONSOLE_UID/com.isdelnorte.nomusic" &>/dev/null; then
    exit 0
else
    exit 1
fi
```

- [ ] **Step 3: Make both scripts executable**

```bash
chmod +x scripts/preinstall scripts/postinstall
```

- [ ] **Step 4: Verify scripts have correct shebang and are executable**

Run: `head -1 scripts/preinstall scripts/postinstall && ls -la scripts/`
Expected: Both show `#!/bin/bash` and have `x` permission.

- [ ] **Step 5: Commit**

```bash
git add scripts/preinstall scripts/postinstall
git commit -m "feat(pkg): agregar scripts de instalacion para .pkg"
```

---

### Task 2: Create Uninstaller.app resources

**Files:**
- Create: `uninstaller/Info.plist`
- Create: `uninstaller/uninstall`

- [ ] **Step 1: Create `uninstaller/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>uninstall</string>
    <key>CFBundleIdentifier</key>
    <string>com.isdelnorte.nomusic.uninstaller</string>
    <key>CFBundleName</key>
    <string>NoMusic Uninstaller</string>
    <key>CFBundleDisplayName</key>
    <string>NoMusic Uninstaller</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 2: Create `uninstaller/uninstall`**

```bash
#!/bin/bash
# NoMusic Uninstaller
# Double-click this .app to remove NoMusic completely

CONSOLE_USER=$(stat -f "%Su" /dev/console)
CONSOLE_UID=$(id -u "$CONSOLE_USER")
CONSOLE_HOME=$(dscl . -read /Users/"$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')

# Confirmation dialog
RESPONSE=$(osascript -e 'display dialog "Do you want to uninstall NoMusic?\n\nThis will stop the background service and remove all files." buttons {"Cancel", "Uninstall"} default button "Cancel" with icon caution with title "NoMusic Uninstaller"' 2>&1)

if [[ "$RESPONSE" != *"Uninstall"* ]]; then
    exit 0
fi

# Stop the LaunchAgent (user-level, no admin needed)
launchctl bootout "gui/$CONSOLE_UID/com.isdelnorte.nomusic" 2>/dev/null || true

# Remove user-level plist (no admin needed)
rm -f "$CONSOLE_HOME/Library/LaunchAgents/com.isdelnorte.nomusic.plist"

# Remove system-level binary and this app (needs admin)
osascript -e 'do shell script "rm -f /usr/local/bin/nomusic && rm -rf /Applications/NoMusic\\ Uninstaller.app" with administrator privileges' 2>/dev/null

if [ $? -eq 0 ]; then
    osascript -e 'display dialog "NoMusic has been uninstalled successfully." buttons {"OK"} default button "OK" with title "NoMusic Uninstaller"'
else
    osascript -e 'display dialog "Uninstallation was cancelled or failed.\nThe LaunchAgent has been stopped but files may remain." buttons {"OK"} default button "OK" with icon caution with title "NoMusic Uninstaller"'
fi
```

- [ ] **Step 3: Make uninstall script executable**

```bash
chmod +x uninstaller/uninstall
```

- [ ] **Step 4: Verify structure**

Run: `ls -la uninstaller/ && head -1 uninstaller/uninstall`
Expected: `Info.plist` and executable `uninstall` with `#!/bin/bash`.

- [ ] **Step 5: Commit**

```bash
git add uninstaller/Info.plist uninstaller/uninstall
git commit -m "feat(pkg): agregar NoMusic Uninstaller.app resources"
```

---

### Task 3: Create distribution.xml and welcome.html

**Files:**
- Create: `distribution.xml`
- Create: `pkg-resources/welcome.html`

- [ ] **Step 1: Create `pkg-resources/welcome.html`**

```html
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, Helvetica Neue, sans-serif; padding: 20px; color: #333; }
        h1 { font-size: 24px; }
        p { font-size: 14px; line-height: 1.6; }
        ul { font-size: 14px; line-height: 1.8; }
    </style>
</head>
<body>
    <h1>NoMusic</h1>
    <p>Replace Apple Music with Spotify for your media keys.</p>
    <p>When you press Play/Pause without an audio app open, macOS opens Apple Music automatically. NoMusic intercepts that and opens Spotify instead.</p>
    <p>This installer will:</p>
    <ul>
        <li>Install the NoMusic background service</li>
        <li>Configure it to start automatically at login</li>
        <li>Install "NoMusic Uninstaller" in your Applications folder</li>
    </ul>
    <p><strong>Requirement:</strong> Spotify must be installed.</p>
</body>
</html>
```

- [ ] **Step 2: Create `distribution.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>NoMusic</title>
    <welcome file="welcome.html"/>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="10.15"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="com.isdelnorte.nomusic"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.isdelnorte.nomusic" visible="false">
        <pkg-ref id="com.isdelnorte.nomusic"/>
    </choice>
    <pkg-ref id="com.isdelnorte.nomusic" version="1.0.0" onConclusion="none">NoMusic-component.pkg</pkg-ref>
</installer-gui-script>
```

- [ ] **Step 3: Commit**

```bash
git add distribution.xml pkg-resources/welcome.html
git commit -m "feat(pkg): agregar distribution.xml y pagina de bienvenida"
```

---

### Task 4: Create build-pkg.sh

**Files:**
- Create: `build-pkg.sh`

- [ ] **Step 1: Create `build-pkg.sh`**

```bash
#!/bin/bash
set -e

# ─── Configuration ───────────────────────────────────────────────
VERSION="${VERSION:-1.0.0}"
IDENTIFIER="com.isdelnorte.nomusic"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
STAGING="$BUILD_DIR/staging"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"

# Signing identities (from environment)
: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP (e.g. 'Developer ID Application: Name (TEAMID)')}"
: "${DEVELOPER_ID_INSTALLER:?Set DEVELOPER_ID_INSTALLER (e.g. 'Developer ID Installer: Name (TEAMID)')}"

# Notarization credentials (from environment)
: "${APPLE_ID:?Set APPLE_ID (your Apple ID email)}"
: "${TEAM_ID:?Set TEAM_ID (your Apple Developer Team ID)}"
: "${APP_PASSWORD:?Set APP_PASSWORD (app-specific password from appleid.apple.com)}"

echo "==> Building NoMusic $VERSION"

# ─── Clean ────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$STAGING/usr/local/bin" "$PKG_SCRIPTS"

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
    --timestamp \
    "$STAGING/usr/local/bin/nomusic"

# ─── Build Uninstaller.app ────────────────────────────────────────
echo "==> Building Uninstaller.app..."
UNINSTALLER="$STAGING/Applications/NoMusic Uninstaller.app/Contents"
mkdir -p "$UNINSTALLER/MacOS"
cp "$SCRIPT_DIR/uninstaller/Info.plist" "$UNINSTALLER/Info.plist"
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
productbuild \
    --distribution "$SCRIPT_DIR/distribution.xml" \
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
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$BUILD_DIR/NoMusic-$VERSION.pkg"

# ─── Cleanup intermediates ────────────────────────────────────────
rm -rf "$STAGING" "$PKG_SCRIPTS"
rm -f "$BUILD_DIR/nomusic-arm64" "$BUILD_DIR/nomusic-x86_64"
rm -f "$BUILD_DIR/NoMusic-component.pkg" "$BUILD_DIR/NoMusic-unsigned.pkg"

echo ""
echo "==> Done! Package ready at: build/NoMusic-$VERSION.pkg"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x build-pkg.sh
```

- [ ] **Step 3: Verify script syntax**

Run: `bash -n build-pkg.sh`
Expected: No output (no syntax errors).

- [ ] **Step 4: Commit**

```bash
git add build-pkg.sh
git commit -m "feat(pkg): agregar script maestro de build para .pkg"
```

---

### Task 5: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Read current .gitignore**

Run: `cat .gitignore`

- [ ] **Step 2: Add `build/` to .gitignore**

Append `build/` to the file.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: agregar build/ a gitignore"
```

---

### Task 6: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add .pkg download section to English part**

After the `## English` heading and description, add a new section before "How it works":

```markdown
### Quick Install (recommended)

1. **Download** the latest `NoMusic.pkg` from [Releases](https://github.com/jorgesoto98/nomusic/releases)
2. **Double-click** the `.pkg` file
3. **Follow the installer** — click "Install" and enter your password
4. Done — NoMusic is running in the background

To uninstall, open **NoMusic Uninstaller** from your Applications folder.

### Manual Install (for developers)
```

Then the existing installation steps follow under "Manual Install".

- [ ] **Step 2: Add .pkg download section to Spanish part**

Same structure for the Spanish section:

```markdown
### Instalacion rapida (recomendada)

1. **Descarga** el ultimo `NoMusic.pkg` de [Releases](https://github.com/jorgesoto98/nomusic/releases)
2. **Doble-click** en el archivo `.pkg`
3. **Sigue el instalador** — click en "Instalar" e ingresa tu contraseña
4. Listo — NoMusic esta corriendo en segundo plano

Para desinstalar, abre **NoMusic Uninstaller** desde tu carpeta de Aplicaciones.

### Instalacion manual (para desarrolladores)
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: agregar instrucciones de instalacion via .pkg"
```

---

### Task 7: Verify full build pipeline

- [ ] **Step 1: Check all new files exist and are executable**

Run:
```bash
ls -la scripts/preinstall scripts/postinstall uninstaller/uninstall build-pkg.sh
cat distribution.xml | head -3
cat pkg-resources/welcome.html | head -3
```

Expected: All files present, scripts have `x` permission, XML and HTML have correct headers.

- [ ] **Step 2: Test compilation of universal binary (unsigned)**

Run:
```bash
mkdir -p /tmp/nomusic-test
swiftc nomusic.swift -o /tmp/nomusic-test/arm64 -O -target arm64-apple-macosx11.0
swiftc nomusic.swift -o /tmp/nomusic-test/x86_64 -O -target x86_64-apple-macosx10.15
lipo -create /tmp/nomusic-test/arm64 /tmp/nomusic-test/x86_64 -output /tmp/nomusic-test/nomusic
file /tmp/nomusic-test/nomusic
rm -rf /tmp/nomusic-test
```

Expected: `Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]`

- [ ] **Step 3: Test unsigned pkg build (without signing/notarization)**

This validates the pkgbuild/productbuild pipeline without needing credentials. Create a temporary test:

```bash
# Quick test: build without signing
VERSION=1.0.0 \
DEVELOPER_ID_APP="test" \
DEVELOPER_ID_INSTALLER="test" \
APPLE_ID="test" \
TEAM_ID="test" \
APP_PASSWORD="test" \
bash -x build-pkg.sh 2>&1 | head -20
```

Expected: Should succeed through the compile and staging steps, then fail at `codesign` (expected — confirms the pipeline structure works up to signing).

- [ ] **Step 4: Verify with real credentials (manual)**

This step is performed manually by the developer with real credentials:

```bash
export DEVELOPER_ID_APP="Developer ID Application: ..."
export DEVELOPER_ID_INSTALLER="Developer ID Installer: ..."
export APPLE_ID="..."
export TEAM_ID="..."
export APP_PASSWORD="..."

./build-pkg.sh
```

Expected: `build/NoMusic-1.0.0.pkg` exists, signed and notarized.
