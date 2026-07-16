<#
  Oracle AI Database Free installer for Windows.
  Run: irm https://raw.githubusercontent.com/<owner>/oradbinstaller/main/install.ps1 | iex
#>
[CmdletBinding()]
param([switch]$NoRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Image = 'container-registry.oracle.com/database/free:latest'
$script:Runtime = $null

function Write-Info([string]$Message) { Write-Host "[oracle-free] $Message" }
function Write-Failure([string]$Message) { Write-Host "[oracle-free] ERROR: $Message" -ForegroundColor Red }

function Get-ContainerRuntime {
    # Podman is preferred because it does not require a privileged daemon.
    foreach ($candidate in @('podman', 'docker')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $candidate }
    }
    return $null
}

function Assert-ContainerRuntime([string]$Runtime) {
    try { & $Runtime info *> $null } catch {
        throw "'$Runtime' is installed but cannot start containers. Start it and retry. $($_.Exception.Message)"
    }
    if ($LASTEXITCODE -ne 0) { throw "'$Runtime info' failed. Start the container runtime and retry." }
}

function Show-PodmanInstructions {
    Write-Failure 'Neither Podman nor Docker was found.'
    Write-Host 'Install Podman Desktop, restart PowerShell, and run this installer again:'
    Write-Host '  https://podman-desktop.io/downloads/windows'
    Write-Host 'Podman requires WSL 2 or its managed virtual machine on Windows.'
}

function Read-Default([string]$Prompt, [string]$Default) {
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Read-YesNo([string]$Prompt, [bool]$Default = $false) {
    $fallback = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $answer = (Read-Host "$Prompt [$fallback]").Trim().ToLowerInvariant()
        if ([string]::IsNullOrEmpty($answer)) { return $Default }
        if ($answer -in @('y', 'yes')) { return $true }
        if ($answer -in @('n', 'no')) { return $false }
        Write-Host 'Please answer y or n.'
    }
}

function Test-OraclePassword([string]$Password) {
    # The image's administrative password must be reasonably complex and safe for an env argument.
    return $Password.Length -ge 8 -and $Password -match '[A-Z]' -and $Password -match '[a-z]' -and
        $Password -match '\d' -and $Password -notmatch '["''`$\\\s]'
}

function Read-OraclePassword {
    while ($true) {
        $secure = Read-Host 'Administrative password (will not be displayed)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        if (Test-OraclePassword $password) { return $password }
        Write-Host 'Use 8+ characters including upper-case, lower-case, and a digit; avoid spaces, quotes, backticks, dollar signs, and backslashes.' -ForegroundColor Yellow
    }
}

function Test-Name([string]$Value) { return $Value -match '^[A-Za-z0-9][A-Za-z0-9_.-]*$' }
function Test-Port([string]$Value) { $n = 0; return [int]::TryParse($Value, [ref]$n) -and $n -ge 1 -and $n -le 65535 }

function Read-ValidDefault([string]$Prompt, [string]$Default, [scriptblock]$Validator, [string]$ErrorText) {
    while ($true) {
        $value = Read-Default $Prompt $Default
        if (& $Validator $value) { return $value }
        Write-Host $ErrorText -ForegroundColor Yellow
    }
}

function Get-InstallConfiguration {
    $advanced = Read-YesNo 'Use advanced installation options?' $false
    $config = [ordered]@{
        ContainerName = 'oracle-free'; VolumeName = 'oracle-free-data'; Port = '1521'
        CharacterSet = 'AL32UTF8'; ArchiveLog = 'false'; ForceLogging = 'false'; Password = (Read-OraclePassword)
    }
    if ($advanced) {
        $config.ContainerName = Read-ValidDefault 'Container name' $config.ContainerName ${function:Test-Name} 'Use letters, numbers, dot, underscore, or hyphen.'
        $config.VolumeName = Read-ValidDefault 'Data volume name' $config.VolumeName ${function:Test-Name} 'Use letters, numbers, dot, underscore, or hyphen.'
        $config.Port = Read-ValidDefault 'Host listener port' $config.Port ${function:Test-Port} 'Use a port between 1 and 65535.'
        $config.CharacterSet = Read-Default 'Database character set' $config.CharacterSet
        $config.ArchiveLog = if (Read-YesNo 'Enable archive logging?' $false) { 'true' } else { 'false' }
        $config.ForceLogging = if (Read-YesNo 'Enable force logging?' $false) { 'true' } else { 'false' }
    }
    return $config
}

