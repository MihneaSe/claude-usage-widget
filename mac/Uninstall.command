#!/bin/bash
# Claude Usage Widget for macOS - uninstall. Leaves Claude Code untouched.
APP="$HOME/Applications/Claude Usage Widget.app"
BUNDLE_ID="com.github.mihnease.claude-usage-widget"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

answer="$(osascript -e 'button returned of (display dialog "Remove Claude Usage Widget from this Mac?" buttons {"Cancel", "Remove"} default button "Remove" with title "Claude Usage Widget")' 2>/dev/null)"
[ "$answer" = "Remove" ] || exit 0

pkill -f "Claude Usage Widget.app/Contents/MacOS/ClaudeUsageWidget" 2>/dev/null
rm -f "$AGENT"
rm -rf "$APP"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1
echo "Claude Usage Widget removed. Claude Code itself was left untouched."
read -r -n 1 -p "Press any key to close this window." _; echo
