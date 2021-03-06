# Works with Veeam Service Provider Console v5.x
# Works with Veeam Service Provider Console v6.x
#
# This script can install prerequisites, VSPC Server, VSPC WebUI and ConnectWise Plugins
# This script does not install MSSQL so make sure a MSSQL Server is already available on on the same or a remote server.
#
$StartTime = (Get-Date -Format yyyy-MM-dd) + " " + (Get-Date -Format hh:mm:ss)
$install_date = (Get-Date -Format yyyy-MM-dd) + "_" + (Get-Date -Format hh:mm:ss) | ForEach-Object { $_ -replace ":", "" }
##############################################
# Components to install
##############################################
# Choose the version you are installing
$vspc_v5 = 0
$vspc_v6 = 1

# To install on server where VSPC Server is installed
$install_server = 1
$install_connectwise_manage_server = 1

# To install on server where VSPC WebUI is Installed
$install_webui = 1
$install_connectwise_manage_webui = 1
$install_connectwise_automate = 1

##############################################
# Variables
##############################################
# General
## Location of installation media including storing log files
$media_path = "C:\install\" # Change if desired, create and copy ISO and license files to it before you run the script.
#$iso = "VeeamServiceProviderConsole_5.0.0.6726_20210528.ISO" # Change to your ISO and copy into $media_path e.g. C:\install\
$iso = "VeeamServiceProviderConsole_6.0.0.7739_20210917.ISO" # Change to your ISO and copy into $media_path e.g. C:\install\

# VSPC Server
$license = "vspc-license.lic" # Change to your VCC/VSPC license file and copy into $media_path e.g. C:\install\

$VSPC_SERVER_NAME = "" # Change to FQDN/IP of your VSPC Server
$VSPC_SERVER_SERVICE_ACCOUNT_USERNAME = "" #  Service account under which VSPC Server service will run, make sure it's added to Local Admin group
$VSPC_SERVER_SERVICE_ACCOUNT_PASSWORD = ""

$VSPC_SERVER_INSTALLDIR = "C:\Program Files\Veeam\Availability Console" # Default
$VSPC_SERVER_MANAGEMENT_PORT = "1989" # Default=1989
$VSPC_SERVER_CONNECTION_HUB_PORT = "9999" # Default=9999

$VSPC_SQL_SERVER = "" # Change to FQDN/IP of your MSSQL Server
$VSPC_SQL_DATABASE_NAME = "VSPC-$install_date" # Change to DB name of choice if desired
$VSPC_SQL_AUTHENTICATION_MODE = "" # 0=Windows, 1=SQL; When set to Windows, make sure the service account can access the MSSQL database
$VSPC_SQL_USER_USERNAME = "" # Set when SQL authentication is used
$VSPC_SQL_USER_PASSWORD = "" # Set when SQL authentication is used

# VSPC WebUI
$VSPC_WEBUI_INSTALLDIR = "C:\Program Files\Veeam\Availability Console" # Default
$VSPC_SERVER_PORT = "1989" # Default=1989
$VSPC_RESTAPI_PORT = "1281" # Default=1281
$VSPC_WEBSITE_PORT = "1280" # Default=1280
$VSPC_CONFIGURE_SCHANNEL = "1" # Default=1
$VSPC_WEBUI_USERNAME = "" # v6 only - Service account under which Web UI service will run
$VSPC_WEBUI_PASSWORD = "" # v6 only

# ConnectWise Manage Plugin
$CW_MANAGE_INSTALLDIR = "C:\Program Files\Veeam\Availability Console\Integrations\" # Default
$CW_MANAGE_USERNAME = "" #  Service account under which Plugin service will run
$CW_MANAGE_PASSWORD = ""
$CW_MANAGE_COMMPORT = "9996" # Default=9996
$VSPC_SERVER_CW_USERNAME= "" # v6 only - Service account to connect to VSPC Server
$VSPC_SERVER_CW_PASSWORD= "" # v6 only

# ConnectWise Automate Plugin
$CW_AUTOMATE_INSTALLDIR = "C:\Program Files\Veeam\Availability Console\Integrations\ConnectWiseAutomate\" # Default

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
# PREREQUISITES
##############################################
# Mount ISO
My-Logger "Mounting $iso ..."
$mount_iso = $media_path + $iso
Mount-DiskImage -ImagePath $mount_iso -PassThru -Access ReadOnly -StorageType ISO
$iso_driveletter = (Get-DiskImage -ImagePath $mount_iso | Get-Volume).DriveLetter
$source = $iso_driveletter + ":"
My-Logger "Mounted $source\$iso ..."

