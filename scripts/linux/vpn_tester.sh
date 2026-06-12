#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NEWEST_OVPN_DIR=$(find "$REPO_ROOT/configs" -maxdepth 1 -type d -name "ovpn*" | sort -r | head -n 1)
if [ -z "$NEWEST_OVPN_DIR" ]; then
    NEWEST_OVPN_DIR="$REPO_ROOT/configs/ovpn"
fi

VPN_DIR="$NEWEST_OVPN_DIR"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs/openvpn}"
RESULTS_FILE="${RESULTS_FILE:-$REPO_ROOT/logs/vpn_benchmark_results_linux.csv}"
TEST_FILE_SIZE="${TEST_FILE_SIZE:-5000000}"
TIMEOUT="${TIMEOUT:-10}"

mkdir -p "$LOG_DIR" "$(dirname "$RESULTS_FILE")"

if [ ! -d "$VPN_DIR" ]; then
    echo "ERROR: VPN config directory does not exist: $VPN_DIR"
    exit 1
fi

missing_deps=()
for cmd in openvpn curl ping ip bc dos2unix; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_deps+=("$cmd")
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "Missing dependencies: ${missing_deps[*]}. Attempting to install..."
    # Map command names to Debian packages
    packages=()
    for cmd in "${missing_deps[@]}"; do
        case "$cmd" in
            openvpn) packages+=("openvpn") ;;
            curl) packages+=("curl") ;;
            ping) packages+=("iputils-ping") ;;
            ip) packages+=("iproute2") ;;
            bc) packages+=("bc") ;;
            dos2unix) packages+=("dos2unix") ;;
        esac
    done

    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"

    # Re-check
    missing_deps_again=()
    for cmd in "${missing_deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps_again+=("$cmd")
        fi
    done

    if [ ${#missing_deps_again[@]} -ne 0 ]; then
        echo "ERROR: Failed to install missing dependencies: ${missing_deps_again[*]}"
        exit 1
    fi
fi

# Run dos2unix on the ovpn configuration files before testing
if ls "$VPN_DIR"/*.ovpn 1> /dev/null 2>&1; then
    find "$VPN_DIR" -maxdepth 1 -name '*.ovpn' -exec dos2unix -q {} +
fi

echo "=========================================="
echo "    FAST OVPN BENCHMARK - LINUX"
echo "=========================================="
echo "Found $(find "$VPN_DIR" -maxdepth 1 -name '*.ovpn' | wc -l) configuration files in $VPN_DIR"
echo "------------------------------------------"

echo "VPN_Name,Ping(ms),Download(Mbit/s)" > "$RESULTS_FILE"

shopt -s nullglob
for config in "$VPN_DIR"/*.ovpn; do
    config_name="$(basename "$config")"
    log_file="$LOG_DIR/${config_name}.runtime.log"
    echo -n "Testing: $config_name ... "

    timeout_seconds=$((TIMEOUT + 6))

    # Run OpenVPN in the background
    sudo openvpn --config "$config" --connect-timeout "$TIMEOUT" --inactive 5 --ping-exit 5 --log "$log_file" &
    OPENVPN_PID=$!

    connected=false
    start_time=$(date +%s)

    # Wait for connection or timeout
    while [ $(( $(date +%s) - start_time )) -lt $timeout_seconds ]; do
        if grep -q "Initialization Sequence Completed" "$log_file" 2>/dev/null; then
            connected=true
            break
        fi
        sleep 0.5
    done

    if [ "$connected" = true ]; then
        ping_res=$(ping -c 2 -W 2 8.8.8.8 | tail -1 | awk -F '/' '{print $5}')
        [ -z "$ping_res" ] && ping_res="999"

        speed_bps=$(curl -o /dev/null -s -w "%{speed_download}" --max-time 10 "http://speed.cloudflare.com/__down?bytes=$TEST_FILE_SIZE")
        if [ -z "$speed_bps" ] || [ "$speed_bps" = "0.000" ]; then
            speed_mbps="0"
        else
            speed_mbps=$(echo "scale=2; $speed_bps * 8 / 1000000" | bc -l)
        fi

        echo "UP ($speed_mbps Mbps | $ping_res ms)"
        echo "$config_name,$ping_res,$speed_mbps" >> "$RESULTS_FILE"
    else
        echo "FAILED or TIMEOUT"
        echo "$config_name,TIMEOUT,0" >> "$RESULTS_FILE"
    fi

    # Cleanly kill OpenVPN process and its children gracefully
    sudo kill $OPENVPN_PID 2>/dev/null || true
    sleep 1
    sudo killall -9 openvpn 2>/dev/null || true

done

echo "=========================================="
echo "TEST COMPLETED"
echo "Results: $RESULTS_FILE"
echo "=========================================="