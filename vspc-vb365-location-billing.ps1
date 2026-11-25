<#
.SYNOPSIS
    Storage and license consumption per Microsoft 365 organization for one VSPC company
    (Veeam Backup for Microsoft 365 plug-in).

.DESCRIPTION
    Input is the VSPC organization (company) name. The script discovers everything else:

      1. POST /api/v3/token                                              (OAuth2IssueToken)
      2. GET  /infrastructure/vb365Servers/organizations/companyMappings  -> M365 orgs of the company
      3. GET  /infrastructure/vb365Servers/organizations/jobs             -> backup jobs per M365 org
      4. GET  /infrastructure/vb365Servers/{server}/organizations/jobs/backup/{job}/availableBackupRepositories
                                                                          -> repository + usedSpaceBytes
      5. GET  /protectedWorkloads/vb365ProtectedObjects                   -> licensed users per M365 org
      6. GET  /licensing/usage/organizations?serverType=VB365             -> company license usage (cross-check)

    Output:
      - VSPC company: total licensed users
      - Per M365 organization: licensed users, then its backup repositories with
        used storage, location and jobs.

.PARAMETER OrganizationName
    VSPC organization (company) name, e.g. PV_M365-shared.

.PARAMETER VspcServer
    VSPC hostname. Overrides the 1Password 'server' field.

.PARAMETER VspcPort
    VSPC REST API port. Overrides the 1Password 'port' field. Default: 1280

.PARAMETER Credential
    VSPC credentials. If omitted, read from 1Password (op CLI).

.PARAMETER OpVault
    1Password vault holding the VSPC item. Default: homelab-automation

.PARAMETER OpItem
    1Password item with username, password, server and port fields. Default: vspc-api

.PARAMETER No1Password
    Don't use 1Password; prompt for credentials instead.

.PARAMETER OutputFolder
    If set, CSV files (per org, per repository) are written here.

.PARAMETER SkipCertificateCheck
    Skip TLS certificate validation (self-signed lab certs).

.EXAMPLE
    ./vspc-vb365-location-billing.ps1 -OrganizationName 'PV_M365-shared' -SkipCertificateCheck

.EXAMPLE
    # Without 1Password: prompts for username and password
    ./vspc-vb365-location-billing.ps1 -OrganizationName 'PV_M365-shared' `
        -VspcServer 'vspc.example.com' -VspcPort 1280 -No1Password -SkipCertificateCheck

.EXAMPLE
    # Without 1Password, non-interactive: pass a PSCredential
    $cred = Get-Credential
    ./vspc-vb365-location-billing.ps1 -OrganizationName 'PV_M365-shared' `
        -VspcServer 'vspc.example.com' -Credential $cred -OutputFolder ./reports

.NOTES
    Requires PowerShell 7+ and the 1Password CLI (op), signed in, unless -Credential or -No1Password is used.
    Assumes repositories are dedicated per M365 organization (e.g. one S3 bucket per org);
    usedSpaceBytes is a repository-wide value.
    VB365 licenses are per user: a user protected in two repositories counts once.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('CompanyName')][string]$OrganizationName,
    [string]$VspcServer,
    [int]$VspcPort,
    [PSCredential]$Credential,
    [string]$OpVault = 'homelab-automation',
    [string]$OpItem  = 'vspc-api',
    [switch]$No1Password,
    [string]$OutputFolder,
    [switch]$SkipCertificateCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Connection settings (1Password) ──────────────────────────────────────

