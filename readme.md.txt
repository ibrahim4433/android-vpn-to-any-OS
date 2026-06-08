Step 0: Move the test folder (that contains the .ovpn files) to the desktop 

Step 1: Create the script

Open your terminal and create a new script file:

nano bulk_vpn_import.sh

Step 2: Paste the code

Copy and paste the following code into the file.

-------------------------------------------------

#!/bin/bash

# Configuration Variables
VPN_DIR="/home/user/Desktop/test"
VPN_USER="govpn_android_08b5b211caef7691_RedmiNote7"
VPN_PASS="70fec39e48197bb77d"

# Loop through all .ovpn files in the directory
for file in "$VPN_DIR"/*.ovpn; do
    if [ -f "$file" ]; then
        echo "Processing: $file"
        
        # 1. Import the configuration
        # We capture the output to get the connection name/UUID created by NetworkManager
        OUTPUT=$(nmcli connection import type openvpn file "$file")
        
        # Extract the UUID of the new connection from the output string
        # Format is usually: Connection 'Name' (UUID) successfully added.
        UUID=$(echo "$OUTPUT" | grep -oP '(?<=\().*(?=\))')
        
        if [ -n "$UUID" ]; then
            echo "Imported with UUID: $UUID"
            
            # 2. Set the Username
            nmcli connection modify "$UUID" +vpn.data username="$VPN_USER"
            
            # 3. Set the Password
            # We add the password to the secrets
            nmcli connection modify "$UUID" +vpn.secrets password="$VPN_PASS"
            
            # 4. CRITICAL: Set the flag to SAVE the password (0 = save, 1 = ask)
            # Without this, it will prompt you every time you connect.
            nmcli connection modify "$UUID" +vpn.data password-flags=0
            
            echo "Credentials updated successfully."
        else
            echo "Failed to import $file"
        fi
    fi
done

echo "Batch processing complete."

------------------------------------------------------------------------------------

Step 3: Run the script

    Save the file in nano by pressing Ctrl+O, then Enter, then Ctrl+X.

    Make the script executable:

chmod +x bulk_vpn_import.sh

Run it:

    ./bulk_vpn_import.sh

Step 4: Verify

    Click your Network Manager icon in the Xfce taskbar.

    You should see a long list of VPN connections.

    Click one to connect. It should connect immediately without asking for a password.

Troubleshooting

If the script runs but you are still asked for a password when connecting, it is likely a permissions issue with the "Secret Flag." You can force the fix on all connections with this single command:
Bash

nmcli -f uuid,type connection show | grep vpn | awk '{print $1}' | xargs -I % nmcli connection modify % +vpn.data password-flags=0

How to delete them all (If something goes wrong)

If you made a mistake and want to clear all these VPNs to start over, run this command:
Bash

nmcli -f uuid,type connection show | grep vpn | awk '{print $1}' | xargs nmcli connection delete