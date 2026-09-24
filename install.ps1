[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^$|^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [ValidatePattern('^$|^[A-Za-z0-9_.-]+$')][string]$Version,
    [string]$InstallerPath,
    [ValidatePattern('^$|^[a-fA-F0-9]{64}$')][string]$Sha256,
    [switch]$NoLaunch,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
Write-Host @'
 ____  _____ ____  _  __ ____  _____ _____
|  _ \| ____/ ___|| |/ /|  _ \| ____|_   _|
| | | |  _| \___ \| ' / | |_) |  _|   | |
| |_| | |___ ___) | . \ |  __/| |___  | |
|____/|_____|____/|_|\_\|_|   |_____| |_|

  PIXEL COMPANIONS / BY Akuazzamq
'@ -ForegroundColor Magenta
if ($env:OS -ne 'Windows_NT') { throw 'DeskPet currently supports Windows only.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows is required.' }
if ($InstallerPath -and $Repository) { throw 'Choose either -InstallerPath or -Repository.' }
if (-not $InstallerPath -and -not $Repository) {
    $Repository = 'Akuazzamq/DeskPet'
}
if ($InstallerPath -and -not $Sha256) { throw 'A local installer requires -Sha256 for verification.' }
if ($WhatIfPreference) {
    Write-Host 'Would verify and install DeskPet for this user, with desktop and Start Menu shortcuts.'
    return
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$downloadFolder = $null
try {
    if ($Repository) {
        Write-Host '[1/3] Finding the latest release...' -ForegroundColor Cyan
        $headers = @{ 'User-Agent'='DeskPet-Installer'; 'Accept'='application/vnd.github+json' }
        $endpoint = if ($Version) { "tags/$Version" } else { "latest" }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/$endpoint" -Headers $headers
        $asset = @($release.assets | Where-Object name -eq 'DeskPet-Setup.exe')
        $checksums = @($release.assets | Where-Object name -eq 'SHA256SUMS.txt')
        if ($asset.Count -ne 1 -or $checksums.Count -ne 1) { throw 'Release must contain DeskPet-Setup.exe and SHA256SUMS.txt.' }
        foreach ($url in @($asset[0].browser_download_url,$checksums[0].browser_download_url)) {
            if (-not $url.StartsWith("https://github.com/$Repository/releases/download/",[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected release asset URL.' }
        }
        $downloadFolder = Join-Path ([IO.Path]::GetTempPath()) ('DeskPet-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $downloadFolder | Out-Null
        $InstallerPath = Join-Path $downloadFolder 'DeskPet-Setup.exe'
        Invoke-WebRequest -UseBasicParsing -Uri $asset[0].browser_download_url -OutFile $InstallerPath
        $rawManifest = (Invoke-WebRequest -UseBasicParsing -Uri $checksums[0].browser_download_url).Content
        $manifest = if ($rawManifest -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($rawManifest) } else { [string]$rawManifest }
        $match = [regex]::Match($manifest, '(?im)^([a-f0-9]{64})\s+\*?DeskPet-Setup\.exe\s*$')
        if (-not $match.Success) { throw 'Installer checksum missing from release manifest.' }
        $Sha256 = $match.Groups[1].Value
    }
    $InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
    Write-Host '[2/3] Verifying SHA-256...' -ForegroundColor Cyan
    if ((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -ne $Sha256) { throw 'Checksum mismatch. Installation cancelled.' }
    if ($CheckOnly) { Write-Host 'Package verified. Check-only mode: nothing installed.' -ForegroundColor Green; return }
    # Invoke-Expression does not provide a script-level PSCmdlet; direct execution does.
    $shouldInstall = if ($null -ne $PSCmdlet) { $PSCmdlet.ShouldProcess('Current Windows user', 'Install DeskPet and create shortcuts') } else { $true }
    if ($shouldInstall) {
        Write-Host '[3/3] Installing DeskPet...' -ForegroundColor Cyan
        $installerLog = Join-Path ([IO.Path]::GetTempPath()) 'DeskPet-install.log'
        $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/TASKS=desktopicon',('/LOG="' + $installerLog + '"'))
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
        if ($process.ExitCode -notin @(0,3010)) { throw "Setup failed (exit $($process.ExitCode)). See $installerLog" }
        Write-Host 'Installed! Open DeskPet from your desktop or Start Menu.' -ForegroundColor Green
        Write-Host 'Uninstall: Windows Settings > Apps > DeskPet'
        if (-not $NoLaunch) {
            $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B1F3654D-65A4-43EF-B2DB-61B7B1337A19}_is1'
            $location=(Get-ItemProperty -LiteralPath $key).InstallLocation
            Start-Process -FilePath (Join-Path $location 'DeskPet.exe') -WindowStyle Normal
        }
    }
} finally {
    if ($downloadFolder) {
        $file=Join-Path $downloadFolder 'DeskPet-Setup.exe'
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        if ((Get-ChildItem -LiteralPath $downloadFolder -Force | Measure-Object).Count -eq 0) { Remove-Item -LiteralPath $downloadFolder }
    }
}