if (-not $No1Password -and (-not $Credential -or -not $VspcServer)) {
    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
        throw '1Password CLI (op) not found. Install it, or use -Credential / -No1Password.'
    }
    Write-Host "[0/6] Reading '$OpItem' from 1Password vault '$OpVault'..." -ForegroundColor Cyan
    $opJson = & op item get $OpItem --vault $OpVault --reveal --format json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "1Password lookup failed: $opJson" }
    $opFields = @{}
    foreach ($f in @(($opJson | Out-String | ConvertFrom-Json).fields)) {
        if ($f.PSObject.Properties['label'] -and $f.PSObject.Properties['value'] -and $f.label) {
            $opFields[$f.label] = $f.value
        }
    }
    if (-not $Credential) {
        if (-not $opFields['username'] -or -not $opFields['password']) {
            throw "1Password item '$OpItem' has no username/password."
        }
        $Credential = [PSCredential]::new($opFields['username'],
            (ConvertTo-SecureString $opFields['password'] -AsPlainText -Force))
    }
    if (-not $VspcServer -and $opFields['server']) { $VspcServer = $opFields['server'] }
    if (-not $VspcPort   -and $opFields['port'])   { $VspcPort   = [int]$opFields['port'] }
    $opFields = $null; $opJson = $null
    Write-Host "  ✓ $($Credential.UserName) @ ${VspcServer}:$(if ($VspcPort) { $VspcPort } else { 1280 })" -ForegroundColor Green
}
if (-not $VspcServer) { throw 'No VSPC server: pass -VspcServer or add a "server" field to the 1Password item.' }
if (-not $VspcPort)   { $VspcPort = 1280 }

#endregion

$vspcBase = "https://${VspcServer}:${VspcPort}/api/v3"

#region ── Helpers ─────────────────────────────────────────────────────────────

function Format-Size {
    param($Bytes)
    if ($null -eq $Bytes) { return 'n/a' }
    $b = [double]$Bytes
    if ($b -ge 1TB) { return '{0:N2} TB' -f ($b / 1TB) }
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    return '{0:N2} MB' -f ($b / 1MB)
}

function Invoke-Vspc {
    param([string]$Path)
    $uri = "$vspcBase$Path"
    try {
        Invoke-RestMethod -Uri $uri -Method GET -Headers $script:Headers `
            -SkipCertificateCheck:$SkipCertificateCheck.IsPresent
    } catch {
        throw "GET $uri failed: $($_.Exception.Message) $($_.ErrorDetails.Message)"
    }
}

# Returns every item of a paged collection (VSPC: { meta.pagingInfo.total, data[] }).
function Get-VspcCollection {
    param([string]$Path, [int]$PageSize = 500)
    $all    = [System.Collections.Generic.List[object]]::new()
    $offset = 0
    while ($true) {
        $sep   = if ($Path -match '\?') { '&' } else { '?' }
        $resp  = Invoke-Vspc "${Path}${sep}limit=${PageSize}&offset=${offset}"
        $items = @($resp.data)
        foreach ($i in $items) { $all.Add($i) }
        $total = $null
        if ($resp.PSObject.Properties['meta'] -and $resp.meta -and
            $resp.meta.PSObject.Properties['pagingInfo'] -and $resp.meta.pagingInfo) {
            $total = [int]$resp.meta.pagingInfo.total
        }
        $offset += $PageSize
        if ($items.Count -lt $PageSize -or ($null -ne $total -and $all.Count -ge $total)) { break }
    }
    return , $all.ToArray()
}

# Protected object id is "<objectId>:<repositoryUid>"; strip the repository part so a user
# protected in several repositories is counted once.
function Get-ObjectKey {
    param($Obj)
    if ($Obj.id -and $Obj.id -match '^(.+):[0-9a-fA-F-]{36}$') { return $Matches[1] }
    if ($Obj.id) { return $Obj.id }
    return $Obj.name
}

function Get-LicensedUserKeys {
    param([object[]]$Objects)
    @($Objects | Where-Object { $_.consumesLicense -eq $true -and "$($_.protectedDataType)" -eq 'User' } |
        ForEach-Object { Get-ObjectKey $_ } | Sort-Object -Unique)
}

#endregion

#region ── 1. Authentication ───────────────────────────────────────────────────

if (-not $Credential) { $Credential = Get-Credential -Message "VSPC credentials for $VspcServer" }

Write-Host "[1/6] Authenticating to $VspcServer..." -ForegroundColor Cyan
try {
    $tokenResp = Invoke-RestMethod -Uri "$vspcBase/token" -Method POST `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            grant_type = 'password'
            username   = $Credential.UserName
            password   = $Credential.GetNetworkCredential().Password
        } -SkipCertificateCheck:$SkipCertificateCheck.IsPresent
} catch {
    throw "Authentication failed: $($_.Exception.Message) $($_.ErrorDetails.Message)"
}
if (-not $tokenResp.access_token) {
    throw 'No access token returned (account may require MFA). Use an API account without MFA.'
}
$script:Headers = @{
    Authorization = "Bearer $($tokenResp.access_token)"
    Accept        = 'application/json'
}
Write-Host '  ✓ Token acquired.' -ForegroundColor Green

