# Claude Usage Widget - setup window (install / update / uninstall)
# ---------------------------------------------------------------------------
# Started by Install.cmd. No admin rights needed. What it can do, only when you click:
#   * Copy widget.ps1 + start-widget.vbs to %LOCALAPPDATA%\ClaudeUsageWidget
#   * Add Start Menu and (optional) Startup shortcuts for the current user
#   * Stop a running copy of the widget before updating or uninstalling
#   * Add %USERPROFILE%\.local\bin to your user PATH (button shown only if needed)
#   * Open a PowerShell window running Anthropic's official Claude Code installer
#     (button shown only if Claude Code is missing)
# It never runs anything in the background and makes no network calls itself.
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
# ---------------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$Src        = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target     = Join-Path $env:LOCALAPPDATA 'ClaudeUsageWidget'
$LocalBin   = Join-Path $env:USERPROFILE '.local\bin'
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Widget.lnk'
$MenuLnk    = Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude Usage Widget.lnk'
$Files      = @('widget.ps1', 'start-widget.vbs')

# ---- window ---------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Usage Widget - Setup" Width="470" SizeToContent="Height"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Background="#FAF9F5" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#D6D3C7"/>
      <Setter Property="Foreground" Value="#141413"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <StackPanel Margin="24,20,24,20">
    <TextBlock Text="Claude Usage Widget" FontSize="20" FontWeight="SemiBold" Foreground="#141413"/>
    <TextBlock Text="A small read-only widget showing your Claude Code session and weekly usage."
               Foreground="#73726C" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,16"/>

    <TextBlock Text="1. Checklist" FontWeight="SemiBold" Foreground="#141413"/>
    <TextBlock Text="No Python, Node.js, Git or admin rights needed." Foreground="#73726C" FontSize="11" Margin="0,2,0,6"/>
    <StackPanel x:Name="Checks" Margin="0,0,0,8"/>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
      <Button x:Name="FixPathBtn" Content="Add to PATH" Visibility="Collapsed" Margin="0,0,8,0"/>
      <Button x:Name="InstallClaudeBtn" Content="Install Claude Code" Visibility="Collapsed" Margin="0,0,8,0"/>
      <Button x:Name="RecheckBtn" Content="Check again"/>
    </StackPanel>

    <TextBlock Text="2. Install" FontWeight="SemiBold" Foreground="#141413"/>
    <TextBlock x:Name="InstallStatus" Foreground="#5E5D59" TextWrapping="Wrap" Margin="0,4,0,6"/>
    <CheckBox x:Name="StartupChk" Content="Start with Windows" IsChecked="True" Foreground="#141413" Margin="0,2,0,2"/>
    <CheckBox x:Name="LaunchChk" Content="Open the widget when done" IsChecked="True" Foreground="#141413" Margin="0,2,0,14"/>

    <DockPanel LastChildFill="False">
      <Button x:Name="UninstallBtn" Content="Uninstall" DockPanel.Dock="Left" Visibility="Collapsed"/>
      <Button x:Name="CloseBtn" Content="Close" DockPanel.Dock="Right" Margin="8,0,0,0"/>
      <Button x:Name="InstallBtn" Content="Install" DockPanel.Dock="Right" IsEnabled="False"
              Background="#C96442" Foreground="White" BorderBrush="#C96442" FontWeight="SemiBold"/>
    </DockPanel>
    <TextBlock x:Name="Result" Foreground="#5E8C4E" TextWrapping="Wrap" Margin="0,12,0,0" Visibility="Collapsed"/>
  </StackPanel>
</Window>
'@
$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($n in 'Checks','FixPathBtn','InstallClaudeBtn','RecheckBtn','InstallStatus',
               'StartupChk','LaunchChk','UninstallBtn','CloseBtn','InstallBtn','Result') { $ui[$n] = $win.FindName($n) }

$BrushConv = New-Object System.Windows.Media.BrushConverter
function Set-Text($box, [string]$text, [string]$color = '#5E5D59') {
    $box.Text = $text; $box.Foreground = $BrushConv.ConvertFromString($color)
}
function Show-Result([string]$text, [string]$color = '#5E8C4E') {
    Set-Text $ui.Result $text $color; $ui.Result.Visibility = 'Visible'
}

