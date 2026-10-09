#!/bin/bash
# Quick checks before a release: compile, script syntax, plist template and
# pkg payload. Needs no signing credentials. The media-key test is still manual
# (see README).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LABEL="com.isdelnorte.nomusic"
FAILED=0

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1" >&2; FAILED=1; }

echo "==> Compile"
for TARGET in arm64-apple-macosx11.0 x86_64-apple-macosx10.15; do
    if OUT=$(swiftc "$SCRIPT_DIR/nomusic.swift" -O -target "$TARGET" -o "$TMP/nomusic-$TARGET" 2>&1); then
        if [ -n "$OUT" ]; then fail "$TARGET compiles with warnings:"; echo "$OUT" >&2; else pass "$TARGET"; fi
    else
        fail "$TARGET does not compile:"; echo "$OUT" >&2
    fi
done

echo "==> Shell scripts"
SCRIPTS=(install.sh uninstall.sh build-pkg.sh test.sh scripts/preinstall scripts/postinstall uninstaller/uninstall)
for F in "${SCRIPTS[@]}"; do
    if bash -n "$SCRIPT_DIR/$F" 2>"$TMP/err"; then pass "$F"; else fail "$F"; cat "$TMP/err" >&2; fi
done
if command -v shellcheck &>/dev/null; then
    if (cd "$SCRIPT_DIR" && shellcheck "${SCRIPTS[@]}"); then pass "shellcheck"; else fail "shellcheck"; fi
else
    echo "  skip shellcheck (brew install shellcheck)"
fi

echo "==> LaunchAgent template"
check_plist() {
    local BIN="$1" OUT="$TMP/$2.plist"
    sed "s|__NOMUSIC_BIN__|$BIN|" "$SCRIPT_DIR/$LABEL.plist" > "$OUT"
    if plutil -lint -s "$OUT" && [ "$(plutil -extract ProgramArguments.0 raw "$OUT")" = "$BIN" ] \
        && [ "$(plutil -extract Label raw "$OUT")" = "$LABEL" ]; then
        pass "$2 ($BIN)"
    else
        fail "$2 plist is invalid or has the wrong program path"
    fi
}
check_plist "/usr/local/bin/nomusic" pkg
check_plist "$HOME/.local/bin/nomusic" manual
if grep -q '__NOMUSIC_BIN__' "$SCRIPT_DIR/$LABEL.plist"; then pass "template has the __NOMUSIC_BIN__ marker"; else fail "template lost the __NOMUSIC_BIN__ marker"; fi

echo "==> Package payload (unsigned)"
# Mirrors the staging layout of build-pkg.sh.
ROOT="$TMP/root"
mkdir -p "$ROOT/usr/local/bin" "$ROOT/Library/LaunchAgents"
cp "$TMP/nomusic-arm64-apple-macosx11.0" "$ROOT/usr/local/bin/nomusic" 2>/dev/null || touch "$ROOT/usr/local/bin/nomusic"
sed "s|__NOMUSIC_BIN__|/usr/local/bin/nomusic|" "$SCRIPT_DIR/$LABEL.plist" > "$ROOT/Library/LaunchAgents/$LABEL.plist"
chmod 644 "$ROOT/Library/LaunchAgents/$LABEL.plist"
if pkgbuild --root "$ROOT" --identifier "$LABEL" --version 0 --install-location / "$TMP/test.pkg" >/dev/null \
    && pkgutil --expand "$TMP/test.pkg" "$TMP/expanded"; then
    BOM=$(lsbom "$TMP/expanded/Bom")
    # launchd ignores agents in /Library/LaunchAgents unless owned by root and not group/world-writable.
    if echo "$BOM" | grep -qE "^\./Library/LaunchAgents/$LABEL\.plist	100644	0/0"; then
        pass "plist installed as root:wheel 644"
    else
        fail "plist has the wrong owner or permissions in the payload"
    fi
    if echo "$BOM" | grep -qE "^\./usr/local/bin/nomusic	1007[0-9]{2}	0/0"; then
        pass "binary installed as root:wheel and executable"
    else
        fail "binary has the wrong owner or permissions in the payload"
    fi
else
    fail "pkgbuild could not build the test package"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All checks passed. Still to do by hand: press Play with Apple Music closed and confirm Spotify plays."
else
    echo "Some checks failed." >&2
    exit 1
fi