#endregion

#region ── 2. M365 organizations mapped to the VSPC company ──────────────────────

Write-Host "[2/6] Finding M365 organizations of '$OrganizationName'..." -ForegroundColor Cyan
$mappings = Get-VspcCollection '/infrastructure/vb365Servers/organizations/companyMappings'
$orgMaps  = @($mappings | Where-Object companyName -eq $OrganizationName)

if ($orgMaps.Count -eq 0) {
    Write-Host '  Companies with mapped M365 organizations:' -ForegroundColor Yellow
    $mappings | Select-Object companyName, vb365OrganizationName, vb365ServerName | Sort-Object companyName |
        Format-Table -AutoSize | Out-Host
    throw "No M365 organizations mapped to VSPC organization '$OrganizationName'."
}
$companyUid = $orgMaps[0].companyUid
foreach ($m in $orgMaps) {
    Write-Host "  ✓ $($m.vb365OrganizationName) (on $($m.vb365ServerName))" -ForegroundColor Green
}

#endregion

#region ── 3. Protected objects ─────────────────────────────────────────────────

# No server-side organizationFilter: it returned nothing in testing, so match client-side.
# Match on M365 organization UID *or* name, in case UIDs differ between endpoints.
$orgNames = @($orgMaps | ForEach-Object { $_.vb365OrganizationName } | Sort-Object -Unique)
$orgUids  = @{}   # M365 org name -> HashSet of known UIDs
foreach ($n in $orgNames) {
    $orgUids[$n] = [System.Collections.Generic.HashSet[string]]::new()
    $orgMaps | Where-Object vb365OrganizationName -eq $n | ForEach-Object { [void]$orgUids[$n].Add("$($_.vb365OrganizationUid)") }
}
function Resolve-M365Org {
    param([string]$Uid, [string]$Name)
    foreach ($n in $orgNames) {
        if (($Name -and $Name -eq $n) -or ($Uid -and $orgUids[$n].Contains($Uid))) { return $n }
    }
    return $null
}

Write-Host '[3/6] Fetching protected objects...' -ForegroundColor Cyan
$allProtected = Get-VspcCollection '/protectedWorkloads/vb365ProtectedObjects'
$protected = [System.Collections.Generic.List[object]]::new()
foreach ($o in $allProtected) {
    $n = Resolve-M365Org -Uid $o.vb365OrganizationUid -Name $o.vb365OrganizationName
    if (-not $n) { continue }
    [void]$orgUids[$n].Add("$($o.vb365OrganizationUid)")   # learn UID alias for job matching
    $o | Add-Member -NotePropertyName M365Org -NotePropertyValue $n -Force
    $protected.Add($o)
}
$protected = $protected.ToArray()
Write-Host "  ✓ $($protected.Count) of $($allProtected.Count) protected object entries belong to these organizations." -ForegroundColor Green
if ($protected.Count -eq 0 -and $allProtected.Count) {
    Write-Host '  Organizations seen in protected objects:' -ForegroundColor Yellow
    $allProtected | Group-Object vb365OrganizationName, vb365OrganizationUid, organizationName -NoElement |
        Format-Table Count, Name -AutoSize | Out-Host
}

#endregion

#region ── 4. Backup jobs ───────────────────────────────────────────────────────

