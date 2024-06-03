using namespace System.ServiceProcess

param (
    [string] $RiotClientPath = 'C:\Riot Games\League of Legends\Riot Client\RiotClientServices.exe',
    [string] $PatchLine = 'live',
    [string] $Product = 'league_of_legends',
    [switch] $Cleanup,
    [int] $StopRetry = 10,
    [double] $StopBackoffTimer = 5
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

[hashtable] $LaunchParams = @{
    FilePath = $RiotClientPath
    WorkingDirectory = (Split-Path -Parent -Path $RiotClientPath)
    ArgumentList = @(
        "--launch-product=$Product",
        "--launch-patchline=$PatchLine"
    )
}

# VGK should be first, as VGC expects it to be running.
[ServiceController[]] $services = (Get-Service -name 'vgk'), (Get-Service -name 'vgc')

if ($services.Where({$null -eq $_}).Count -gt 0) {
    Write-Error 'Could not find Vanguard service(s)'
    Read-Host
    exit 1
}

Write-Host 'Starting Vanguard...'
foreach ($service in $services) {
    # We don't REALLY need to know this, but it may be nice for the user to be aware.
    if ($service.StartType -ne 'Disabled') {
        Write-Warning "$($service.Name) was not previously disabled"
    }
    $service | Set-Service -StartupType Manual

    if ($service.Status -eq 'Running') {
        Write-Warning "$($service.Name) was already running!"
        continue
    }
    $service | Start-Service
    if ($service.Status -ne 'Running') {
        Write-Error "Service '$($service.Name)' did not start"
        Read-Host
        exit 1
    }
}

if (-not $Cleanup) {
    Write-Information 'Starting Game...'
    try {
        Start-Process -Wait @LaunchParams
    }
    catch {
        # Continue on error so we can still tear-down.
        Write-Error "Unable to launch Riot Client at '$RiotClientPath'" -ErrorAction Continue
    }
    Write-Information 'Game exited'
}

Write-Information 'Stopping and disabling Vanguard:'
# Run these backwards, since VGK doesn't want to stop if VGC is running.
[array]::Reverse($services)
foreach ($service in $services) {
    Write-Information "Stopping $($service.Name)..."

    # For some reason, these don't like stopping the first time, so let's give it a couple tries.
    for ($i = 1; $i -lt ($StopRetry + 1); $i++) {
        Start-Sleep -Seconds ($StopBackoffTimer * $i)
        try {
            $service | Stop-Service
            Write-Information "`t$($service.Name) stopped"
            break
        }
        catch {
            Write-Warning "$($service.Name) did not stop, retrying $i / $StopRetry"
            continue
        }
    }
    $service | Set-Service -StartupType Disabled
    if ($service.Status -ne 'Stopped') {
        Write-Error "Service '$($service.Name)' did not stop. Vanguard is still running!"
        Read-Host
        exit 1
    }
}
Write-Information 'Done'