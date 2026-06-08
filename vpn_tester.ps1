# --- CONFIGURATION ---
# The path where your .ovpn files and pass.txt are located
$VpnDir = "D:\test"
$ResultsFile = "$VpnDir\vpn_benchmark_results.csv"
$TestFileSize = 25000000 # 25MB file (Cut off at 5 seconds)
$Timeout = 15            # Increased timeout slightly for Windows TAP adapter initialization
$OpenVpnExe = "C:\Program Files\OpenVPN\bin\openvpn.exe"
# ---------------------

# 1. Enforce Administrator Privileges (Auto-Elevate)
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to run OpenVPN..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"D:\test\vpn_tester.ps1`"" -Verb RunAs
    Exit
}

# 2. NAVIGATE & CHECK
if (-not (Test-Path $VpnDir)) {
    Write-Host "ERROR: Directory $VpnDir does not exist." -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    Exit
}

if (-not (Test-Path $OpenVpnExe)) {
    Write-Host "ERROR: OpenVPN not found. Please verify installation." -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    Exit
}

Set-Location $VpnDir

# 3. CLEANUP: Kill any old stuck OpenVPN connections
Write-Host "Cleaning up old connections..." -ForegroundColor Cyan
Stop-Process -Name "openvpn" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ovpnFiles = Get-ChildItem -Path $VpnDir -Filter "*.ovpn"

Write-Host "=========================================="
Write-Host "    FAST OVPN BENCHMARK - WINDOWS"
Write-Host "=========================================="
Write-Host "Found $($ovpnFiles.Count) configuration files."
Write-Host "Using Cloudflare for speed tests (No blocking)."
Write-Host "------------------------------------------"

# CSV Header
"VPN_Name,Ping(ms),Download(Mbit/s)" | Out-File -FilePath $ResultsFile -Encoding UTF8

foreach ($file in $ovpnFiles) {
    Write-Host "Testing: $($file.Name) ... " -NoNewline

    # Create a unique log file name for this specific test
    $CurrentLog = "$VpnDir\$($file.Name).log"
    if (Test-Path $CurrentLog) { Remove-Item $CurrentLog -Force -ErrorAction SilentlyContinue }

    # Start OpenVPN quietly in the background
    # ADDED: --auth-user-pass overrides the broken Linux paths (/home/user/...) hiding inside your .ovpn files!
    $ovpnArgs = @("--config", "`"$($file.FullName)`"", "--log", "`"$CurrentLog`"", "--auth-user-pass", "`"$VpnDir\pass.txt`"")
    $proc = Start-Process -FilePath $OpenVpnExe -ArgumentList $ovpnArgs -WorkingDirectory $VpnDir -WindowStyle Hidden -PassThru

    # Wait for connection by reading the log file using .NET (bypasses Windows file locks)
    $connected = $false
    
    # Loop runs twice per second
    for ($i = 0; $i -lt ($Timeout * 2); $i++) {
        if (Test-Path $CurrentLog) {
            try {
                # Safely open the file even if OpenVPN is currently writing to it, forcing UTF8 decoding
                $fs = [System.IO.File]::Open($CurrentLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $logContent = $sr.ReadToEnd()
                $sr.Dispose()
                $fs.Dispose()
                
                # ADDED: "Data Channel: cipher" to catch successful connections even when machine-readable-output hides standard logs
                if ($logContent -match "CONNECTED,SUCCESS" -or $logContent -match "Initialization Sequence Completed" -or $logContent -match "Data Channel: cipher") {
                    $connected = $true
                    break
                }
            } catch {
                # Ignore read errors if file is briefly inaccessible
            }
        }
        Start-Sleep -Milliseconds 500
    }

    if ($connected) {
        # Quick stabilize - INCREASED to 5 seconds to let Windows apply the routing tables
        Start-Sleep -Seconds 5 
        
        # 1. TEST PING (Google DNS) - Single fast ping
        $pingMs = 999
        $pingOut = ping.exe -n 1 -w 2000 8.8.8.8
        if ($pingOut -match 'time[=<](\d+)ms') {
            $pingMs = $Matches[1]
        }

        # 2. TEST DOWNLOAD SPEED using curl
        $speedMbps = 0
        try {
            # Max-time strictly set to 5s. Extremely fast average calculation.
            $speedStr = & curl.exe -o NUL -s -w "%{speed_download}" --max-time 5 "http://speed.cloudflare.com/__down?bytes=$TestFileSize"
            
            if (![string]::IsNullOrWhiteSpace($speedStr)) {
                $speedStr = $speedStr -replace ',', '.'
                $speedBps = [double]$speedStr
                if ($speedBps -gt 0) {
                    $speedMbps = [math]::Round(($speedBps * 8 / 1000000), 2)
                }
            }
        } catch {}

        Write-Host "UP ($speedMbps Mbps | $pingMs ms)" -ForegroundColor Green
        "$($file.Name),$pingMs,$speedMbps" | Out-File -FilePath $ResultsFile -Append -Encoding UTF8

    } else {
        Write-Host "FAILED or TIMEOUT" -ForegroundColor Red
        
        # ADDED: Print exactly why it failed to the screen so we can debug the root cause
        if (Test-Path $CurrentLog) {
            Write-Host "   -> OpenVPN Error Log:" -ForegroundColor DarkYellow
            Get-Content $CurrentLog -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { 
                Write-Host "      $_" -ForegroundColor DarkGray 
            }
        }
        
        "$($file.Name),999,0" | Out-File -FilePath $ResultsFile -Append -Encoding UTF8
    }

    # CLEANUP
    Stop-Process -Name "openvpn" -Force -ErrorAction SilentlyContinue
    
    # Wait 3 seconds for Windows networking adapter to reset routes before the next test
    Start-Sleep -Seconds 3
    
    # Clean up the temporary log ONLY if successful. Keep it if failed for manual review.
    if ($connected -and (Test-Path $CurrentLog)) { 
        Remove-Item $CurrentLog -Force -ErrorAction SilentlyContinue 
    }
}

Write-Host "=========================================="
Write-Host "TEST COMPLETED."
Write-Host "=========================================="

# Read the CSV and display TOP 3
if (Test-Path $ResultsFile) {
    $results = Import-Csv $ResultsFile
    $validResults = $results | Where-Object { $_.'Download(Mbit/s)' -ne '0' }

    if ($validResults) {
        Write-Host "`nTOP 3 FASTEST (Download):" -ForegroundColor Yellow
        $validResults | Sort-Object -Property @{Expression={[decimal]$_.'Download(Mbit/s)'}; Descending=$true} | Select-Object -First 3 | Format-Table -AutoSize

        Write-Host "`nTOP 3 LOWEST LATENCY (Ping):" -ForegroundColor Yellow
        $validResults | Sort-Object -Property @{Expression={[decimal]$_.'Ping(ms)'}; Descending=$false} | Select-Object -First 3 | Format-Table -AutoSize
    } else {
        Write-Host "`nNo successful connections found to display." -ForegroundColor Red
    }
}

Write-Host ""
Read-Host "Press Enter to exit..."