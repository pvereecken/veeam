### Description
# This script lists all VMware Cloud Director Backup jobs per VM/vApp per restore point.
# Exports the result to CSV
# Can be further enhanced to calculate total storage used per Org/VM/vApp.

$vbr_server = "FQDN or hostname"
$vbr_user   = "domain\username or host\username"
$vbr_userpwd = "password"

#Connect VBR
Disconnect-VBRServer
Connect-VBRServer -Server $vbr_server -User $vbr_user -Password $vbr_userpwd
$ErrorActionPreference = "Stop"

$AllBackupJobs = Get-VBRBackup # -Name "Jobname if a single job"

$AllVMRestorePoints = @()

$BackupCounter = 0
Foreach ($BackupJob in $AllBackupJobs) {
    if ($BackupJob.TypeToString -eq "Cloud Director Backup") {

    $BackupCounter ++
    Write-host -ForegroundColor Green " [b][$BackupCounter/$($AllBackupJobs.Count)]Working on $($BackupJob.Name)"
    $AllRestorePoints = $BackupJob.GetAllChildrenStorages()
    $AllVMs = $BackupJob.GetObjectOibsAll()
    
    $AllVMIDs = $AllRestorePoints.ObjectId | Sort-Object -Unique
    $VMCounter = 0
    Foreach ($FoundVMID in $AllVMIDs){
        $VMCounter ++
        $FoundVMName = $($AllVMs | Where-Object {$_.ObjId -eq $FoundVMID}).VMName
        
        Write-host -ForegroundColor Green "      [vm][$VMCounter/$($AllVMIDs.Count)]Working on $($FoundVMName)"
        $RestorePointObj = "" | Select-Object VMId, Obj
        $FoundRestoreJobs = $AllRestorePoints | Where-object {$_.Objectid -eq $FoundVMID}

 

        
        $AllFoundJobs = @()
        Foreach ($RestorePoint in $FoundRestoreJobs) {
            $ResultObj = "" | Select-Object VMName, BackupJob, BackupSize, FilePath ,CreationTime, BackupType, SourceType, host #, JobType

 

            $ResultObj.VMName = $FoundVMName
            $ResultObj.BackupJob = $BackupJob.Name
            $ResultObj.BackupSize = [math]::round($RestorePoint.Stats.BackupSize/1GB, 2)
            $ResultObj.FilePath = $RestorePoint.FilePath
            $ResultObj.CreationTime = $RestorePoint.CreationTime
            $ResultObj.BackupType = if ($RestorePoint.IsFull) {"Full"} Else {"Incremental"}
            $ResultObj.SourceType = $BackupJob.TypeToString
            #$ResultObj.JobType = if ($BackupJob.IsBackup) {"Primary"} ElseIf ($BackupJob.IsBackupSync) {"Copy"} Else {"Unknown"}
            $ResultObj.host = $RestorePoint.GetHost().name

             

            $AllFoundJobs += $ResultObj
        }

 

        $RestorePointObj.VMid = $FoundVMID
        $RestorePointObj.Obj = $AllFoundJobs
        $AllVMRestorePoints += $RestorePointObj
     }
}
}
 

$AllVMRestorePoints.Obj | Export-Csv -NoTypeInformation -Path c:\backup-sizes-per-restore-point.csv