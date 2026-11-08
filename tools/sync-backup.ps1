<#
  Local backup helper - NOT part of the game runtime.

  Mirrors the working copy of FOS Sports Football to the archive drive.
  Committed history (.git) and any uncommitted work are included; the Godot
  import cache (.godot) is skipped because it is disposable and large.

  Usage:
      powershell -ExecutionPolicy Bypass -File tools\sync-backup.ps1
      powershell -ExecutionPolicy Bypass -File tools\sync-backup.ps1 -Destination "D:\backup\FOS"
#>
param(
    [string]$Source = (Split-Path $PSScriptRoot -Parent),
    [string]$Destination = "E:\Game stuff\mods\Repos\FOS-Sports-Football"
)

if (-not (Test-Path (Join-Path $Source "project.godot"))) {
    throw "Source does not look like the FOS project (no project.godot): $Source"
}

# Never run a mirror onto a bare drive root - /MIR deletes anything not in the source.
if ([string]::IsNullOrWhiteSpace($Destination) -or $Destination -match '^[A-Za-z]:\\?$') {
    throw "Refusing to mirror onto a drive root: '$Destination'"
}

Write-Host "Mirroring:"
Write-Host "  from: $Source"
Write-Host "  to:   $Destination"

robocopy $Source $Destination /MIR /XD .godot /R:2 /W:2 /NFL /NDL /NP

$code = $LASTEXITCODE
if ($code -ge 8) {
    throw "robocopy failed with exit code $code"
}

Write-Host "Backup complete (robocopy exit $code)."