# ---- checklist rows -----------------------------------------------------------
$Rows = [ordered]@{}
$RowDefs = [ordered]@{
    os     = 'Windows 10 or 11'
    ps     = 'Windows PowerShell 5.1'
    wpf    = '.NET Framework / WPF (draws the window)'
    vbs    = 'VBScript (starts the widget without a console window)'
    policy = 'PowerShell scripts allowed'
    claude = 'Claude Code installed'
    path   = 'Claude Code on your PATH'
    usage  = 'Signed in and /usage readable'
}
$StateLook = @{
    ok      = @{ icon = [string][char]0x2713; color = '#5E8C4E' }
    warn    = @{ icon = '!';                  color = '#B8862B' }
    fail    = @{ icon = [string][char]0x2717; color = '#B53A31' }
    pending = @{ icon = [string][char]0x2026; color = '#B0AEA5' }
}
foreach ($k in $RowDefs.Keys) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = '0,2,0,2'
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = '20'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1)
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.FontWeight = 'Bold'; $icon.FontSize = 13
    $sp = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $name = New-Object System.Windows.Controls.TextBlock
    $name.Text = $RowDefs[$k]; $name.Foreground = $BrushConv.ConvertFromString('#141413'); $name.FontSize = 12.5
    $det = New-Object System.Windows.Controls.TextBlock
    $det.FontSize = 11; $det.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($name); [void]$sp.Children.Add($det)
    [void]$g.Children.Add($icon); [void]$g.Children.Add($sp)
    [void]$ui.Checks.Children.Add($g)
    $Rows[$k] = @{ icon = $icon; detail = $det; state = 'pending' }
}
function Set-Row([string]$key, [string]$state, [string]$detail) {
    $r = $Rows[$key]; $look = $StateLook[$state]
    $r.state = $state
    $r.icon.Text = $look.icon
    $r.icon.Foreground = $BrushConv.ConvertFromString($look.color)
    $r.detail.Text = $detail
    $r.detail.Foreground = $BrushConv.ConvertFromString($(if ($state -eq 'ok' -or $state -eq 'pending') { '#73726C' } else { $look.color }))
}
foreach ($k in $Rows.Keys) { Set-Row $k 'pending' 'Checking...' }

$script:HasVbs = $true

function Check-System {
    # Windows version
    $v = [Environment]::OSVersion.Version
    if ($v.Major -ge 10) {
        $name = $(if ($v.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' })
        Set-Row os 'ok' "$name (build $($v.Build))"
    } else { Set-Row os 'fail' "Windows $($v.Major).$($v.Minor) is too old. Windows 10 or 11 is needed." }

    # PowerShell
    $pv = $PSVersionTable.PSVersion
    if ($pv.Major -gt 5 -or ($pv.Major -eq 5 -and $pv.Minor -ge 1)) { Set-Row ps 'ok' "Version $pv (built into Windows)" }
    else { Set-Row ps 'fail' "Version $pv. Install Windows Management Framework 5.1." }

    # .NET / WPF - if this window is showing, WPF works
    $rel = $null
    try { $rel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop).Release } catch {}
    $net = $(if ($rel -ge 528040) { '4.8' } elseif ($rel -ge 461808) { '4.7.2' } elseif ($rel) { '4.x' } else { '' })
    Set-Row wpf 'ok' ($(if ($net) { ".NET Framework $net, built into Windows" } else { 'Working (this window uses it)' }))

    # VBScript (Microsoft is phasing it out; optional feature on recent Windows 11)
    $script:HasVbs = (Test-Path (Join-Path $env:WINDIR 'System32\vbscript.dll')) -and (Test-Path (Join-Path $env:WINDIR 'System32\wscript.exe'))
    if ($script:HasVbs) { Set-Row vbs 'ok' 'Available' }
    else { Set-Row vbs 'warn' 'Not available. The widget will start through PowerShell instead (a console window may flash briefly).' }

    # Execution policy set by group policy overrides -ExecutionPolicy Bypass
    $blocked = @()
    foreach ($scope in 'MachinePolicy', 'UserPolicy') {
        $pol = [string](Get-ExecutionPolicy -Scope $scope)
        if ($pol -eq 'Restricted' -or $pol -eq 'AllSigned') { $blocked += "$scope = $pol" }
    }
    if ($blocked.Count -gt 0) { Set-Row policy 'fail' ("Blocked by your organisation's policy (" + ($blocked -join ', ') + '). Ask your IT team.') }
    else { Set-Row policy 'ok' 'Allowed for this widget' }
}

# ---- helpers --------------------------------------------------------------
function Refresh-EnvPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Find-Claude {
    Refresh-EnvPath
    $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

# stop any running copy of this widget (it allows only one instance)
function Stop-Widget {
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop
    } catch { return 0 }
    $n = 0
    foreach ($p in $procs) {
        $m = [regex]::Match([string]$p.CommandLine, '-File\s+"([^"]*widget\.ps1)"')
        if (-not $m.Success) { continue }
        $path = $m.Groups[1].Value
        $isOurs = $false
        try { $isOurs = (Get-Content -Path $path -TotalCount 1 -ErrorAction Stop) -match 'Claude Usage Mini' } catch {}
        if ($isOurs) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $n++ } catch {} }
    }
    if ($n -gt 0) { Start-Sleep -Milliseconds 600 }
    return $n
}

