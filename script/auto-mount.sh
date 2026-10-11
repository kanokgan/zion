#!/bin/bash

NAS_HOST="tnbk.dove-komodo.ts.net"

# 1. Silently check if the NAS is reachable over SMB (Port 445)
# If it is offline or Tailscale is disconnected, exit immediately without showing popups
if ! nc -z -w 2 "$NAS_HOST" 445 > /dev/null 2>&1; then
    exit 0
fi

# 2. Define shares
SHARES=(
    "Media;smb://$NAS_HOST/Media"
    "temp;smb://$NAS_HOST/temp"
    "Projects;smb://$NAS_HOST/Projects"
    "ZionLabs;smb://$NAS_HOST/ZionLabs"
    # Personal drives: replace the placeholders with the real share names
    "Member1Drive;smb://$NAS_HOST/Member1Drive"
    "Member2Drive;smb://$NAS_HOST/Member2Drive"
    "Member3Drive;smb://$NAS_HOST/Member3Drive"
    "Member4Drive;smb://$NAS_HOST/Member4Drive"
)

# 3. Mount each share securely
for ITEM in "${SHARES[@]}"; do
    SHARE_NAME="${ITEM%%;*}"
    NAS_URL="${ITEM##*;}"
    
    # Check if this specific volume folder exists
    if [ ! -d "/Volumes/$SHARE_NAME" ]; then
        # timeout guards against a stalled SMB session hanging/prompting if the link drops mid-mount
        # try/on error keeps a failed mount from ever surfacing a Finder alert dialog
        timeout 10 osascript -e "try
            tell application \"Finder\" to mount volume \"$NAS_URL\"
        end try" > /dev/null 2>&1
        # Wait 2 seconds before mounting the next one to prevent Finder race conditions
        sleep 2
    fi
done
