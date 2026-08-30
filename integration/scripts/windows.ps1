# The driver's custom-data bootstrap opened the WinRM listeners, and the
# generated computer name is one Azure accepted.
$ErrorActionPreference = "Stop"

Write-Host "== winrm =="
Write-Host ([System.Environment]::OSVersion.VersionString)

$name = (Get-CimInstance Win32_ComputerSystem).Name
Write-Host "computer name: $name"
if ($name.Length -gt 15) {
  Write-Error "computer name '$name' is longer than the 15 characters Windows allows"
  exit 1
}

# Join to a single string: -match against an array filters it rather than
# returning a boolean.
$listeners = (& winrm enumerate winrm/config/listener) -join "`n"
Write-Host $listeners

if ($listeners -notmatch "Transport = HTTP\b")  { Write-Error "no HTTP WinRM listener was created";  exit 1 }
if ($listeners -notmatch "Transport = HTTPS\b") { Write-Error "no HTTPS WinRM listener was created"; exit 1 }

Write-Host "OK: winrm"