Write-Host '[4/6] Fetching VB365 jobs...' -ForegroundColor Cyan
$allJobs = Get-VspcCollection '/infrastructure/vb365Servers/organizations/jobs'
$jobs = [System.Collections.Generic.List[object]]::new()
foreach ($j in $allJobs) {
    $n = Resolve-M365Org -Uid $j.vb365OrganizationUid
    if (-not $n) { continue }
    $j | Add-Member -NotePropertyName M365Org -NotePropertyValue $n -Force
    $jobs.Add($j)
    Write-Host ("  ✓ {0,-32} {1,-30} {2,-9} -> {3}" -f $n, $j.name, $j.jobType, $j.repositoryName) -ForegroundColor Green
}
$jobs = $jobs.ToArray()
if ($jobs.Count -eq 0) {
    Write-Warning "No jobs matched ($($allJobs.Count) jobs visible). Repositories will be derived from protected objects."
    if ($allJobs.Count) {
        $allJobs | Select-Object name, vb365OrganizationUid, vspcOrganizationName, repositoryName |
            Format-Table -AutoSize | Out-Host
    }
}

#endregion

#region ── 5. Backup repositories ───────────────────────────────────────────────

Write-Host '[5/6] Fetching backup repository details...' -ForegroundColor Cyan
$repoCache      = @{}   # repositoryUid -> Vb365BackupRepository
$serverRepoList = @{}   # vb365ServerUid -> all repositories on that server

function Get-ServerRepo {
    param([string]$ServerUid, [string]$RepoUid)
    if (-not $ServerUid) { return $null }
    if (-not $serverRepoList.ContainsKey($ServerUid)) {
        $serverRepoList[$ServerUid] = Get-VspcCollection "/infrastructure/vb365Servers/$ServerUid/backupRepositories"
    }
    $serverRepoList[$ServerUid] | Where-Object instanceUid -eq $RepoUid | Select-Object -First 1
}

# Repositories referenced by jobs (preferred: job's available repositories)
foreach ($j in $jobs) {
    if (-not $j.repositoryUid -or $repoCache.ContainsKey($j.repositoryUid)) { continue }
    $repo = $null
    if ($j.jobType -eq 'BackupJob') {
        $avail = Get-VspcCollection "/infrastructure/vb365Servers/$($j.vb365ServerUid)/organizations/jobs/backup/$($j.instanceUid)/availableBackupRepositories"
        $repo  = $avail | Where-Object instanceUid -eq $j.repositoryUid | Select-Object -First 1
    }
    if (-not $repo) { $repo = Get-ServerRepo $j.vb365ServerUid $j.repositoryUid }
    if ($repo) { $repoCache[$j.repositoryUid] = $repo }
}
# Repositories only seen in protected objects (e.g. job no longer exists)
foreach ($o in $protected) {
    if (-not $o.repositoryUid -or $repoCache.ContainsKey($o.repositoryUid)) { continue }
    $repo = Get-ServerRepo $o.vb365ServerUid $o.repositoryUid
    if ($repo) { $repoCache[$o.repositoryUid] = $repo }
}
foreach ($r in $repoCache.Values) {
    Write-Host ("  ✓ {0,-25} used {1}" -f $r.name, (Format-Size $r.usedSpaceBytes)) -ForegroundColor Green
}

#endregion

#region ── 6. Company license usage (cross-check) ───────────────────────────────

Write-Host '[6/6] Fetching VSPC license usage (VB365)...' -ForegroundColor Cyan
$licenseUsageUsers = $null
try {
    $usage = Get-VspcCollection "/licensing/usage/organizations?organizationUid=$companyUid&serverType=VB365"
    $vb365Workloads = @($usage | Where-Object organizationUid -eq $companyUid |
                        ForEach-Object { $_.servers } | Where-Object serverType -eq 'VB365' |
                        ForEach-Object { $_.workloads })
    if ($vb365Workloads.Count) {
        $licenseUsageUsers = ($vb365Workloads | Measure-Object -Property usedCount -Sum).Sum
    }
    Write-Host "  ✓ $licenseUsageUsers licensed users reported by VSPC licensing." -ForegroundColor Green
} catch {
    Write-Warning "License usage lookup failed: $_"
}

#endregion

#region ── Build report ─────────────────────────────────────────────────────────

