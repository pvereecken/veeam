# Works with Veeam Service Provider Console v5.x
#
# This script can install prerequisites, VSPC Server, VSPC WebUI and ConnectWise Plugins
# This script does not install MSSQL so make sure a MSSQL Server is already available on on the same or a remote server.
#
$StartTime = (Get-Date -Format yyyy-MM-dd) + " " + (Get-Date -Format hh:mm:ss)
$install_date = (Get-Date -Format yyyy-MM-dd) + "_" + (Get-Date -Format hh:mm:ss) | ForEach-Object { $_ -replace ":", "" }
##############################################
# Components to install
##############################################

# Install on server where VSPC Server is installed
$install_server = 1
$install_connectwise_manage_server = 1

# Install on server where VSPC WebUI is Installed
$install_webui = 0
$install_connectwise_manage_webui = 0
$install_connectwise_automate = 0

##############################################
# Variables
##############################################
# General
## Location of installation media including storing log files
$media_path = "C:\install\" # Change if desired, create and copy ISO and license files to it before you run the script.
$iso = "VeeamServiceProviderConsole_5.0.0.6726_20210528.ISO" # Change to your ISO

# VSPC Server
$license = "vspc-license.lic" # Change to your VCC/VSPC license file

$VSPC_SERVER_SERVICE_ACCOUNT_USERNAME = "DOMAIN\USERNAME" # Make sure this user is added to the Local Admin group
$VSPC_SERVER_SERVICE_ACCOUNT_PASSWORD = ""

$VSPC_SERVER_INSTALLDIR = "C:\Program Files\Veeam\Availability Console" # Default
$VSPC_SERVER_MANAGEMENT_PORT = "1989" # Default=1989
$VSPC_SERVER_CONNECTION_HUB_PORT = "9999" # Default=9999

$VSPC_SQL_SERVER = "" # Change to FQDN/IP of your MSSQL Server
$VSPC_SQL_DATABASE_NAME = "VSPC-$install_date" # Change to DB name of choice if desired
$VSPC_SQL_AUTHENTICATION_MODE ="1" # 0=Windows, 1=SQL
$VSPC_SQL_USER_USERNAME = "sa" # Set when SQL authentication is used
$VSPC_SQL_USER_PASSWORD = "" # Set when SQL authentication is used

# VSPC WebUI
$VSPC_WEBUI_Installationdir = "C:\Program Files\Veeam\Availability Console" # Default
$VSPC_SERVER_NAME = "" # Change to FQDN/IP of your VSPC Server
$VSPC_SERVER_PORT = "1989" # Default=1989
$VSPC_RESTAPI_PORT = "1281" # Default=1281
$VSPC_WEBSITE_PORT = "1280" # Default=1280
$VSPC_CONFIGURE_SCHANNEL = "1" # Default=1

# ConnectWise Manage Plugin
$CW_MANAGE_Installationdir = "C:\Program Files\Veeam\Availability Console\Integrations\" # Default
$CW_MANAGE_USERNAME = "DOMAIN\USERNAME" # Account under with the plugin will run
$CW_MANAGE_PASSWORD = ""
$CW_MANAGE_COMMPORT = "9996" # Default=9996

# ConnectWise Automate Plugin
$CW_AUTOMATE_Installationdir = "C:\Program Files\Veeam\Availability Console\Integrations\ConnectWiseAutomate\" # Default

