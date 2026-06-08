#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VPN_DIR="${VPN_DIR:-$REPO_ROOT/configs/ovpn}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/logs/openvpn}"
RESULTS_FILE="${RESULTS_FILE:-$REPO_ROOT/logs/vpn_benchmark_results_linux.csv}"
TEST_FILE_SIZE="${TEST_FILE_SIZE:-5000000}"
TIMEOUT="${TIMEOUT:-10}"

mkdir -p "$LOG_DIR" "$(dirname "$RESULTS_FILE")"

if [ ! -d "$VPN_DIR" ]; then
    echo "ERROR: VPN config directory does not exist: $VPN_DIR"
    exit 1
fi

if ! command -v openvpn >/dev/null 2>&1; then
    echo "ERROR: openvpn command not found."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v ping >/dev/null 2>&1 || ! command -v ip >/dev/null 2>&1 || ! command -v bc >/dev/null 2>&1; then
    echo "ERROR: Missing required commands (curl, ping, ip, bc)."
    exit 1
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
    openvpn_status=0
    if ! sudo timeout "${timeout_seconds}s" openvpn --config "$config" --connect-timeout "$TIMEOUT" --inactive 5 --ping-exit 5 --log "$log_file"; then
        openvpn_status=$?
    fi

    if [ "$openvpn_status" -eq 0 ] || [ "$openvpn_status" -eq 124 ]; then
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
        echo "FAILED"
        echo "$config_name,TIMEOUT,0" >> "$RESULTS_FILE"
    fi
done

echo "=========================================="
echo "TEST COMPLETED"
echo "Results: $RESULTS_FILE"
echo "=========================================="