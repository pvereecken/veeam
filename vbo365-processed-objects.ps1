# NOTE:
# 1. Run the script locally on the VBO365 controller server.
# 2. Change the variables below if needed.

#############################################
# Variables
#############################################
$server = "localhost" # Enter localhost, FQDN or IP address of the VBO365 controller server.
$report_file = "C:\VBO365_processed objects.csv" # Path and filename where the report will be created.

#############################################
# Connect to VBO365 controller server
#############################################
Import-Module Veeam.Archiver.PowerShell
$server = Read-Host -Prompt "Enter VBO365 server FQDN/IP"
$creds = Get-Credential -Message "Enter VBO365 server credentials:"
Connect-VBOServer -Server $server -Credential $creds
#############################################
# Check processed objects PER JOB
#############################################
<#
Write-Host -ForegroundColor Green "Processed objects per job:"
$jobs = Get-VBOJob
foreach ($job in $jobs)
{
##Get-VBOJobSession -Job $job | Sort-Object -Property CreationTime | Where-Object {$_.Status -ne 'Failed'} | Select -Last 1 | Select Id, JobId, JobName, CreationTime, Progress
Get-VBOJobSession -Job $job | Sort-Object -Property CreationTime | Where-Object {$_.Status -ne 'Failed'} | Select -Last 1 | Select JobName, Progress
}
#>
#############################################
# Check processed objects PER PROXY
#############################################
$report = @()
$organizations = Get-VBOOrganization
$jobcount = (get-vbojob).count
$number = 1
foreach($org in $organizations)
{
    $proxyname = (Get-VBOProxy -Organization $org).Hostname
    $jobs = Get-VBOJob -Organization $org
    foreach($job in $jobs)
    {
        $session = Get-VBOJobSession -Job $job -Last | select Jobname, Progress
        $myObject1 = New-Object -TypeName PSObject
        $myObject1 | add-member -type Noteproperty -Name Organization -Value $org.Name
        $myObject1 | add-member -type Noteproperty -Name Proxy -Value $proxyname
        $myObject1 | add-member -type Noteproperty -Name Jobname -Value $session.JobName
        $myObject1 | add-member -type Noteproperty -Name Objects -Value $session.Progress
        
        $Report += $myObject1
    }
}
$report | export-csv $report_file -NoTypeInformation
Write-Host -ForegroundColor Green  "Report created at $report_file"

Disconnect-VBOServer