# (optional) Remove license and iso file
$cleanup = $false
#######################################################################
# LOGGING
#######################################################################
Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "yyyy-MM-dd_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $InstallationLogFile
}
$InstallationLogFile = $media_path + "install-vspc.log"
#######################################################################
# MSI installation
#######################################################################
Function Install-MSI{
     param(
    [Parameter(Mandatory=$true)] $msi_arguments
    )
    My-Logger "Installing $app ..."
    Start-Process "msiexec.exe" -ArgumentList $msi_arguments -Wait -NoNewWindow
    if (Select-String -path "$InstallationLogFile" -pattern "Installation success or error status: 0.") {
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
# PREREQUISITES
##############################################
# Mount ISO
My-Logger "Mounting $iso ..."
$mount_iso = $media_path + $iso
Mount-DiskImage -ImagePath $mount_iso -PassThru -Access ReadOnly -StorageType ISO
$iso_driveletter = (Get-DiskImage -ImagePath $mount_iso | Get-Volume).DriveLetter
$source = $iso_driveletter + ":"
My-Logger "Mounted $source\$iso ..."

if($install_server -eq 1 -or $install_webui -eq 1){
    # Microsoft IIS components
    $app = "Microsoft IIS components"
    $log = "prereq-iis.log"
    My-Logger "Installing $app ..."
    
    Install-WindowsFeature Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, Web-Asp-Net45, Web-ISAPI-Ext -Restart:$false -ErrorVariable WindowsFeatureFailure | Out-Null
    if ($WindowsFeatureFailure) {
        $WindowsFeatureFailure | Out-File $media_path$log -Append
        Remove-Variable WindowsFeatureFailure
        $EntMgr_Prereq_Failures += 1
        My-Logger "Installing $app FAILED" 
    }
    else {
        My-Logger "Installing $app SUCCESS" 
    }
}
if($install_server -eq 1){
    # Microsoft SQL Native Client 2021
    $app = "Microsoft SQL Native Client 2021"
    $log = "prereq-sqlnc.log"

    $MSIArguments = @(
        "/i"
        "$source\Redistr\x64\sqlncli.msi"
        "/qn"
        "/norestart"
        "/L*v"
        "$media_path$log"
        "IACCEPTSQLNCLILICENSETERMS=YES"
    )
    Install-MSI $MSIArguments
}
if($install_server -eq 1){
    # Microsoft System CLR Types for SQL Server 2014
    $app = "Microsoft System CLR Types for SQL Server 2014"
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
}
if($install_server -eq 1){
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
}
if($install_server -eq 1 -or $install_webui -eq 1){
    # Microsoft ASP.NET Core Module V2
    $app = "Microsoft ASP.NET Core Module V2"
    $log = "prereq-aspdotnetcore.log"
    My-Logger "Installing $app ..."

    Start-Process -NoNewWindow -FilePath "$source\Redistr\dotnet-hosting-2.2.4-win.exe" -ArgumentList "/Installation /quiet /log $media_path$log" -Wait
    if (Select-String -Path "$media_path$log" -Pattern "Apply complete, result: 0x0") {
        My-Logger "Installing $app SUCCESS"
    }
    else {
        My-Logger "Installing $app FAILED"
    }
}
##############################################
# VSPC SERVER
##############################################
if($install_server -eq 1){
    $app = "Veeam Service Provider Console Server"
    $log = "vspc-server.log"

    if($VSPC_SQL_AUTHENTICATION_MODE -eq 1){
        # Use SQL authentication mode
        $MSIArguments = @(
        "/L*v"
        """$media_path$log"""
        "/qn"
        "/i"
        """$source\ApplicationServer\VAC.ApplicationServer.x64.msi"""
        "InstallationDIR=`"$VSPC_SERVER_INSTALLDIR`""
        "VAC_LICENSE_FILE=`"$media_path$license`""
        "VAC_SERVICE_ACCOUNT_NAME=`"$VSPC_SERVER_SERVICE_ACCOUNT_USERNAME`""
        "VAC_SERVICE_ACCOUNT_PASSWORD=`"$VSPC_SERVER_SERVICE_ACCOUNT_PASSWORD`""
        "VAC_SQL_SERVER=`"$VSPC_SQL_Server`""
        "VAC_SQL_DATABASE_NAME=`"$VSPC_SQL_DATABASE_NAME`""
        "VAC_AUTHENTICATION_MODE=`"1`""
        "VAC_SQL_USER=`"$VSPC_SQL_USER_USERNAME`""
        "VAC_SQL_USER_PASSWORD=`"$VSPC_SQL_USER_PASSWORD`""
        "VAC_SERVER_MANAGEMENT_PORT=`"$VSPC_SERVER_MANAGEMENT_PORT`""
        "VAC_CONNECTION_HUB_PORT=`"$VSPC_SERVER_CONNECTION_HUB_PORT`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
        )
    }
    else{
        # Use Windows authentication mode
        $MSIArguments = @(
        "/L*v"
        """$media_path$log"""
        "/qn"
        "/i"
        """$source\ApplicationServer\VAC.ApplicationServer.x64.msi"""
        "InstallationDIR=`"$VSPC_SERVER_INSTALLDIR`""
        "VAC_LICENSE_FILE=`"$media_path$license`""
        "VAC_SERVICE_ACCOUNT_NAME=`"$VSPC_SERVER_SERVICE_ACCOUNT_USERNAME`""
        "VAC_SERVICE_ACCOUNT_PASSWORD=`"$VSPC_SERVER_SERVICE_ACCOUNT_PASSWORD`""
        "VAC_SQL_SERVER=`"$VSPC_SQL_Server`""
        "VAC_SQL_DATABASE_NAME=`"$VSPC_SQL_DATABASE_NAME`""
        "VAC_SERVER_MANAGEMENT_PORT=`"$VSPC_SERVER_MANAGEMENT_PORT`""
        "VAC_CONNECTION_HUB_PORT=`"$VSPC_SERVER_CONNECTION_HUB_PORT`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
        )
    }
    Install-MSI $MSIArguments
}
if($cleanup -eq $true){
    My-Logger "Cleaning up ..."
    # Remove license file
    Remove-Item $media_path$license
    My-Logger "Removed: $license"
    # Remove ISO file
    Remove-Item $media_path$iso
    My-Logger "Removed: $iso"
}
##############################################
# VSPC WEBUI
##############################################
if($install_webui -eq 1){
    $app = "Veeam Service Provider Console Web UI"
    $log = "vspc-webui.log"

    $MSIArguments = @(
        "/L*v"
        """$media_path$log"""
        "/qn"
        "/i"
        """$source\WebUI\VAC.WebUI.x64.msi"""
        "InstallationDIR=`"$VSPC_WEBUI_Installationdir`""
        "VAC_SERVER_NAME=$VSPC_SERVER_NAME"
        "VAC_SERVER_PORT=`"$VSPC_SERVER_PORT`""
        "VAC_RESTAPI_PORT=`"$VSPC_RESTAPI_PORT`""
        "VAC_WEBSITE_PORT=`"$VSPC_WEBSITE_PORT`""
        "VAC_CONFIGURE_SCHANNEL=`"$VSPC_CONFIGURE_SCHANNEL`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
    )
    Install-MSI $MSIArguments
}
##############################################
# ConnectWise Manage Plugin Server
##############################################
if($install_connectwise_manage_server -eq 1){
    $app = "ConnectWise Manage Plugin Server"
    $log = "connectwise-manage-server.log"

    $MSIArguments = @(
        "/L*v"
        """$media_path\$log"""
        "/qn"
        "/i"
        """$source\Plugins\ConnectWise\Manage\VAC.ConnectorService.x64.msi"""
        "InstallationDIR=`"$CW_MANAGE_Installationdir`""
        "SERVERNAME=$VSPC_SERVER_NAME"
        "VAC_CW_COMMUNICATION_PORT=`"$CW_MANAGE_COMMPORT`""
        "USERNAME=`"$CW_MANAGE_USERNAME`""
        "PASSWORD=`"$CW_MANAGE_PASSWORD`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
    )
    Install-MSI $MSIArguments
}
##############################################
# ConnectWise Manage Plugin WebUI
##############################################
if($install_connectwise_manage_webui -eq 1){
    $app = "ConnectWise Manage Plugin Web UI"
    $log = "connectwise-manage-webui.log"

    $MSIArguments = @(
        "/L*v"
        """$media_path$log"""
        "/qn"
        "/i"
        """$source\Plugins\ConnectWise\Manage\VAC.ConnectorWebUI.x64.msi"""
        #"InstallationDIR=`"$CW_MANAGE_Installationdir`""
        #"USERNAME=$CW_MANAGE_USERNAME"
        #"PASSWORD=`"$CW_MANAGE_PASSWORD`""
        #"VAC_CW_COMMUNICATION_PORT=`"$CW_MANAGE_COMMPORT`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
    )
    Install-MSI $MSIArguments
}
##############################################
# ConnectWise Automate Plugin
##############################################
if($install_connectwise_automate -eq 1){
    $app = "ConnectWise Automate Plugin"
    $log = "connectwise-automate.log"

    $MSIArguments = @(
        "/L*v"
        """$media_path$log"""
        "/qn"
        "/i"
        """$source\Plugins\ConnectWise\Automate\VAC.AutomatePlugin.x64.msi"""
        "InstallationDIR=`"$CW_AUTOMATE_Installationdir`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
    )
    Install-MSI $MSIArguments
}
#######################################################################
# END
#######################################################################
# UnMount ISO
Dismount-DiskImage -ImagePath $mount_iso
My-Logger "ISO dismounted."

$EndTime = (Get-Date -Format yyyy-MM-dd) + " " + (Get-Date -Format hh:mm:ss)
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "Installation COMPLETE"
My-Logger "StartTime: $StartTime"
My-Logger "EndTime: $EndTime"
My-Logger "Duration: $duration minutes"