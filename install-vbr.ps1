# Works with Veeam Backup & Replication v11 RTM/GA releases.
#
# This script can install prerequisites, VBR Server, VBR Console, Veeam Explorers and Public Cloud Plug-ins.
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
$iso = "VeeamBackup&Replication_11.0.1.1261_20210930_11a.ISO" # Change to your ISO and copy into $media_path e.g. C:\install\

# Log
$install_log = "install-vbr.log"

# VBR Server
$license = "vbr-license.lic" # Change to your VBR/VCC license file and copy into $media_path e.g. C:\install\

$vbr_sqlserver = ""
$vbr_sqldb = ""
$vbr_sqluser = ""
$vbr_sqlpwd = ""
$vbr_nfsdatastore = "C:\vPowerNFS"

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
# Microsoft System CLR Types for SQL Server 2012
$app = "Microsoft System CLR Types for SQL Server 2012"
$log = "prereq-sqlclr.log"

$MSIArguments = @(
    "/i"
    "$source\Redistr\x64\SQLSysClrTypes.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
)
Install-MSI $MSIArguments

# Microsoft Shared management objects 2012
$app = "Microsoft Shared management objects 2012"
$log = "prereq-smo.log"

$MSIArguments = @(
    "/i"
    "$source\Redistr\x64\SharedManagementObjects.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
)
Install-MSI $MSIArguments

# Microsoft Report Viewer Redistributable 2015
$app = "Microsoft Report Viewer Redistributable 2015"
$log = "prereq-reportviewer.log"

$MSIArguments = @(
    "/i"
    "$source\Redistr\ReportViewer.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
)
Install-MSI $MSIArguments

# Microsoft .NET Core Runtime 3.1.16
$app = "Microsoft .NET Core Runtime 3.1.16"
$log = "prereq-dotnet-runtime.log"

$command = "F:\Redistr\x64\dotnet-runtime-3.1.16-win-x64.exe"
$Arguments = "/install /quiet /norestart /log $media_path$log"

My-Logger "Installing $app"
Start-Process -NoNewWindow -FilePath $command -ArgumentList $Arguments -Wait

# Microsoft ASP.NET Core Shared Framework 3.1.16
$app = "Microsoft ASP.NET Core Shared Framework 3.1.16"
$log = "prereq-aspnetcore-runtime.log"

$command = "F:\Redistr\x64\aspnetcore-runtime-3.1.16-win-x64.exe"
$Arguments = "/install /quiet /norestart /log $media_path$log"

My-Logger "Installing $app"
Start-Process -NoNewWindow -FilePath $command -ArgumentList $Arguments -Wait
##############################################
# Install Veeam Backup & Replication Server
##############################################
$app = "Veeam Backup & Replication Server"
$log = "vbr-server.log"

$MSIArguments = @(
    "/i"
    """$source\Backup\Server.x64.msi"""
    "/qn"
    "/L*v"
    "$media_path$log"
    "ACCEPTEULA=YES"
    "VBR_LICENSE_FILE=$media_path\$license"
    "VBR_SQLSERVER_SERVER=$vbr_sqlserver"
    "VBR_SQLSERVER_DATABASE=$vbr_sqldb"
    "VBR_SQLSERVER_AUTHENTICATION=1"
    "VBR_SQLSERVER_USERNAME=$vbr_sqluser"
    "VBR_SQLSERVER_PASSWORD=$vbr_sqlpwd"
    "VBR_NFSDATASTORE=$vbr_nfsdatastore"
    "ACCEPT_THIRDPARTY_LICENSES=1"
)
Install-MSI $MSIArguments   

##############################################
# Install Veeam Backup & Replication Console
##############################################
$app = "Veeam Backup & Replication Console"
$log = "vbr-console.log"

$MSIArguments = @(
    "/i"
    "$source\Backup\Shell.x64.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPTEULA=YES"
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments      

##############################################
# Install Veeam Explorers
##############################################
# Veeam Explorer for Microsoft Active Directory
$app = "Veeam Explorer for Microsoft Active Directory"
$log = "explorer-activedirectory.log"

$MSIArguments = @(
    "/i"
    "$source\Explorers\VeeamExplorerForActiveDirectory.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments   
  
# Veeam Explorer for Microsoft Exchange
$app = "Veeam Explorer for Microsoft Exchange"
$log = "explorer-exchange.log"

$MSIArguments = @(
    "/i"
    "$source\Explorers\VeeamExplorerForExchange.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments   

# Veeam Explorer for Microsoft SQL Server
$app = "Veeam Explorer for Microsoft SQL Server"
$log = "explorer-sql.log"

$MSIArguments = @(
    "/i"
    "$source\Explorers\VeeamExplorerForSQL.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments  

# Veeam Explorer for Oracle
$app = "Veeam Explorer for Oracle"
$log = "explorer-oracle.log"

$MSIArguments = @(
    "/i"
    "$source\Explorers\VeeamExplorerForOracle.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments  

# Veeam Explorer for Microsoft SharePoint
$app = "Veeam Explorer for Microsoft SharePoint"
$log = "explorer-sharepoint.log"

$MSIArguments = @(
    "/i"
    "$source\Explorers\VeeamExplorerForSharePoint.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments 

##############################################
# Install Plug-ins for AWS/Azure/GCP
##############################################

# Veeam Backup for AWS
$app = "Veeam Backup for AWS"
$log = "vb-aws.log"

$MSIArguments = @(
    "/i"
    "$source\Plugins\AWS\AWSPlugin.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments

$app = "Veeam Backup for AWS UI"
$MSIArguments = @(
    "/i"
    "$source\Plugins\AWS\AWSPluginUI.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments

# Veeam Backup for Microsoft Azure
$app = "Veeam Backup for Microsoft Azure"
$log = "vb-azure.log"

$MSIArguments = @(
    "/i"
    "`"$source\Plugins\Microsoft Azure\MicrosoftAzurePluginUI.msi`""
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments

$app = "Veeam Backup for Microsoft Azure UI"
$MSIArguments = @(
    "/i"
    "`"$source\Plugins\Microsoft Azure\MicrosoftAzurePluginUI.msi`""
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments

# Veeam Backup for GCP
$app = "Veeam Backup for GCP"
$log = "vb-gcp.log"

$MSIArguments = @(
    "/i"
    "$source\Plugins\GCP\GCPPlugin.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments

$app = "Veeam Backup for GCP UI"
$MSIArguments = @(
    "/i"
    "$source\Plugins\GCP\GCPPluginUI.msi"
    "/qn"
    "/norestart"
    "/L*v"
    "$media_path$log"
    "ACCEPT_EULA=`"1`""
    "ACCEPT_THIRDPARTY_LICENSES=`"1`""
)
Install-MSI $MSIArguments
##############################################
# Install updates/patches if applicable
##############################################

$app = "Veeam Updates"
$log = "vbr-updates.log"
My-Logger "Checking for $app in $source\Updates ..."
$count_updates = (Get-ChildItem ($source + "\Updates") | Measure-Object).Count
if( $count_updates -eq 0){
    My-Logger "No update(s) found ..."
} 
else{
    $count_updates_file = (Get-ChildItem ($source + "\Updates"))
    $count_update_name = $count_updates_file.Name
    My-Logger "$count_updates update(s) found: $count_update_name ..."
        
    $update = $source + "\Updates\" + $count_update_name
    Copy-Item -Path $update -Destination $media_path
    My-Logger "$count_update_name copied to $media_path"
    My-Logger "Please install update manually!"
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