function Start-OracleFree([System.Collections.IDictionary]$Config) {
    & $script:Runtime pull $script:Image
    if ($LASTEXITCODE -ne 0) { throw "Could not pull $script:Image. Sign in to Oracle Container Registry and accept its licence if prompted." }
    & $script:Runtime container inspect $Config.ContainerName *> $null
    if ($LASTEXITCODE -eq 0) { throw "Container '$($Config.ContainerName)' already exists. Choose a different name or remove it explicitly." }
    $run = @('run', '-d', '--name', $Config.ContainerName, '-p', "$($Config.Port):1521", '-v', "$($Config.VolumeName):/opt/oracle/oradata",
        '-e', "ORACLE_PWD=$($Config.Password)", '-e', "ORACLE_CHARACTERSET=$($Config.CharacterSet)",
        '-e', "ENABLE_ARCHIVELOG=$($Config.ArchiveLog)", '-e', "ENABLE_FORCE_LOGGING=$($Config.ForceLogging)", $script:Image)
    & $script:Runtime @run
    if ($LASTEXITCODE -ne 0) { throw 'The container could not be started. Review runtime output above.' }
}

function Wait-OracleFree([System.Collections.IDictionary]$Config) {
    Write-Info 'Waiting for Oracle Database Free to become ready (this can take several minutes)...'
    foreach ($attempt in 1..90) {
        $logs = (& $script:Runtime logs $Config.ContainerName 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw "Container stopped while starting. Run: $script:Runtime logs $($Config.ContainerName)" }
        if ($logs -match 'DATABASE IS READY TO USE') { return }
        Start-Sleep -Seconds 4
    }
    & $script:Runtime logs --tail 100 $Config.ContainerName
    throw "Timed out waiting for the database. Run: $script:Runtime logs $($Config.ContainerName)"
}

function Get-SqlclCommand { return Get-Command sql -ErrorAction SilentlyContinue }

function Get-JavaMajorVersion {
    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($null -eq $java) { return $null }
    $output = (& java -version 2>&1 | Out-String)
    if ($output -match 'version "(?:(\d+)\.|1\.(\d+)\.)') {
        $major = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
        return [int]$major
    }
    return $null
}

function Install-Sqlcl {
    $destination = Join-Path $env:LOCALAPPDATA 'Oracle\sqlcl'
    $zip = Join-Path $env:TEMP 'sqlcl-latest.zip'
    $url = 'https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip'
    Write-Info 'Downloading SQLcl from Oracle...'
    Invoke-WebRequest -Uri $url -OutFile $zip
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $destination -Force
    $bin = Join-Path $destination 'sqlcl\bin'
    if (-not (Test-Path (Join-Path $bin 'sql.exe')) -and -not (Test-Path (Join-Path $bin 'sql'))) {
        throw "SQLcl download did not contain a SQL executable at $bin."
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $bin) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $bin).Trim(';')), 'User')
    }
    $env:Path += ";$bin"
    Write-Info "SQLcl installed in $destination. Open a new PowerShell window to use its permanent PATH entry."
}

function Handle-Sqlcl {
    $sql = Get-SqlclCommand
    if ($null -eq $sql -and -not (Read-YesNo 'SQLcl was not found. Install it natively now?' $true)) { return $false }
    $javaVersion = Get-JavaMajorVersion
    if ($null -eq $javaVersion -or $javaVersion -lt 17) {
        Write-Failure 'SQLcl needs Java 17 or later. Install a JDK, then rerun this installer or install SQLcl manually. The database remains running.'
        Write-Host '  winget install EclipseAdoptium.Temurin.17.JDK'
        return $false
    }
    if ($null -ne $sql) { Write-Info "Using existing SQLcl: $($sql.Source)"; return $true }
    Install-Sqlcl
    return $true
}

function Main {
    if ($env:OS -ne 'Windows_NT') { throw 'This entrypoint is for Windows. On macOS or Linux use install.sh.' }
    Write-Info "Detected operating system: $([Environment]::OSVersion.VersionString)"
    $script:Runtime = Get-ContainerRuntime
    if ($null -eq $script:Runtime) { Show-PodmanInstructions; exit 1 }
    Assert-ContainerRuntime $script:Runtime
    Write-Info "Using $script:Runtime."
    $config = Get-InstallConfiguration
    Start-OracleFree $config
    Wait-OracleFree $config
    $hasSqlcl = Handle-Sqlcl
    Write-Host ''
    Write-Info 'Oracle AI Database Free is ready.'
    if ($hasSqlcl) {
        Write-Host "Connect (SQLcl will prompt for the password):"
        Write-Host "  sql sys@localhost:$($config.Port)/FREEPDB1 as sysdba"
    } else { Write-Host "Install SQLcl later, then connect with: sql sys@localhost:$($config.Port)/FREEPDB1 as sysdba" }
}

if (-not $NoRun) { Main }
