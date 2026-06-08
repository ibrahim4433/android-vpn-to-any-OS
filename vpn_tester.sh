#!/bin/bash

# --- CONFIGURATION ---
# EDIT THIS PATH to point to where your .ovpn files are!
VPN_DIR="/home/user/Desktop/test/"
RESULTS_FILE="$VPN_DIR/vpn_benchmark_results.csv"
TEST_FILE_SIZE=5000000  # 5MB test file for speed (adjust if needed)
TIMEOUT=10              # Max seconds to wait for connection
# ---------------------

# 1. CLEANUP: Kill any old stuck OpenVPN connections silently
echo "Cleaning up old connections..."
sudo killall openvpn > /dev/null 2>&1
sudo rm -f /tmp/ovpn_test.pid
sleep 2

# 2. NAVIGATE
if [ -d "$VPN_DIR" ]; then
    cd "$VPN_DIR"
else
    echo "ERROR: Directory $VPN_DIR does not exist."
    read -p "Press Enter to exit..."
    exit 1
fi

shopt -s nullglob
files=(*.ovpn)

echo "=========================================="
echo "    FAST OVPN BENCHMARK - V3"
echo "=========================================="
echo "Found ${#files[@]} configuration files."
echo "Using Cloudflare for speed tests (No blocking)."
echo "------------------------------------------"

# CSV Header
echo "VPN_Name,Ping(ms),Download(Mbit/s)" > "$RESULTS_FILE"

for config in "${files[@]}"; do
    echo -n "Testing: $config ... "

    # Start OpenVPN silently
    sudo openvpn --config "$config" --daemon --log /tmp/ovpn.log --writepid /tmp/ovpn_test.pid

    # Wait for connection
    count=0
    connected=false
    while [ $count -lt $TIMEOUT ]; do
        if ip addr show tun0 > /dev/null 2>&1; then
            connected=true
            break
        fi
        sleep 1
        ((count++))
    done

    if [ "$connected" = true ]; then
        # Quick stabilize
        sleep 3
        
        # 1. TEST PING (Google DNS)
        # We take the average of 2 pings, timeout 2 seconds
        ping_res=$(ping -c 2 -W 2 8.8.8.8 | tail -1| awk -F '/' '{print $5}')
        
        # If ping fails, set to 999
        if [ -z "$ping_res" ]; then ping_res="999"; fi

        # 2. TEST DOWNLOAD SPEED (Curl)
        # Downloads 5MB from Cloudflare. Timeout 10s.
        # Output format is bytes per second.
        speed_bps=$(curl -o /dev/null -s -w "%{speed_download}" --max-time 10 "http://speed.cloudflare.com/__down?bytes=$TEST_FILE_SIZE")
        
        # Math: Convert Bytes/sec to Mbit/sec
        # (bps * 8) / 1,000,000
        if [ -z "$speed_bps" ] || [ "$speed_bps" == "0.000" ]; then
             speed_mbps="0"
        else
             speed_mbps=$(echo "scale=2; $speed_bps * 8 / 1000000" | bc -l)
        fi

        echo "UP ($speed_mbps Mbps | $ping_res ms)"
        echo "$config,$ping_res,$speed_mbps" >> "$RESULTS_FILE"

    else
        echo "FAILED"
        echo "$config,TIMEOUT,0" >> "$RESULTS_FILE"
    fi

    # CLEANUP IMMEDIATELY
    if [ -f /tmp/ovpn_test.pid ]; then
        sudo kill $(cat /tmp/ovpn_test.pid) > /dev/null 2>&1
        sudo rm -f /tmp/ovpn_test.pid
    fi
    sudo killall openvpn > /dev/null 2>&1
    
    sleep 1
done

echo "=========================================="
echo "TEST COMPLETED."
echo "=========================================="
echo ""
echo "TOP 3 FASTEST (Download):"
# Sort by 3rd column (Download), numeric, reverse
tail -n +2 "$RESULTS_FILE" | sort -t, -k3 -nr | head -n 3 | awk -F, '{printf "%-25s %s Mbit/s\n", $1, $3}'
echo ""
echo "TOP 3 LOWEST LATENCY (Ping):"
# Sort by 2nd column (Ping), numeric
tail -n +2 "$RESULTS_FILE" | grep -v "TIMEOUT" | grep -v ",0," | sort -t, -k2 -n | head -n 3 | awk -F, '{printf "%-25s %s ms\n", $1, $2}'
echo ""
read -p "Press Enter to exit..."