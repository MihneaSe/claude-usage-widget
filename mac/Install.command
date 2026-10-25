#!/bin/bash
# Claude Usage Widget for macOS - setup (install / update)
# ---------------------------------------------------------------------------
# Checks the requirements, builds the widget from source on this Mac,
# installs it to ~/Applications and (if you say yes) starts it at login.
# No admin rights, no Homebrew, no Python, no downloads.
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")" || exit 1

VERSION="$(cat ../VERSION 2>/dev/null || echo dev)"
VERSION="${VERSION//[$'\r\n ']}"
APP="$HOME/Applications/Claude Usage Widget.app"
BIN="$APP/Contents/MacOS/ClaudeUsageWidget"
BUNDLE_ID="com.github.mihnease.claude-usage-widget"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

green=$'\033[32m'; amber=$'\033[33m'; red=$'\033[31m'; dim=$'\033[2m'; off=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$green" "$off" "$1"; }
warn() { printf '  %s!%s %s\n' "$amber" "$off" "$1"; }
fail() { printf '  %s✗%s %s\n' "$red" "$off" "$1"; }
finish() { echo; read -r -n 1 -p "Press any key to close this window." _; echo; exit "${1:-0}"; }

echo
echo "Claude Usage Widget v$VERSION for macOS - setup"
echo "${dim}No Python, Node.js, Homebrew or admin rights needed.${off}"
echo
echo "Checklist"

# 1. macOS version
mac="$(sw_vers -productVersion)"
if [ "${mac%%.*}" -ge 11 ]; then ok "macOS $mac"
else fail "macOS $mac is too old. macOS 11 Big Sur or later is needed."; finish 1; fi

# 2. Swift compiler (Xcode Command Line Tools) - builds the widget on this Mac
if xcrun --find swiftc >/dev/null 2>&1; then
    ok "Xcode Command Line Tools (Swift compiler)"
else
    fail "Xcode Command Line Tools are missing. A window will open to install them (free, from Apple)."
    xcode-select --install >/dev/null 2>&1
    echo "     When that install finishes, double-click Install.command again."
    finish 1
fi

# 3. Claude Code installed
find_claude() {
    CLAUDE=""
    for c in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
        if [ -x "$c" ]; then CLAUDE="$c"; return; fi
    done
    CLAUDE="$(/bin/zsh -lc 'command -v claude' 2>/dev/null)"
}
sign_in() {
    echo
    echo "     Sign in to Claude Code:"
    echo "       1. Claude Code opens below and asks you to log in."
    echo "       2. Pick your Claude account and finish the login in your browser."
    echo "       3. Back here, type  /exit  and press Enter to continue setup."
    echo
    read -r -n 1 -p "     Press any key to open Claude Code..." _ </dev/tty; echo
    "$CLAUDE" </dev/tty
    echo
}
find_claude
if [ -n "$CLAUDE" ] && [ -x "$CLAUDE" ]; then
    ok "Claude Code installed: $("$CLAUDE" --version 2>/dev/null | head -n 1)"
else
    fail "Claude Code is not installed. The Claude desktop app doesn't include it."
    echo "     How to install it (Anthropic's official installer, no admin rights):"
    echo "       1. In Terminal run:  curl -fsSL https://claude.ai/install.sh | bash"
    echo "       2. Then run:  claude   - sign in with your Claude account, then type /exit"
    echo "       3. Run this setup again."
    echo "     Needs a Pro, Max, Team or Enterprise plan (the free plan doesn't include Claude Code)."
    answer="$(osascript -e 'button returned of (display dialog "Claude Code is not installed. Install it now with Anthropic'"'"'s official installer?" buttons {"Not now", "Install"} default button "Install" with title "Claude Usage Widget")' 2>/dev/null)"
    if [ "$answer" != "Install" ]; then finish 1; fi
    echo
    echo "     Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    find_claude
    if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
        fail "Claude Code install didn't finish. Run step 1 above by hand, then this setup again."
        finish 1
    fi
    ok "Claude Code installed: $("$CLAUDE" --version 2>/dev/null | head -n 1)"
    sign_in
fi