if($install_webui -eq 1){
    # Microsoft IIS components
    $app = "Microsoft IIS components"
    $log = "prereq-iis.log"
    My-Logger "Installing $app ..."
    
    if($vspc_v5 -eq 1){
        Install-WindowsFeature Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, Web-Asp-Net45, Web-ISAPI-Ext -Restart:$false -ErrorVariable WindowsFeatureFailure | Out-Null
    }
    if($vspc_v6 -eq 1){
        Install-WindowsFeature Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, Web-Asp-Net45, Web-ISAPI-Ext, Web-WebSockets -Restart:$false -ErrorVariable WindowsFeatureFailure | Out-Null
    }
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
    # Microsoft SQL Native Client 2012
    $app = "Microsoft SQL Native Client 2012"
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
if($install_webui -eq 1){
    # Microsoft ASP.NET Core Module V2
    $app = "Microsoft ASP.NET Core Module V2"
    $log = "prereq-aspdotnetcore.log"
    My-Logger "Installing $app ..."

    # v5 uses dotnet-hosting-2.2.4-win.exe
    # v6 uses dotnet-hosting-2.2.8-win.exe
    $dotnet_hosting_version = (Get-ChildItem -Path "$source\Redistr\dotnet*").Name
    $dotnet_hosting = $source + "\Redistr\" + $dotnet_hosting_version
    Start-Process -NoNewWindow -FilePath $dotnet_hosting -ArgumentList "/Installation /quiet /log $media_path$log" -Wait
    if (Select-String -Path "$media_path$log" -Pattern "Apply complete, result: 0x0") {
        My-Logger "Installing $app SUCCESS"
    }
    else {
        My-Logger "Installing $app FAILED"
    }
}
if($install_webui -eq 1 -and $vspc_v6 -eq 1){
    # IIS URL Rewrite Module 2.1
    $app = "IIS URL Rewrite Module 2.1"
    $log = "prereq-iisurlrewrite.log"
   
    $MSIArguments = @(
        "/i"
        "$source\Redistr\x64\rewrite_amd64_en-US.msi"
        "/qn"
        "/norestart"
        "/L*v"
        "$media_path$log"
    )
    Install-MSI $MSIArguments
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
        "INSTALLDIR=`"$VSPC_SERVER_INSTALLDIR`""
        "VAC_LICENSE_FILE=`"$media_path$license`""
        "VAC_SERVICE_ACCOUNT_NAME=`"$VSPC_SERVER_SERVICE_ACCOUNT_USERNAME`""
        "VAC_SERVICE_ACCOUNT_PASSWORD=`"$VSPC_SERVER_SERVICE_ACCOUNT_PASSWORD`""
        "VAC_SQL_SERVER=`"$VSPC_SQL_Server`""
        "VAC_DATABASE_NAME=`"$VSPC_SQL_DATABASE_NAME`""
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
        "INSTALLDIR=`"$VSPC_SERVER_INSTALLDIR`""
        "VAC_LICENSE_FILE=`"$media_path$license`""
        "VAC_SERVICE_ACCOUNT_NAME=`"$VSPC_SERVER_SERVICE_ACCOUNT_USERNAME`""
        "VAC_SERVICE_ACCOUNT_PASSWORD=`"$VSPC_SERVER_SERVICE_ACCOUNT_PASSWORD`""
        "VAC_SQL_SERVER=`"$VSPC_SQL_Server`""
        "VAC_DATABASE_NAME=`"$VSPC_SQL_DATABASE_NAME`""
        "VAC_SERVER_MANAGEMENT_PORT=`"$VSPC_SERVER_MANAGEMENT_PORT`""
        "VAC_CONNECTION_HUB_PORT=`"$VSPC_SERVER_CONNECTION_HUB_PORT`""
        "ACCEPT_THIRDPARTY_LICENSES=`"1`""
        "ACCEPT_EULA=`"1`""
        "/norestart"
        )
    }
    Install-MSI $MSIArguments
}
##############################################
# VSPC WEBUI
##############################################
if($install_webui -eq 1){
    $app = "Veeam Service Provider Console Web UI"
    $log = "vspc-webui.log"

    if($vspc_v5 -eq 1){
        $MSIArguments = @(
            "/L*v"
            """$media_path$log"""
            "/qn"
            "/i"
            """$source\WebUI\VAC.WebUI.x64.msi"""
            "INSTALLDIR=`"$VSPC_WEBUI_INSTALLDIR`""
            "VAC_SERVER_NAME=$VSPC_SERVER_NAME"
            "VAC_SERVER_PORT=`"$VSPC_SERVER_PORT`""
            "VAC_RESTAPI_PORT=`"$VSPC_RESTAPI_PORT`""
            "VAC_WEBSITE_PORT=`"$VSPC_WEBSITE_PORT`""
            "VAC_CONFIGURE_SCHANNEL=`"$VSPC_CONFIGURE_SCHANNEL`""
            "ACCEPT_THIRDPARTY_LICENSES=`"1`""
            "ACCEPT_EULA=`"1`""
            "/norestart"
        )
    }
    if($vspc_v6 -eq 1){
        $MSIArguments = @(
            "/L*v"
            """$media_path$log"""
            "/qn"
            "/i"
            """$source\WebUI\VAC.WebUI.x64.msi"""
            "INSTALLDIR=`"$VSPC_WEBUI_INSTALLDIR`""
            "VAC_SERVER_NAME=$VSPC_SERVER_NAME"
            "VAC_SERVER_ACCOUNT_NAME=`"$VSPC_WEBUI_USERNAME`""
            "VAC_SERVER_ACCOUNT_PASSWORD=`"$VSPC_WEBUI_PASSWORD`""
            "VAC_SERVER_PORT=`"$VSPC_SERVER_PORT`""
            "VAC_RESTAPI_PORT=`"$VSPC_RESTAPI_PORT`""
            "VAC_WEBSITE_PORT=`"$VSPC_WEBSITE_PORT`""
            "VAC_CONFIGURE_SCHANNEL=`"$VSPC_CONFIGURE_SCHANNEL`""
            "ACCEPT_THIRDPARTY_LICENSES=`"1`""
            "ACCEPT_EULA=`"1`""
            "/norestart"
        )
    }
    Install-MSI $MSIArguments
}
##############################################
# ConnectWise Manage Plugin Server
##############################################
if($install_connectwise_manage_server -eq 1){
    $app = "ConnectWise Manage Plugin Server"
    $log = "connectwise-manage-server.log"

    if($vspc_v5 -eq 1){
        $MSIArguments = @(
            "/L*v"
            """$media_path\$log"""
            "/qn"
            "/i"
            """$source\Plugins\ConnectWise\Manage\VAC.ConnectorService.x64.msi"""
            "ACCEPT_THIRDPARTY_LICENSES=`"1`""
            "ACCEPT_EULA=`"1`""
            "INSTALLDIR=`"$CW_MANAGE_INSTALLDIR`""
            "USERNAME=`"$CW_MANAGE_USERNAME`""
            "PASSWORD=`"$CW_MANAGE_PASSWORD`""
            #"SERVERNAME=`"$VSPC_SERVER_NAME`""
            "VAC_CW_COMMUNICATION_PORT=`"$CW_MANAGE_COMMPORT`""
            "/norestart"
        )
    }
    if($vspc_v6 -eq 1){
        $MSIArguments = @(
            "/L*v"
            """$media_path\$log"""
            "/qn"
            "/i"
            """$source\Plugins\ConnectWise\Manage\VAC.ConnectorService.x64.msi"""
            "ACCEPT_THIRDPARTY_LICENSES=`"1`""
            "ACCEPT_EULA=`"1`""
            "INSTALLDIR=`"$CW_MANAGE_INSTALLDIR`""
            "USERNAME=`"$CW_MANAGE_USERNAME`""
            "PASSWORD=`"$CW_MANAGE_PASSWORD`""
            "SERVER_ACCOUNT_NAME=`"$VSPC_SERVER_CW_USERNAME`""
            "SERVER_ACCOUNT_PASSWORD=`"$VSPC_SERVER_CW_PASSWORD`""
            "SERVER_NAME=`"$VSPC_SERVER_NAME`""
            "VAC_CW_COMMUNICATION_PORT=`"$CW_MANAGE_COMMPORT`""
            "/norestart"
        )
    }
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
        "INSTALLDIR=`"$CW_AUTOMATE_INSTALLDIR`""
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