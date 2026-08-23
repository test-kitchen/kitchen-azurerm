# format_data_disks initialised and NTFS-formatted the raw data disk.
$ErrorActionPreference = "Stop"

Write-Host "== format_data_disks =="
Get-Disk   | Format-Table Number, Size, PartitionStyle -AutoSize | Out-String | Write-Host
Get-Volume | Format-Table DriveLetter, FileSystem, FileSystemLabel, Size -AutoSize | Out-String | Write-Host

$volume = Get-Volume | Where-Object { $_.FileSystemLabel -eq "datadisk" }
if (-not $volume) {
  Write-Error "format_data_disks produced no volume labelled 'datadisk'"
  exit 1
}
if ($volume.FileSystem -ne "NTFS") {
  Write-Error "the datadisk volume is $($volume.FileSystem), expected NTFS"
  exit 1
}

Write-Host "OK: format_data_disks"