# 4. Claude Code on your PATH (only matters for using it in Terminal; the widget finds it anyway)
if /bin/zsh -lc 'command -v claude' >/dev/null 2>&1; then
    ok "Claude Code on your PATH"
else
    dir="$(dirname "$CLAUDE")"
    answer="$(osascript -e 'button returned of (display dialog "Claude Code isn'"'"'t on your Terminal PATH, so typing claude in Terminal won'"'"'t work. Add it to ~/.zshrc? (The widget works either way.)" buttons {"Skip", "Add"} default button "Add" with title "Claude Usage Widget")' 2>/dev/null)"
    if [ "$answer" = "Add" ]; then
        printf '\n# Added by Claude Usage Widget setup\nexport PATH="%s:$PATH"\n' "$dir" >> "$HOME/.zshrc"
        ok "Added $dir to your PATH (in ~/.zshrc; open a new Terminal window to use it)"
    else
        warn "Claude Code isn't on your Terminal PATH. The widget still works."
    fi
fi

# 5. Signed in and /usage readable (with a 45 s time limit)
printf '  %s…%s Asking Claude Code for your usage (a few seconds)\r' "$dim" "$off"
out="$(perl -e 'alarm 45; exec @ARGV' "$CLAUDE" -p /usage --output-format text --no-session-persistence 2>&1 </dev/null)"
printf '\033[2K'
s="$(printf '%s' "$out" | grep -o 'Current session: [0-9]*%' | grep -o '[0-9]*%' | head -n 1)"
w="$(printf '%s' "$out" | grep -o 'Current week (all models): [0-9]*%' | grep -o '[0-9]*%' | head -n 1)"
if [ -n "$s$w" ]; then
    ok "Signed in, /usage works: session ${s:---}, week ${w:---}"
elif printf '%s' "$out" | grep -qiE 'log ?in|not authenticated|auth'; then
    fail "Claude Code is installed but not signed in."
    sign_in
    out="$(perl -e 'alarm 45; exec @ARGV' "$CLAUDE" -p /usage --output-format text --no-session-persistence 2>&1 </dev/null)"
    s="$(printf '%s' "$out" | grep -o 'Current session: [0-9]*%' | grep -o '[0-9]*%' | head -n 1)"
    w="$(printf '%s' "$out" | grep -o 'Current week (all models): [0-9]*%' | grep -o '[0-9]*%' | head -n 1)"
    if [ -n "$s$w" ]; then ok "Signed in, /usage works: session ${s:---}, week ${w:---}"
    else fail "Still not signed in. Run  claude , sign in, type /exit, then run this setup again."; finish 1; fi
else
    warn "Unexpected answer from /usage (plan without limits, or a new format). The widget may show \"unexpected output\"."
fi

# Build
echo
echo "Building the widget on this Mac..."
mkdir -p "$APP/Contents/MacOS"
if ! xcrun swiftc -O -o "$BIN.new" ClaudeUsageWidget.swift 2> "$TMPDIR/claude-usage-widget-build.log"; then
    fail "Build failed. Details: $TMPDIR/claude-usage-widget-build.log"
    tail -n 20 "$TMPDIR/claude-usage-widget-build.log"
    finish 1
fi

# Stop a running copy before replacing it
pkill -f "Claude Usage Widget.app/Contents/MacOS/ClaudeUsageWidget" 2>/dev/null && sleep 1
mv -f "$BIN.new" "$BIN"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Usage Widget</string>
  <key>CFBundleDisplayName</key><string>Claude Usage Widget</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>ClaudeUsageWidget</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || warn "Could not sign the app locally (it should still run)."
ok "Installed v$VERSION in ~/Applications"

# Start at login?
answer="$(osascript -e 'button returned of (display dialog "Start Claude Usage Widget when you log in?" buttons {"No", "Yes"} default button "Yes" with title "Claude Usage Widget")' 2>/dev/null)"
if [ "$answer" = "Yes" ]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    ok "Will start at login"
else
    rm -f "$AGENT"
    ok "Won't start at login (open it from ~/Applications)"
fi

open "$APP"
echo
echo "Done: the widget is in your menu bar and on screen. Right-click it for options."
finish 0
