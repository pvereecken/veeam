### Description
# This script lists all VMware Cloud Director organizations and the total space used.

$vbr_server = "FQDN or hostname"
$vbr_user   = "domain\username or host\username"
$vbr_userpwd = "password"

#Connect VBR
Disconnect-VBRServer
Connect-VBRServer -Server $vbr_server -User $vbr_user -Password $vbr_userpwd
$ErrorActionPreference = "Stop"

try {
    $vcdOrgItems = Find-VBRvCloudEntity -Organization

    $now = Get-Date
    $report = New-Object -TypeName System.Collections.Generic.List[PSCustomObject]​
    # Write-LogOutput $logFile "`n$($vcdOrg.OrgName)`tbackupId`tbackup.JobId`tbackup.JobName"
    foreach ($item in $vcdOrgItems) {
        $vcdHost = $item.Path.Split("\")[0]
        $vcd = Get-VBRServer -Name $vcdHost
        $siteRef = ($vcd.Info.Options | select-xml -XPath '/root/VcdConnectionOptions/LocalSiteUid').Node.InnerXml
        $hostSiteUid = $item.VcdRef.GetType()::Make($siteRef)
        $vcdOrg = New-Object -TypeName Veeam.Backup.Model.CVcdOrganization `
            -ArgumentList $item.VcdId, $hostSiteUid, $item.VcdRef, $item.Name

        $unique_vms = @()
        $usedSpace = 0
        $usedSpaceCS = 0
        $totalObjects = 0
        $orgBackupIds = [Veeam.Backup.DBManager.CDBManager]::Instance.VcdMultiTenancy.FindOrganizationBackups($vcdOrg)
        $backupseq = 0
        #Write-LogOutput $logFile "`n$($vcdOrg.OrgName)`tbackupId`tbackup.JobId`tbackup.JobName`tbackup.CreationTime`tbackup.VmCount`tbackup.LastPointCreationTime`t`tinternalstorageseq`tstorage.Stats.BackupSize`tstorage.CreationTime`tstorage.PartialPath"

        #Write-LogOutput $logFileCS "`n$($vcdOrg.OrgName)`tbackupId`tbackup.JobId`tbackup.JobName`tbackup.CreationTime`tbackup.VmCount`tbackup.LastPointCreationTime`t`tinternalstorageseq`tstorage.Stats.BackupSize`tstorage.CreationTime`tstorage.PartialPath"
        foreach ($backupId in $orgBackupIds) {
            $backupseq += 1
            $backup = [Veeam.Backup.Core.CBackup]::Get($backupId)
            $backup_prefix = "$backupseq`t$backupId`t$($backup.JobId)`t$($backup.JobName)`t$($backup.CreationTime)`t$($backup.VmCount)`t$($backup.LastPointCreationTime)`t"

            # Loop through the storage usage and only report the "internal" storage
            # We query COS directly to obtain the "external" storage separately
            $internalstorageseq = 0
            $backupstoragesizetotal = 0
            foreach ($storage in $backup.GetAllStorages()) {
                if (-Not $storage.IsContentExternal) {
                    $internalstorageseq += 1
                    #Write-LogOutput $logFile "$backup_prefix`t$internalstorageseq`t$($storage.Stats.BackupSize)`t$($storage.CreationTime)`t$($storage.PartialPath)"
                    $backupstoragesizetotal += $storage.Stats.BackupSize
                }
            }
            # Write-LogOutput $logFile "$backupseq`tBackup All Storage size:`t$backupstoragesizetotal"
            $usedSpace += $backupstoragesizetotal

            $internalstorageseq = 0
            $backupchildrenstoragesizetotal = 0
            foreach ($storage in $backup.GetAllChildrenStorages()) {
                if (-Not $storage.IsContentExternal) {
                    $internalstorageseq += 1
                    #Write-LogOutput $logFileCS "$backup_prefix`t$internalstorageseq`t$($storage.Stats.BackupSize)`t$($storage.CreationTime)`t$($storage.PartialPath)"
                    $backupchildrenstoragesizetotal += $storage.Stats.BackupSize
                }
            }
            $usedSpaceCS += $backupchildrenstoragesizetotal
        }

        $orgReport = @{
            orgName      = $vcdOrg.OrgName;
            protectedVms = $unique_vms.Length;
            totalObjects = $totalObjects;
            usedSpace    = $usedSpace;
            usedSpaceCS  = $usedSpaceCS;
            # URL = $item.Path
        }
        $report.Add($orgReport)
    }

    $result = ConvertTo-Json -Compress $report
    $result

    #New-Item $lockfile -Type File -Force -Value "$(Get-TimeStamp) lock" | Out-Null
    #Start-Sleep -s 1
    #New-Item $reportfile -Type File -Force -Value $result | Out-Null
    #Remove-Item $lockfile

}
catch {
    $Msg = $_.Exception.Message
    $Item = $_.Exception.ItemName
    Write-Host "Info: [Generate-OrganizationReport] $Msg"
    Exit 1
}
finally {
    if ($disconnect_session) { Disconnect-VBRServer }
}