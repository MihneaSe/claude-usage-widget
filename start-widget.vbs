' Starts Claude Usage Mini (widget.ps1 in this folder) without a console window.
' -ExecutionPolicy Bypass applies to this one PowerShell process only; it does not change system settings.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\widget.ps1"""
CreateObject("WScript.Shell").Run cmd, 0, False
