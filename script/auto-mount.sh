#!/bin/bash

NAS_HOST="tnbk.dove-komodo.ts.net"

# 1. Silently check if the NAS is reachable over SMB (Port 445)
# If it is offline or Tailscale is disconnected, exit immediately without showing popups
if ! nc -z -w 2 "$NAS_HOST" 445 > /dev/null 2>&1; then
    exit 0
fi

# 2. Define shares
SHARES=(
    "temp;smb://$NAS_HOST/temp"
    "Media;smb://$NAS_HOST/Media"
    "ZionLabs;smb://$NAS_HOST/ZionLabs"
    "KanokganDrive;smb://$NAS_HOST/KanokganDrive"
    "JongdeeDrive;smb://$NAS_HOST/JongdeeDrive"
    "OrawanDrive;smb://$NAS_HOST/OrawanDrive"
    "ChurinDrive;smb://$NAS_HOST/ChurinDrive"
)

# 3. Mount each share securely
for ITEM in "${SHARES[@]}"; do
    SHARE_NAME="${ITEM%%;*}"
    NAS_URL="${ITEM##*;}"
    
    # Check if this specific volume folder exists
    if [ ! -d "/Volumes/$SHARE_NAME" ]; then
        # perl alarm is a 10 s timeout (macOS has no `timeout`); it guards against a stalled
        # SMB session hanging if the link drops mid-mount.
        # try/on error keeps a failed mount from ever surfacing a Finder alert dialog
        perl -e 'alarm shift; exec @ARGV' 10 osascript -e "try
            tell application \"Finder\" to mount volume \"$NAS_URL\"
        end try" > /dev/null 2>&1
        # Wait 2 seconds before mounting the next one to prevent Finder race conditions
        sleep 2
    fi
done
