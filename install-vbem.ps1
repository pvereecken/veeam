# Works with Veeam Backup Enterprise Manager v11 RTM/GA releases.
#
# This script can install prerequisites, Enterprise Manager Server and Cloud Portal
# At the end updates are copied to the media path, but need to be manually installed!
# This script does not install MSSQL so make sure a MSSQL Server is already available on on the same or a remote server.
#
#######################################################################
# LOGGING
#######################################################################
Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "yyyy-MM-dd_hh:mm:ss"
    $InstallationLogFile = $media_path + $install_log

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $InstallationLogFile
}
$StartTime = (Get-Date -Format yyyy-MM-dd) + " " + (Get-Date -Format hh:mm:ss)
$install_date = (Get-Date -Format yyyy-MM-dd) + "_" + (Get-Date -Format hh:mm:ss) | ForEach-Object { $_ -replace ":", "" }
##############################################
# Variables
##############################################
# General
## Location of installation media including storing log files
$media_path = "C:\install\" # Change if desired, create and copy ISO and license files to it before you run the script.
$iso = "VeeamBackup&Replication_11.0.0.837_20210525.ISO" # Change to your ISO and copy into $media_path e.g. C:\install\

# Log
$install_log = "install-vbem.log"

# VBEM Server
$license = "vbr-license.lic" # Change to your VBR/VCC license file and copy into $media_path e.g. C:\install\

$vbem_catalog = "C:\VBRCatalog"

$vbem_sqlserver = ""
$vbem_sqldb = "vbem-$install_date"
$vbem_sqluser = ""
$vbem_sqlpwd = ""

# (Cloud connect only)
$cloudportal = $false # Install the Cloud Portal for failover plan self-service

# (optional) Remove license and iso file
$cleanup = $false
#######################################################################
# MSI installation
#######################################################################
Function Install-MSI{
     param(
    [Parameter(Mandatory=$true)] $msi_arguments
    )
    My-Logger "Installing $app ..."
    Start-Process "msiexec.exe" -ArgumentList $msi_arguments -Wait -NoNewWindow
    if (Select-String -path "$media_path$log" -pattern "Installation success or error status: 0.") {
        My-Logger "Installing $app SUCCESS" 
    }
    else {
        if (Select-String -Path "$media_path$log" -Pattern "Reconfiguration success or error status:") {
        My-Logger "Installing $app SUCCESS (already installed)"
        }
        else{
            Write-Host -ForegroundColor Red "Installing $app FAILED"
            break
        }
    }
}
##############################################
# MOUNT ISO
##############################################
My-Logger "Mounting $iso ..."
$mount_iso = $media_path + $iso
Mount-DiskImage -ImagePath $mount_iso -PassThru -Access ReadOnly -StorageType ISO
$iso_driveletter = (Get-DiskImage -ImagePath $mount_iso | Get-Volume).DriveLetter
$source = $iso_driveletter + ":"
My-Logger "Mounted $source\$iso ..."

##############################################
# Install PREREQUISITES
##############################################
My-Logger "Installing prerequisites ..."

# WindowsFeatures
$app = "Windows Features - Part 1"
$log = "prereq-windowsfeatures.log"

My-Logger "Installing $app ..."
Install-WindowsFeature Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, Web-Windows-Auth -Restart:$false -ErrorVariable WindowsFeatureFailure | Out-Null
if ($WindowsFeatureFailure) {
    $WindowsFeatureFailure | Out-File "$media_path$log" -Append
    Remove-Variable WindowsFeatureFailure
    $EntMgr_Prereq_Failures += 1
    Write-Host -ForegroundColor Red "Install $app FAILED" 
}
else {
    My-Logger "Install $app SUCCESS" 
}

$app = "Windows Features - Part 2"
My-Logger "Installing $app ..."
Install-WindowsFeature Web-Http-Logging, Web-Stat-Compression, Web-Filtering, Web-Net-Ext45, Web-Asp-Net45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Console -Restart:$false -ErrorVariable WindowsFeatureFailure | Out-Null
if ($WindowsFeatureFailure) {
  $WindowsFeatureFailure | Out-File "$media_path$log" -Append
  Remove-Variable WindowsFeatureFailure
  $EntMgr_Prereq_Failures += 1
  Write-Host -ForegroundColor Red "Install $app FAILED" 
}
else {
    My-Logger "Install $app SUCCESS" 
}

$WindowsFeatureResults = Get-WindowsFeature -Name Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, Web-Windows-Auth, Web-Http-Logging, Web-Stat-Compression, Web-Filtering, Web-Net-Ext45, Web-Asp-Net45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Console
$WindowsFeatureResults | Out-File "$media_path$log" -Append