function Get-Launch([string]$vbs) {
    if ($script:HasVbs) {
        return @{ exe = (Join-Path $env:WINDIR 'System32\wscript.exe'); args = ('"' + $vbs + '"') }
    }
    $ps1 = Join-Path (Split-Path $vbs) 'widget.ps1'
    return @{ exe = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe');
              args = ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ps1 + '"') }
}

function New-Shortcut([string]$lnk, [string]$vbs) {
    $l = Get-Launch $vbs
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath       = $l.exe
    $s.Arguments        = $l.args
    $s.WorkingDirectory = Split-Path $vbs
    if (-not $script:HasVbs) { $s.WindowStyle = 7 }   # minimized
    $s.IconLocation     = (Join-Path $env:WINDIR 'System32\shell32.dll') + ',43'
    $s.Description      = 'Claude Usage Widget'
    $s.Save()
}

function Update-InstallState {
    $installed = Test-Path (Join-Path $Target 'widget.ps1')
    if ($installed) {
        Set-Text $ui.InstallStatus "Installed in $Target. Install again to update."
        $ui.InstallBtn.Content = 'Update'
        $ui.UninstallBtn.Visibility = 'Visible'
        $ui.StartupChk.IsChecked = (Test-Path $StartupLnk)
    } else {
        Set-Text $ui.InstallStatus "Will be installed in $Target (no admin rights needed)."
        $ui.InstallBtn.Content = 'Install'
        $ui.UninstallBtn.Visibility = 'Collapsed'
    }
}

# ---- usage check (runs in the background, UI stays responsive) ------------
$Probe = @{ proc = $null; task = $null; started = [datetime]::MinValue }
$probeTimer = New-Object System.Windows.Threading.DispatcherTimer
$probeTimer.Interval = [TimeSpan]::FromMilliseconds(300)

function Start-UsageCheck([string]$claudePath) {
    if ($Probe.proc) { return }
    Set-Row usage 'pending' 'Asking Claude Code for your usage (a few seconds)...'
    try {
        $argLine = '-p /usage --output-format text --no-session-persistence'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $ext = [System.IO.Path]::GetExtension($claudePath).ToLower()
        if ($ext -eq '.cmd' -or $ext -eq '.bat') {
            $psi.FileName = $env:ComSpec; $psi.Arguments = '/d /c ""' + $claudePath + '" ' + $argLine + '"'
        } else {
            $psi.FileName = $claudePath; $psi.Arguments = $argLine
        }
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $p = [System.Diagnostics.Process]::Start($psi)
        $Probe.proc = $p; $Probe.task = $p.StandardOutput.ReadToEndAsync()
        [void]$p.StandardError.ReadToEndAsync()
        $Probe.started = Get-Date
        $probeTimer.Start()
    } catch {
        Set-Row usage 'fail' 'Could not run Claude Code.'
    }
}

$probeTimer.add_Tick({
    $p = $Probe.proc
    if (-not $p) { $probeTimer.Stop(); return }
    if (-not $p.HasExited) {
        if (((Get-Date) - $Probe.started).TotalSeconds -gt 45) {
            try { & taskkill.exe /T /F /PID $p.Id 2>$null | Out-Null } catch {}
            $Probe.proc = $null; $probeTimer.Stop()
            Set-Row usage 'warn' 'Claude Code did not answer in time. You can still install and check later.'
        }
        return
    }
    if (-not $Probe.task.IsCompleted) { return }
    $text = ''; try { $text = [string]$Probe.task.Result } catch {}
    $Probe.proc = $null; $probeTimer.Stop()
    $text = $text -replace '\x1b\[[0-9;?]*[A-Za-z]', ''
    $s = [regex]::Match($text, 'Current session:\s*(\d{1,3})%')
    $w = [regex]::Match($text, 'Current week \(all models\):\s*(\d{1,3})%')
    if ($s.Success -or $w.Success) {
        $parts = @()
        if ($s.Success) { $parts += "session $($s.Groups[1].Value)%" }
        if ($w.Success) { $parts += "week $($w.Groups[1].Value)%" }
        Set-Row usage 'ok' ("Works: " + ($parts -join ', ') + '.')
    } elseif ($text -match '(?i)log ?in|not authenticated|auth') {
        Set-Row usage 'fail' 'Not signed in. Open PowerShell, run "claude", sign in, type /exit, then click Check again.'
    } else {
        Set-Row usage 'warn' 'Unexpected answer from /usage (plan without limits, or a new format). The widget may show "unexpected output".'
    }
})

