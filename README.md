# Android VPN to Any OS

A small toolkit for testing many OpenVPN configuration files (`.ovpn`) and ranking them by latency and download speed on Linux or Windows.

## What this repository contains

- `configs/ovpn/` - OpenVPN configuration files to test.
- `scripts/linux/vpn_tester.sh` - Linux benchmark runner.
- `scripts/windows/vpn_tester.ps1` - Windows benchmark runner.
- `scripts/windows/run_vpn_tester.bat` - Windows launcher.
- `tools/fix.py` - Helper that updates/adds `auth-user-pass` in `.ovpn` files.
- `logs/openvpn/` - OpenVPN log files.
- `docs/legacy_notes.txt` - Old setup notes kept for reference.

## Requirements

### Linux
- OpenVPN
- `curl`, `ping`, `ip`, `bc`
- `sudo` access

### Windows
- OpenVPN installed at `C:\Program Files\OpenVPN\bin\openvpn.exe`
- PowerShell
- Run as Administrator (the script auto-prompts)

## Credentials file

Create `pass.txt` in the repository root with:

```text
username
password
```

Do not commit real credentials.

## Run benchmark

### Linux
```bash
bash scripts/linux/vpn_tester.sh
```

### Windows
```bat
scripts\windows\run_vpn_tester.bat
```

## Output

- Linux CSV: `logs/vpn_benchmark_results_linux.csv`
- Windows CSV: `logs/vpn_benchmark_results_windows.csv`
- Per-profile logs: `logs/openvpn/*.log`

## Optional: update auth-user-pass lines in all profiles

```bash
python tools/fix.py
```

You can override defaults:

```bash
python tools/fix.py --config-dir /path/to/ovpn --pass-path /path/to/pass.txt
```