if (($WindowsFeatureResults | Select-Object -ExpandProperty InstallState -Unique) -eq 'Installed') {
    My-Logger "Install $app SUCCESS" 
}
else {
    My-Logger "Not all Windows Features installed properly" | Out-File "$media_path$log" -Append
    Write-Host -ForegroundColor Red "$msg Install $app FAILED" 
}

# URLRewrite_IIS
$app = "URLRewrite_IIS"
$log = "prereq-URLRewrite_IIS.txt"

$MSIArguments = @(
  "/i"
  "$source\Redistr\x64\rewrite_amd64.msi"
  "/qn"
  "/norestart"
  "/L*v"
  "$media_path$log"
  "ACCEPTEULA=YES"
  "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments
##############################################
# Install Veeam Backup Catalog
##############################################
$app = "Veeam Backup Catalog"
$log = "vbem-catalog.txt"

New-Item -ItemType Directory -path $vbem_catalog | Out-Null

$MSIArguments = @(
  "/i"
  "$source\Catalog\VeeamBackupCatalog64.msi"
  "/qn"
  "/norestart"
  "/L*v"
  "$media_path$log"
  "ACCEPT_THIRDPARTY_LICENSES=`"1`""
  "VM_CATALOGPATH=$vbem_catalog"
)
Install-MSI $MSIArguments

##############################################
# Stop Veeam Services and processes if installed on existing VBR Server
##############################################
# Stop existing VBR Console processes if exist
if((Get-Process -Name veeam.backup.shell) -ne $null){
    Get-Process -Name veeam.backup.shell | Stop-Process
}

# Stop Veeam Services if running
if((Get-Service | Where-Object {$_.DisplayName.StartsWith("Veeam")}) -ne $null){
    My-Logger "Stopping all existing Veeam Services before installing ..."
    Get-Service | Where-Object {$_.DisplayName.StartsWith("Veeam")} | Stop-Service
}
##############################################
# Install Veeam Backup Enterprise Manager
##############################################
$app = "Veeam Backup Enterprise Manager"
$log = "vbem-server.txt"

$MSIArguments = @(
  "/i"
  "$source\EnterpriseManager\BackupWeb_x64.msi"
  "/qn"
  "/norestart"
  "/L*v"
  "$media_path$log"
  "ACCEPTEULA=YES"
  "ACCEPT_THIRDPARTY_LICENSES=`"1`""
  "VBREM_LICENSE_FILE=$media_path$license"
  "VBREM_SQLSERVER_SERVER=$vbem_sqlserver"
  "VBREM_SQLSERVER_DATABASE=$vbem_sqldb"
  "VBREM_SQLSERVER_AUTHENTICATION=1"
  "VBREM_SQLSERVER_USERNAME=$vbem_sqluser"
  "VBREM_SQLSERVER_PASSWORD=$vbem_sqlpwd"
)
Install-MSI $MSIArguments

##############################################
# Install Veeam Backup Enterprise Manager Cloud Portal // VCC-only
##############################################
if($cloudportal -eq $true){
    $app = "Veeam Backup Enterprise Manager Cloud Portal"
    $log = "vbem-cloudportal.txt"

    $MSIArguments = @(
        "/qn"
        "/L*v"
        "$media_path$log"
        "/qn"
        "/i"
        "$source\Cloud Portal\BackupCloudPortal_x64.msi"
        "ACCEPTEULA=YES"
        "ACCEPT_THIRDPARTY_LICENSES=1"
    )
    Install-MSI $MSIArguments
}

##############################################
# Start all services
##############################################
My-Logger "Starting all Veeam Services ..."
Get-Service | Where-Object {$_.DisplayName.StartsWith("Veeam")} | Start-Service

#######################################################################
# END
#######################################################################
# UnMount ISO
Dismount-DiskImage -ImagePath $mount_iso
My-Logger "ISO dismounted."

if($cleanup -eq $true){
    My-Logger "Cleaning up ..."
    # Remove license file
    Remove-Item $media_path$license
    My-Logger "Removed: $license"
    # Remove ISO file
    Remove-Item $media_path$iso
    My-Logger "Removed: $iso"
}

$EndTime = (Get-Date -Format yyyy-MM-dd) + " " + (Get-Date -Format hh:mm:ss)
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "Installation COMPLETE"
My-Logger "StartTime: $StartTime"
My-Logger "EndTime: $EndTime"
My-Logger "Duration: $duration minutes"