$orgReport  = [System.Collections.Generic.List[object]]::new()
$repoReport = [System.Collections.Generic.List[object]]::new()

foreach ($orgName in $orgNames) {
    $orgObjs = @($protected | Where-Object M365Org -eq $orgName)
    $orgJobs = @($jobs      | Where-Object M365Org -eq $orgName)
    $orgRepoUids = @(@($orgJobs) + @($orgObjs) | ForEach-Object { $_.repositoryUid } | Where-Object { $_ } | Sort-Object -Unique)
    $orgBytes = [long]0

    foreach ($repoUid in $orgRepoUids) {
        $repo     = $repoCache[$repoUid]
        $repoJobs = @($orgJobs | Where-Object repositoryUid -eq $repoUid)
        $repoObjs = @($orgObjs | Where-Object repositoryUid -eq $repoUid)
        $location = (@(@($repoObjs) + @($repoJobs) | ForEach-Object { $_.locationName }) |
                     Where-Object { $_ } | Sort-Object -Unique) -join ', '
        $bytes    = if ($repo) { $repo.usedSpaceBytes } else { $null }
        if ($bytes) { $orgBytes += [long]$bytes }

        $repoReport.Add([PSCustomObject]@{
            CompanyName      = $OrganizationName
            M365Organization = $orgName
            Repository       = if ($repo) { $repo.name } else { (@($repoJobs) + @($repoObjs))[0].repositoryName }
            UsedSpace        = Format-Size $bytes
            UsedSpaceBytes   = $bytes
            Location         = if ($location) { $location } else { '(none)' }
            LicensedUsers    = @(Get-LicensedUserKeys $repoObjs).Count
            Jobs             = (@($repoJobs | ForEach-Object { $_.name }) | Sort-Object) -join ', '
            VB365Server      = (@(@($repoJobs) + @($repoObjs) | ForEach-Object { $_.vb365ServerName }) | Where-Object { $_ } | Sort-Object -Unique) -join ', '
        })
    }

    $orgReport.Add([PSCustomObject]@{
        CompanyName      = $OrganizationName
        M365Organization = $orgName
        LicensedUsers    = @(Get-LicensedUserKeys $orgObjs).Count
        Repositories     = $orgRepoUids.Count
        UsedSpace        = Format-Size $orgBytes
        UsedSpaceBytes   = $orgBytes
    })
}

$companyLicensed = @(Get-LicensedUserKeys $protected).Count
$companyBytes    = ($orgReport | Measure-Object UsedSpaceBytes -Sum).Sum

#endregion

#region ── Output ───────────────────────────────────────────────────────────────

Write-Host ''
Write-Host "══ VSPC organization: $OrganizationName ══" -ForegroundColor White
Write-Host ("   Licensed users (total) : {0}" -f $companyLicensed)
if ($null -ne $licenseUsageUsers -and $licenseUsageUsers -ne $companyLicensed) {
    Write-Host ("   VSPC license usage reports {0} (may lag until the next license data collection)" -f $licenseUsageUsers) -ForegroundColor DarkYellow
}
Write-Host ("   Storage used (total)   : {0}" -f (Format-Size $companyBytes))

foreach ($o in $orgReport) {
    Write-Host ''
    Write-Host "── M365 organization: $($o.M365Organization)" -ForegroundColor Cyan
    Write-Host ("   Licensed users : {0}" -f $o.LicensedUsers)
    Write-Host ("   Storage used   : {0}" -f $o.UsedSpace)
    $repoReport | Where-Object M365Organization -eq $o.M365Organization |
        Format-Table Repository, UsedSpace, Location, LicensedUsers, Jobs -AutoSize | Out-Host
}

if ($OutputFolder) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $orgReport  | Export-Csv (Join-Path $OutputFolder "vb365_organizations_$stamp.csv") -NoTypeInformation
    $repoReport | Export-Csv (Join-Path $OutputFolder "vb365_repositories_$stamp.csv")  -NoTypeInformation
    Write-Host "CSV files written to $OutputFolder" -ForegroundColor Green
}

#endregion
