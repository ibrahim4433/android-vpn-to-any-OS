# --- CONFIGURATION ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\")).Path

$ConfigsDir = Join-Path $RepoRoot "configs"
$NewestVpnDir = Get-ChildItem -Path $ConfigsDir -Directory -Filter "ovpn*" | Sort-Object Name -Descending | Select-Object -First 1
if ($null -ne $NewestVpnDir) {
    $VpnDir = $NewestVpnDir.FullName
} else {
    $VpnDir = Join-Path $ConfigsDir "ovpn"
}

$LogsDir = Join-Path $RepoRoot "logs\openvpn"
$ResultsFile = Join-Path $RepoRoot "logs\vpn_benchmark_results_windows.csv"
$PassFile = Join-Path $RepoRoot "pass.txt"
$TestFileSize = 25000000
$Timeout = 15

# Auto-detect OpenVPN path
$OpenVpnPaths = @(
    "C:\Program Files\OpenVPN\bin\openvpn.exe",
    "C:\Program Files (x86)\OpenVPN\bin\openvpn.exe",
    "C:\Program Files\OpenVPN Connect\openvpn.exe"
)

$OpenVpnExe = $null
foreach ($path in $OpenVpnPaths) {
    if (Test-Path $path) {
        $OpenVpnExe = $path
        break
    }
}
# ---------------------

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to run OpenVPN..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    Exit
}

if (-not (Test-Path $VpnDir)) {
    Write-Host "ERROR: VPN config directory does not exist: $VpnDir" -ForegroundColor Red
    Exit 1
}

if ($null -eq $OpenVpnExe -or -not (Test-Path $OpenVpnExe)) {
    Write-Host "ERROR: openvpn.exe not found in common installation paths." -ForegroundColor Red
    Write-Host "Please download and install the OpenVPN community GUI/CLI from: https://openvpn.net/community-downloads/" -ForegroundColor Yellow
    Exit 1
}

if (-not (Test-Path $PassFile)) {
    Write-Host "ERROR: pass.txt not found at $PassFile" -ForegroundColor Red
    Exit 1
}

if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

Write-Host "Cleaning up old connections..." -ForegroundColor Cyan
Stop-Process -Name "openvpn" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ovpnFiles = Get-ChildItem -Path $VpnDir -Filter "*.ovpn"

Write-Host "=========================================="
Write-Host "    FAST OVPN BENCHMARK - WINDOWS"
Write-Host "=========================================="
Write-Host "Found $($ovpnFiles.Count) configuration files in $VpnDir"
Write-Host "------------------------------------------"

"VPN_Name,Ping(ms),Download(Mbit/s)" | Out-File -FilePath $ResultsFile -Encoding UTF8

foreach ($file in $ovpnFiles) {
    Write-Host "Testing: $($file.Name) ... " -NoNewline

    $CurrentLog = Join-Path $LogsDir "$($file.Name).runtime.log"
    if (Test-Path $CurrentLog) { Remove-Item $CurrentLog -Force -ErrorAction SilentlyContinue }

    $ovpnArgs = @("--config", "`"$($file.FullName)`"", "--log", "`"$CurrentLog`"", "--auth-user-pass", "`"$PassFile`"")
    $null = Start-Process -FilePath $OpenVpnExe -ArgumentList $ovpnArgs -WorkingDirectory $VpnDir -WindowStyle Hidden -PassThru

    $connected = $false
    for ($i = 0; $i -lt ($Timeout * 2); $i++) {
        if (Test-Path $CurrentLog) {
            try {
                $fs = [System.IO.File]::Open($CurrentLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $logContent = $sr.ReadToEnd()
                $sr.Dispose()
                $fs.Dispose()

                if ($logContent -match "CONNECTED,SUCCESS" -or $logContent -match "Initialization Sequence Completed" -or $logContent -match "Data Channel: cipher") {
                    $connected = $true
                    break
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 500
    }

    if ($connected) {
        Start-Sleep -Seconds 5

        $pingMs = 999
        $pingOut = ping.exe -n 1 -w 2000 8.8.8.8
        if ($pingOut -match 'time[=<](\d+)ms') { $pingMs = $Matches[1] }

        $speedMbps = 0
        try {
            $speedStr = & curl.exe -o NUL -s -w "%{speed_download}" --max-time 5 "http://speed.cloudflare.com/__down?bytes=$TestFileSize"
            if (![string]::IsNullOrWhiteSpace($speedStr)) {
                $speedStr = $speedStr -replace ',', '.'
                $speedBps = [double]$speedStr
                if ($speedBps -gt 0) { $speedMbps = [math]::Round(($speedBps * 8 / 1000000), 2) }
            }
        } catch {}

        Write-Host "UP ($speedMbps Mbps | $pingMs ms)" -ForegroundColor Green
        "$($file.Name),$pingMs,$speedMbps" | Out-File -FilePath $ResultsFile -Append -Encoding UTF8
    } else {
        Write-Host "FAILED or TIMEOUT" -ForegroundColor Red
        "$($file.Name),999,0" | Out-File -FilePath $ResultsFile -Append -Encoding UTF8
    }

    # Cleanly kill OpenVPN process and avoid zombies
    $openvpnProcs = Get-Process -Name "openvpn" -ErrorAction SilentlyContinue
    if ($openvpnProcs) {
        foreach ($proc in $openvpnProcs) {
            $proc.Kill()
            $proc.WaitForExit(3000)
        }
    }
    Start-Sleep -Seconds 3
}

Write-Host "=========================================="
Write-Host "TEST COMPLETED"
Write-Host "Results: $ResultsFile"
Write-Host "=========================================="