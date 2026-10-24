# Claude Usage Mini - read-only Claude Code usage widget for Windows (v4)
# ---------------------------------------------------------------------------
# What it does, and nothing more:
#   * Every 2 minutes runs:  claude -p /usage --output-format text --no-session-persistence
#     (the same numbers as /usage in Claude Code; the slash command does not call the model)
#   * Shows session %, weekly % and (if reported) Fable weekly %, with time left to reset.
# What it never does:
#   * No network calls of its own, no telemetry, no location/weather lookups.
#   * No admin rights, no scheduled tasks, no registry changes, no autostart.
#   * No chat, no AI-generated scripts, no PC scanning, no running other programs.
#   * Writes only two files, both in its own folder: settings.json (window position)
#     and widget-error.log (error messages only - never the /usage output itself).
# Plain Windows PowerShell 5.1 + WPF. No dependencies. Keep this file ASCII-only.
# ---------------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ---- single instance ------------------------------------------------------
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeUsageMini', [ref]$created)
if (-not $created) { exit }

# ---- settings -------------------------------------------------------------
$Here         = Split-Path -Parent $MyInvocation.MyCommand.Path
$SettingsFile = Join-Path $Here 'settings.json'
$LogFile      = Join-Path $Here 'widget-error.log'
$IntervalSec  = 120   # how often to ask /usage
$TimeoutSec   = 45    # kill the probe if it hangs longer than this

# Colour of the % number, one step per 20% (Claude light theme)
$Bands = @(
    @{ max = 19;  color = '#3D3D3A' }   # 0-19   ink
    @{ max = 39;  color = '#5E8C4E' }   # 20-39  sage
    @{ max = 59;  color = '#B8862B' }   # 40-59  amber
    @{ max = 79;  color = '#C96442' }   # 60-79  clay
    @{ max = 100; color = '#B53A31' }   # 80-100 red
)

$S = @{ left = 100; top = 100; topmost = $true; fadeOnHover = $true }
if (Test-Path $SettingsFile) {
    try {
        $j = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        foreach ($k in 'left', 'top', 'topmost', 'fadeOnHover') {
            if ($j.PSObject.Properties[$k]) { $S[$k] = $j.$k }
        }
    } catch {}
}
function Save-Settings {
    try { ($S | ConvertTo-Json) | Set-Content -Path $SettingsFile -Encoding UTF8 } catch {}
}
function Write-Log([string]$msg) {
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) { Remove-Item $LogFile -Force }
        Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch {}
}

# ---- locate Claude Code ---------------------------------------------------
$cmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cmd) {
    [System.Windows.MessageBox]::Show(
        'Claude Code ("claude") was not found on PATH. Install it, sign in, then start the widget again.',
        'Claude Usage Mini', 'OK', 'Error') | Out-Null
    exit 1
}
$ClaudePath = $cmd.Source

# ---- probe state ----------------------------------------------------------
$State = @{
    proc = $null; outTask = $null; started = [datetime]::MinValue
    nextRun = [datetime]::Now; lastOk = [datetime]::MinValue; lastErr = ''
    s = $null; w = $null; f = $null
}

function Start-Probe {
    if ($State.proc) { return }
    try {
        $argLine = '-p /usage --output-format text --no-session-persistence'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $ext = [System.IO.Path]::GetExtension($ClaudePath).ToLower()
        if ($ext -eq '.cmd' -or $ext -eq '.bat') {
            # npm-style install: claude.cmd has to go through cmd.exe
            $psi.FileName  = $env:ComSpec
            $psi.Arguments = '/d /c ""' + $ClaudePath + '" ' + $argLine + '"'
        } else {
            $psi.FileName  = $ClaudePath
            $psi.Arguments = $argLine
        }
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $p = [System.Diagnostics.Process]::Start($psi)
        $State.proc    = $p
        $State.outTask = $p.StandardOutput.ReadToEndAsync()
        [void]$p.StandardError.ReadToEndAsync()   # drained so the process never blocks
        $State.started = Get-Date
    } catch {
        $State.lastErr = 'could not start claude'
        Write-Log "Start-Probe: $($_.Exception.Message)"
        $State.nextRun = (Get-Date).AddSeconds($IntervalSec)
    }
}

