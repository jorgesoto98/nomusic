#!/bin/bash
set -e

echo "Uninstalling NoMusic..."

launchctl bootout "gui/$(id -u)/com.isdelnorte.nomusic" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.isdelnorte.nomusic.plist"
rm -f "$HOME/.local/bin/nomusic"

echo "NoMusic uninstalled."
