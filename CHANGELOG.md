# Changelog

## v1.2.1 - 2026-10-25
- macOS setup: if Claude Code is missing, shows the install steps and offers to run
  Anthropic's official installer, then walks you through signing in.
- macOS setup: offers to add Claude Code to your Terminal PATH; signs you in if needed.
- README: step-by-step Claude Code install for Mac and Windows.

## v1.2.0 - 2026-10-25
- macOS version (`mac/`): native floating widget plus menu bar %, same cream theme,
  colour steps, countdowns and fade on mouse-over. `Install.command` runs a requirements
  checklist, builds the app on your Mac and can start it at login. Not yet tested on a Mac.

## v1.1.1 - 2026-10-24
- README: plan compatibility table (tested on Pro and Enterprise).

## v1.1.0 - 2026-10-24
- Setup window: 8-point requirements checklist (Windows, PowerShell 5.1, .NET/WPF,
  VBScript, script policy, Claude Code installed, PATH, signed in and `/usage` readable).
- Starts the widget through PowerShell when VBScript isn't available.
- Version shown in the widget's right-click menu, tray tooltip and setup window;
  setup tells you which version is installed.

## v1.0.0 - 2026-10-24
- First GitHub release.
- `Install.cmd` setup window: install, update, uninstall, Start Menu and
  start-with-Windows shortcuts, no admin rights.
- README, MIT license.

## v0.4.0 - 2026-10-19 (claude-usage-mini)
- Light cream theme, vertical layout, % colour changes every 20%.
- Reset times as countdowns ("resets in 3d 4h").
- Fades to 10% opacity on mouse-over.