function Stop-Probe {
    $p = $State.proc
    if ($p) {
        try { if (-not $p.HasExited) { & taskkill.exe /T /F /PID $p.Id 2>$null | Out-Null } } catch {}
        try { $p.Dispose() } catch {}
    }
    $State.proc = $null; $State.outTask = $null
    $State.nextRun = (Get-Date).AddSeconds($IntervalSec)
}

function Check-Probe {
    $p = $State.proc
    if (-not $p) { return }
    if (-not $p.HasExited) {
        if (((Get-Date) - $State.started).TotalSeconds -gt $TimeoutSec) {
            Stop-Probe
            $State.lastErr = 'timed out'
            Write-Log 'Probe timed out'
        }
        return
    }
    if (-not $State.outTask.IsCompleted) { return }
    $text = ''
    try { $text = [string]$State.outTask.Result } catch {}
    Stop-Probe
    Apply-Usage $text
}

# ---- parsing --------------------------------------------------------------
function Parse-ResetTime([string]$s) {
    # "Oct 19, 9:49pm (Europe/Paris)", "Oct 19 at 9pm" or just "9:49pm" -> local DateTime
    # The time zone in brackets is assumed to be this PC's time zone.
    $now = Get-Date
    $m = [regex]::Match($s, '([A-Za-z]{3})\s+(\d{1,2}),?\s*(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)')
    if ($m.Success) {
        $min = $m.Groups[4].Value; if (-not $min) { $min = '00' }
        $stamp = '{0} {1} {2} {3}:{4} {5}' -f $m.Groups[1].Value, $m.Groups[2].Value, $now.Year,
                 $m.Groups[3].Value, $min, $m.Groups[5].Value.ToUpper()
        try {
            $dt = [datetime]::ParseExact($stamp, 'MMM d yyyy h:mm tt', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($dt -lt $now.AddDays(-30)) { $dt = $dt.AddYears(1) }   # around New Year
            return $dt
        } catch { return $null }
    }
    $m = [regex]::Match($s, '(\d{1,2})(?::(\d{2}))?\s*([ap]m)')
    if ($m.Success) {
        $min = $m.Groups[2].Value; if (-not $min) { $min = '00' }
        try {
            $t = [datetime]::ParseExact(('{0}:{1} {2}' -f $m.Groups[1].Value, $min, $m.Groups[3].Value.ToUpper()),
                 'h:mm tt', [System.Globalization.CultureInfo]::InvariantCulture)
            $dt = $now.Date.Add($t.TimeOfDay)
            if ($dt -lt $now) { $dt = $dt.AddDays(1) }
            return $dt
        } catch { return $null }
    }
    return $null
}

function Get-UsageLine([string]$text, [string]$label) {
    $m = [regex]::Match($text, [regex]::Escape($label) + '\s*(\d{1,3})%([^\r\n]*)')
    if (-not $m.Success) { return $null }
    $reset = $null
    $r = [regex]::Match($m.Groups[2].Value, 'resets\s*(.+)$')
    if ($r.Success) { $reset = Parse-ResetTime $r.Groups[1].Value }
    return @{ pct = [int]$m.Groups[1].Value; reset = $reset }
}

function Apply-Usage([string]$text) {
    $text = $text -replace '\x1b\[[0-9;?]*[A-Za-z]', ''   # strip colour codes, if any
    $s = Get-UsageLine $text 'Current session:'
    $w = Get-UsageLine $text 'Current week (all models):'
    $f = Get-UsageLine $text 'Current week (Fable):'
    if (-not $s -and -not $w) {
        if ($text -match '(?i)log ?in|not authenticated|auth') { $State.lastErr = 'not signed in' }
        else { $State.lastErr = 'unexpected output' }
        Write-Log "Unrecognised /usage output ($($text.Length) chars) - content not logged"
        return
    }
    $State.lastErr = ''; $State.lastOk = Get-Date
    $State.s = $s; $State.w = $w; $State.f = $f
    Render

    $tip = 'Claude: '
    if ($s) { $tip += "session $($s.pct)%" } else { $tip += 'session --' }
    if ($w) { $tip += ", week $($w.pct)%" }
    if ($f) { $tip += ", Fable $($f.pct)%" }
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $tray.Text = $tip
}

# ---- UI helpers -----------------------------------------------------------
$BrushConv = New-Object System.Windows.Media.BrushConverter
function Get-Brush([string]$hex) { $BrushConv.ConvertFromString($hex) }
function Get-PctColor([int]$p) {
    foreach ($b in $Bands) { if ($p -le $b.max) { return $b.color } }
    return $Bands[-1].color
}
function Format-Left($reset) {
    if (-not $reset) { return 'not started' }
    $span = $reset - (Get-Date)
    if ($span.TotalSeconds -le 0) { return 'resetting...' }
    $mins = [int][Math]::Ceiling($span.TotalMinutes)
    $d = [int][Math]::Floor($mins / 1440); $h = [int][Math]::Floor(($mins % 1440) / 60); $m = $mins % 60
    if ($d -gt 0) { return "resets in ${d}d ${h}h" }
    if ($h -gt 0) { return "resets in ${h}h {0:D2}m" -f $m }
    return "resets in ${m}m"
}
function Set-Block($pctBox, $leftBox, $data) {
    if (-not $data) { $pctBox.Text = '--%'; $pctBox.Foreground = Get-Brush '#B0AEA5'; $leftBox.Text = ''; return }
    $p = [Math]::Max(0, [Math]::Min(100, [int]$data.pct))
    $pctBox.Text = "$p%"
    $pctBox.Foreground = Get-Brush (Get-PctColor $p)
    $leftBox.Text = Format-Left $data.reset
}
function Render {
    Set-Block $ui.SessionPct $ui.SessionLeft $State.s
    Set-Block $ui.WeekPct    $ui.WeekLeft    $State.w
    if ($State.f) { $ui.FablePanel.Visibility = 'Visible'; Set-Block $ui.FablePct $ui.FableLeft $State.f }
    else          { $ui.FablePanel.Visibility = 'Collapsed' }
}
function Update-Status {
    $text = ''; $color = '#B0AEA5'
    if ($State.lastErr -and $State.lastOk -eq [datetime]::MinValue) { $text = $State.lastErr; $color = '#B53A31' }
    elseif ($State.lastOk -eq [datetime]::MinValue) { $text = 'loading...' }
    elseif (((Get-Date) - $State.lastOk).TotalSeconds -gt 3 * $IntervalSec) {
        $text = 'stale - ' + $State.lastOk.ToString('HH:mm'); $color = '#B8862B'
    }
    $ui.Status.Text = $text
    $ui.Status.Foreground = Get-Brush $color
    if ($text) { $ui.Status.Visibility = 'Visible' } else { $ui.Status.Visibility = 'Collapsed' }
}

# ---- window ---------------------------------------------------------------
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Usage Mini" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        ShowInTaskbar="False" FontFamily="Segoe UI">
  <Border CornerRadius="12" Background="#FAF9F5" BorderBrush="#E3E0D5"
          BorderThickness="1" Padding="14,9,14,10" Margin="4">
    <StackPanel MinWidth="96">
      <TextBlock Text="Session" Foreground="#73726C" FontSize="11"/>
      <TextBlock x:Name="SessionPct" Text="--%" FontSize="30" FontWeight="SemiBold" Foreground="#B0AEA5" Margin="0,-2,0,-2"/>
      <TextBlock x:Name="SessionLeft" Foreground="#5E5D59" FontSize="13" FontWeight="Medium"/>

      <Border Height="1" Background="#E3E0D5" Margin="0,7,0,7"/>

      <TextBlock Text="Week" Foreground="#73726C" FontSize="11"/>
      <TextBlock x:Name="WeekPct" Text="--%" FontSize="30" FontWeight="SemiBold" Foreground="#B0AEA5" Margin="0,-2,0,-2"/>
      <TextBlock x:Name="WeekLeft" Foreground="#5E5D59" FontSize="13" FontWeight="Medium"/>

      <StackPanel x:Name="FablePanel" Visibility="Collapsed">
        <Border Height="1" Background="#E3E0D5" Margin="0,7,0,7"/>
        <TextBlock Text="Week - Fable" Foreground="#73726C" FontSize="11"/>
        <TextBlock x:Name="FablePct" Text="--%" FontSize="30" FontWeight="SemiBold" Foreground="#B0AEA5" Margin="0,-2,0,-2"/>
        <TextBlock x:Name="FableLeft" Foreground="#5E5D59" FontSize="13" FontWeight="Medium"/>
      </StackPanel>

      <TextBlock x:Name="Status" Foreground="#B0AEA5" FontSize="11" Margin="0,8,0,0" Text="loading..."/>
    </StackPanel>
  </Border>
</Window>
'@

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($n in 'Status','SessionPct','SessionLeft','WeekPct','WeekLeft','FablePanel','FablePct','FableLeft') {
    $ui[$n] = $win.FindName($n)
}

# keep the window on screen even if monitors changed since last run
$vl = [System.Windows.SystemParameters]::VirtualScreenLeft
$vt = [System.Windows.SystemParameters]::VirtualScreenTop
$vw = [System.Windows.SystemParameters]::VirtualScreenWidth
$vh = [System.Windows.SystemParameters]::VirtualScreenHeight
if ($S.left -lt $vl -or $S.left -gt ($vl + $vw - 100) -or $S.top -lt $vt -or $S.top -gt ($vt + $vh - 100)) {
    $S.left = 100; $S.top = 100
}
$win.Left = $S.left; $win.Top = $S.top; $win.Topmost = [bool]$S.topmost

# fade almost invisible while the mouse is over it, so it never hides what's underneath
$FadeOpacity = 0.10
function Set-Fade([double]$to) {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation($to, [TimeSpan]::FromMilliseconds(150))
    $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
}
$win.add_MouseEnter({ if ($S.fadeOnHover -and -not $script:Dragging) { Set-Fade $FadeOpacity } })
$win.add_MouseLeave({ Set-Fade 1.0 })

# drag anywhere (solid while dragging); save position when released
$script:Dragging = $false
$win.add_MouseLeftButtonDown({
    $script:Dragging = $true; Set-Fade 1.0
    try { $win.DragMove() } catch {}
    $script:Dragging = $false
    $S.left = $win.Left; $S.top = $win.Top; Save-Settings
})

function Toggle-Window { if ($win.IsVisible) { $win.Hide() } else { $win.Show(); $win.Activate() | Out-Null } }
function Exit-Widget {
    $timer.Stop()
    Stop-Probe
    $tray.Visible = $false; $tray.Dispose()
    try { $mutex.ReleaseMutex() } catch {}
    $app.Shutdown()
}

# right-click menu on the widget
$menu = New-Object System.Windows.Controls.ContextMenu
function Add-MenuItem([string]$header, [scriptblock]$action) {
    $i = New-Object System.Windows.Controls.MenuItem
    $i.Header = $header; $i.add_Click($action); [void]$menu.Items.Add($i); return $i
}
[void](Add-MenuItem 'Refresh now' { $State.nextRun = Get-Date })
$topItem = Add-MenuItem 'Always on top' { $win.Topmost = -not $win.Topmost; $topItem.IsChecked = $win.Topmost; $S.topmost = $win.Topmost; Save-Settings }
$topItem.IsChecked = $win.Topmost
$fadeItem = Add-MenuItem 'Fade on mouse-over' { $S.fadeOnHover = -not $S.fadeOnHover; $fadeItem.IsChecked = [bool]$S.fadeOnHover; Save-Settings }
$fadeItem.IsChecked = [bool]$S.fadeOnHover
[void](Add-MenuItem 'Hide (click tray icon to show)' { $win.Hide() })
[void](Add-MenuItem 'Exit' { Exit-Widget })
$win.ContextMenu = $menu

# ---- tray icon ------------------------------------------------------------
$tray = New-Object System.Windows.Forms.NotifyIcon
try { $tray.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($ClaudePath) } catch { $tray.Icon = [System.Drawing.SystemIcons]::Information }
if (-not $tray.Icon) { $tray.Icon = [System.Drawing.SystemIcons]::Information }
$tray.Text = 'Claude usage: loading...'
$tray.add_MouseClick({ param($sender, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-Window } })
$cms = New-Object System.Windows.Forms.ContextMenuStrip
[void]$cms.Items.Add('Show / hide', $null, { Toggle-Window })
[void]$cms.Items.Add('Refresh now', $null, { $State.nextRun = Get-Date })
[void]$cms.Items.Add('Exit', $null, { Exit-Widget })
$tray.ContextMenuStrip = $cms
$tray.Visible = $true

# ---- main loop ------------------------------------------------------------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.add_Tick({
    try {
        Check-Probe
        if (-not $State.proc -and (Get-Date) -ge $State.nextRun) { Start-Probe }
        if ($State.lastOk -ne [datetime]::MinValue) { Render }   # keeps the countdowns live
        Update-Status
    } catch { Write-Log "Tick: $($_.Exception.Message)" }
})
$timer.Start()

$win.Show()
[void]$app.Run()
