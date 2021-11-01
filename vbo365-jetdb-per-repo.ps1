$localdrives=[System.IO.DriveInfo]::GetDrives() | where {($_.name -ne "C:\") -and ($_.DriveType -ne "CDRom")}
$totalfiles=0
foreach ($drive in $localdrives )
  {
  $FilesThisDrive=( Get-ChildItem -Path $($drive.name) -Recurse -Filter *.adb | Measure-Object ).Count
  $totalfiles+=$FilesThisDrive
  Write-Host "checked $($drive.name) files:$($FilesThisDrive)"
  }
Write-Host "Total count *.adb:$totalfiles"
