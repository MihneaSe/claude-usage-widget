# claude-usage-widget

**Version 1.2.2** · see [CHANGELOG.md](CHANGELOG.md)

A tiny, read-only Windows and macOS widget that shows your Claude Code plan usage: the current
5-hour session and the weekly limit, each with time left until reset.

- The % number changes colour every 20% (ink, sage, amber, clay, red).
- Reset times are shown as countdowns: `resets in 1h 08m`, `resets in 3d 4h`.
- Fades to 10% opacity when the mouse is over it, so it never hides what's underneath.
- Light cream theme inspired by the Claude interface. Not affiliated with Anthropic.

## Why it's safe

The only thing it ever runs is:

```
claude -p /usage --output-format text --no-session-persistence
```

every 2 minutes. `/usage` is a slash command, so no model is called. Beyond that:

- No network calls of its own, no telemetry, no location or weather lookups.
- No admin rights, scheduled tasks, registry changes or autostart.
- No chat, no AI-generated scripts, no PC scanning.
- Writes only `settings.json` (window position) and `widget-error.log` (errors only,
  never your usage output), both in its own folder.
- One readable PowerShell file, no dependencies.

## Requirements

- Windows 10 or 11 (Windows PowerShell 5.1 and WPF are built in)
- [Claude Code](https://code.claude.com/docs/en/setup) installed, signed in, and `claude` on your PATH
- A Claude plan that includes Claude Code and has usage limits:

  | Plan | Status |
  | --- | --- |
  | Pro | Tested, works |
  | Enterprise | Tested, works |
  | Max, Team | Should work (same `/usage` limits), not yet tested |
  | API key / Console | Not supported: no plan limits to show |
  | Free | Not supported: doesn't include Claude Code |

Check it works first, in PowerShell (not Git Bash):

```
claude -p /usage --output-format text --no-session-persistence
```

You should see lines starting with `Current session:` and `Current week (all models):`.

## Don't have Claude Code yet?

The Claude desktop app doesn't include the `claude` command; install Claude Code separately
(Pro, Max, Team or Enterprise plan). Both setups offer to do this for you, or by hand:

| | Mac (Terminal) | Windows (PowerShell) |
| --- | --- | --- |
| 1. Install | `curl -fsSL https://claude.ai/install.sh \| bash` | `irm https://claude.ai/install.ps1 \| iex` |
| 2. Sign in | run `claude`, log in in the browser, type `/exit` | same |
| 3. Check | `claude --version` | same (in a **new** PowerShell window) |

If `claude` isn't found afterwards, add `~/.local/bin` (Mac) or `%USERPROFILE%\.local\bin`
(Windows) to your PATH. Source: [Claude Code setup docs](https://code.claude.com/docs/en/setup).

## Install

1. Download this repo as a ZIP (**Code → Download ZIP**) and unzip it anywhere.
2. Double-click **`Install.cmd`**. If Windows asks whether to run it, click **Run** / **More info → Run anyway**.
3. The setup window runs a checklist, then installs the widget with one click:

   | Check | Why it matters |
   | --- | --- |
   | Windows 10 or 11 | Built for Windows only |
   | Windows PowerShell 5.1 | Runs the widget (built into Windows) |
   | .NET Framework / WPF | Draws the window (built into Windows) |
   | VBScript | Starts the widget without a console window; falls back to PowerShell if missing |
   | PowerShell scripts allowed | Company group policy can block scripts |
   | Claude Code installed | The desktop app does **not** include the `claude` command |
   | Claude Code on PATH | The installer doesn't always add `%USERPROFILE%\.local\bin` |
   | Signed in and `/usage` readable | Confirms the widget will get real numbers |

   No Python, Node.js, Git or admin rights needed.

Setup installs to `%LOCALAPPDATA%\ClaudeUsageWidget`, adds a Start Menu shortcut and
(optionally) starts the widget with Windows. No admin rights needed. Run `Install.cmd`
again to update or uninstall; it shows which version is installed. The version is also shown
in the widget's right-click menu.

If Claude Code is missing, setup offers to open Anthropic's
[official installer](https://code.claude.com/docs/en/setup) in a PowerShell window, and
to add `%USERPROFILE%\.local\bin` to your PATH if needed. It only does these when you click.

<details>
<summary>Manual install (without setup)</summary>

1. Right-click `start-widget.vbs` → Properties → tick **Unblock** if shown → OK.
2. Double-click `start-widget.vbs`.
3. To start with Windows: Win+R → `shell:startup` → put a shortcut to `start-widget.vbs` there.
</details>

## macOS

The `mac/` folder has a native version: the same floating card, plus your session % in the
menu bar. It's built from source on your Mac during install, so there's nothing pre-compiled
to trust. **New in v1.2.0 and not yet tested on a Mac** — feedback welcome.

**Requirements:** macOS 11 or later, Xcode Command Line Tools (free; setup offers to install
them), Claude Code installed and signed in. No Homebrew, Python or admin rights.

**Install:**

1. Download the ZIP: <https://github.com/MihneaSe/claude-usage-widget/archive/refs/heads/main.zip>
   (Safari usually unzips it into Downloads as `claude-usage-widget-main`).
2. Open Terminal (Cmd+Space, type Terminal) and run:
   `bash ~/Downloads/claude-usage-widget-main/mac/Install.command`
   (or type `bash `, drag `mac/Install.command` into the window, press Enter). (Double-clicking also works, but macOS may block files downloaded from the
   internet; then use System Settings → Privacy & Security → Open Anyway.)
3. Setup runs a checklist, builds the app into `~/Applications`, and asks whether to start
   it at login.

To remove it, run `mac/Uninstall.command` the same way.

## Use

- Drag the widget anywhere; the position is remembered.
- Right-click the widget: refresh now, always on top, fade on mouse-over, hide, exit.
- Left-click the tray icon to show or hide; right-click it to exit.

## Troubleshooting

- **"unexpected output"**: the `/usage` text format changed or you're not signed in.
  Run the command above and compare.
- **Nothing starts**: your PC may block PowerShell scripts by policy. Check with
  `Get-ExecutionPolicy -List`.
- **`claude` not recognized**: add `%USERPROFILE%\.local\bin` to your user PATH (setup has
  a button for this), then open a **new** terminal. Windows already open keep the old PATH.
- **Don't test `/usage` from Git Bash**: it rewrites `/usage` into a file path and the prompt
  goes to the model. Use PowerShell or CMD.

## Credits

Inspired by [Enhed/clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget)
(MIT), which showed that `claude -p /usage` returns the plan limits headlessly.

## License

MIT
