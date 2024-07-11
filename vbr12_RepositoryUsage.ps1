### Description
# This script lists all Backup Repositories with their Total and Free Space.

$vbr_server = "FQDN or hostname"
$vbr_user   = "domain\username or host\username"
$vbr_userpwd = "password"

#Connect VBR
Disconnect-VBRServer
Connect-VBRServer -Server $vbr_server -User $vbr_user -Password $vbr_userpwd
$ErrorActionPreference = "Stop"

# Standalone repositories TotalSpace + FreeSpace

$repos = Get-VBRBackupRepository 
$repoReport = @()
foreach ($repo in $repos) {
  $container = $repo.GetContainer()
  $totalSpace += [Math]::Round($container.CachedTotalSpace.InMegabytes / 1024, 1)
  $totalFreeSpace += [Math]::Round($container.CachedFreeSpace.InMegabytes / 1024, 1)
  $repoReport += $repo | select Name, @{n='TotalSpace';e={$totalSpace}}, `
  @{n='FreeSpace';e={$totalFreeSpace}}
}
$repoReport


# SOBR TotalSpace + FreeSpace

$sobrs = Get-VBRBackupRepository -Scaleout
$sobrReport = @()
foreach ($sobr in $sobrs) {
$extents = $sobr.Extent
$totalSpace = $null
$totalFreeSpace = $null
foreach ($extent in $extents) {
$repo = $extent.Repository
$container = $repo.GetContainer()
$totalSpace += [Math]::Round($container.CachedTotalSpace.InMegabytes / 1024, 1)
$totalFreeSpace += [Math]::Round($container.CachedFreeSpace.InMegabytes / 1024, 1)
}
$sobrReport += $sobr | select Name, @{n='TotalSpace';e={$totalSpace}}, `
@{n='FreeSpace';e={$totalFreeSpace}}
}
$sobrReport


