#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLIST_NAME="com.isdelnorte.nomusic.plist"
AGENTS_DIR="$HOME/Library/LaunchAgents"

if [ -f "/Library/LaunchAgents/$PLIST_NAME" ]; then
    echo "Error: NoMusic is already installed from the .pkg. Run \"NoMusic Uninstaller\" first." >&2
    exit 1
fi

echo "Compiling NoMusic..."
swiftc "$SCRIPT_DIR/nomusic.swift" -o "$SCRIPT_DIR/nomusic" -O

echo "Installing NoMusic..."
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/nomusic" "$BIN_DIR/nomusic"
chmod +x "$BIN_DIR/nomusic"
rm "$SCRIPT_DIR/nomusic"

mkdir -p "$AGENTS_DIR"
sed "s|__NOMUSIC_BIN__|$BIN_DIR/nomusic|" "$SCRIPT_DIR/$PLIST_NAME" > "$AGENTS_DIR/$PLIST_NAME"

launchctl bootout "gui/$(id -u)/com.isdelnorte.nomusic" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENTS_DIR/$PLIST_NAME"

sleep 1
if launchctl print "gui/$(id -u)/com.isdelnorte.nomusic" &>/dev/null; then
    echo "NoMusic installed and running."
else
    echo "Error: NoMusic failed to start." >&2
    exit 1
fi