# ---- Claude Code check ------------------------------------------------------
function Check-Claude {
    $ui.FixPathBtn.Visibility = 'Collapsed'; $ui.InstallClaudeBtn.Visibility = 'Collapsed'
    $policyOk = $Rows['policy'].state -ne 'fail'
    $path = Find-Claude
    if ($path) {
        $ver = ''
        try { $ver = (& $path --version 2>$null | Select-Object -First 1) } catch {}
        Set-Row claude 'ok' $(if ($ver) { [string]$ver } else { $path })
        Set-Row path 'ok' $path
        $ui.InstallBtn.IsEnabled = $policyOk
        Start-UsageCheck $path
        return
    }
    $ui.InstallBtn.IsEnabled = $false
    if (Test-Path (Join-Path $LocalBin 'claude.exe')) {
        Set-Row claude 'ok' (Join-Path $LocalBin 'claude.exe')
        Set-Row path 'fail' "Its folder isn't on your PATH. Click 'Add to PATH'."
        $ui.FixPathBtn.Visibility = 'Visible'
    } else {
        Set-Row claude 'fail' "Not installed. The Claude desktop app doesn't include it. Click 'Install Claude Code'."
        Set-Row path 'pending' 'Checked after install.'
        $ui.InstallClaudeBtn.Visibility = 'Visible'
    }
    Set-Row usage 'pending' 'Checked once Claude Code is found.'
}

function Check-All { Check-System; Check-Claude }

# ---- buttons --------------------------------------------------------------
$ui.RecheckBtn.add_Click({ Check-All })

$ui.FixPathBtn.add_Click({
    $p = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $p) { $p = '' }
    if ($p -notlike "*$LocalBin*") {
        [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ";$LocalBin").TrimStart(';'), 'User')
    }
    Check-Claude
})

$ui.InstallClaudeBtn.add_Click({
    # Opens a visible PowerShell window running Anthropic's official installer (see code.claude.com/docs/en/setup)
    $cmd = "Write-Host 'Installing Claude Code (official installer)...'; irm https://claude.ai/install.ps1 | iex; " +
           "Write-Host ''; Write-Host 'Next: close this window, open a NEW PowerShell, run: claude  (sign in, then /exit), then click Check again in setup.'"
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-NoExit', '-Command', $cmd)
})

$ui.InstallBtn.add_Click({
    try {
        foreach ($f in $Files) {
            if (-not (Test-Path (Join-Path $Src $f))) { throw "Missing $f next to setup. Unzip the whole folder first." }
        }
        [void](Stop-Widget)
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        foreach ($f in $Files) {
            $dst = Join-Path $Target $f
            Copy-Item -Path (Join-Path $Src $f) -Destination $dst -Force
            try { Unblock-File -Path $dst } catch {}
        }
        $vbs = Join-Path $Target 'start-widget.vbs'
        New-Shortcut $MenuLnk $vbs
        if ($ui.StartupChk.IsChecked) { New-Shortcut $StartupLnk $vbs }
        elseif (Test-Path $StartupLnk) { Remove-Item $StartupLnk -Force }
        if ($ui.LaunchChk.IsChecked) { $l = Get-Launch $vbs; Start-Process $l.exe -ArgumentList $l.args -WindowStyle Hidden }
        Show-Result 'Done. Find it later in the Start menu as "Claude Usage Widget".'
        Update-InstallState
    } catch {
        Show-Result ("Install failed: " + $_.Exception.Message) '#B53A31'
    }
})

$ui.UninstallBtn.add_Click({
    $ok = [System.Windows.MessageBox]::Show('Remove Claude Usage Widget from this computer?',
            'Uninstall', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { return }
    try {
        [void](Stop-Widget)
        foreach ($l in $StartupLnk, $MenuLnk) { if (Test-Path $l) { Remove-Item $l -Force } }
        if (Test-Path $Target) { Remove-Item $Target -Recurse -Force }
        Show-Result 'Uninstalled. Claude Code itself was left untouched.'
        Update-InstallState
    } catch {
        Show-Result ("Uninstall failed: " + $_.Exception.Message) '#B53A31'
    }
})

$ui.CloseBtn.add_Click({ $win.Close() })

# ---- go -------------------------------------------------------------------
Update-InstallState
$win.add_ContentRendered({ Check-All })
[void]$win.ShowDialog()
