#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.linux-setup"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR" "$INSTALL_DIR"

# CONFIG: Change this to your actual distrobox name
CONTAINER_NAME="my-distrobox" 

log() { echo -e "\033[34m➜\033[0m $1"; }
ok()  { echo -e "\033[32m✔\033[0m $1"; }
err() { echo -e "\033[31m✘\033[0m $1"; exit 1; }

# 1. Clone Repo on the HOST first
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Updating repo on host..."
    git -C "$INSTALL_DIR" pull
else
    log "Cloning repo to host..."
    # Replace with your actual repo URL if needed
    git clone "https://github.com" "$INSTALL_DIR"
fi

# 2. Deploy the CLI to the HOST bin
log "Installing CLI to host bin..."
cp "$INSTALL_DIR/linux-setup.sh" "$BIN_DIR/linux-setup"
chmod +x "$BIN_DIR/linux-setup"

# 3. Handle Dependencies (Inside Distrobox)
if command -v rpm-ostree &>/dev/null; then
    log "Atomic distro detected. Ensuring dependencies in $CONTAINER_NAME..."
    
    # Check if container exists
    if ! distrobox list | grep -q "$CONTAINER_NAME"; then
        err "Distrobox '$CONTAINER_NAME' not found. Create it first or update the script with the correct name."
    fi

    # Install deps inside the box
    distrobox enter "$CONTAINER_NAME" -- sudo dnf install -y git gh jq gnupg2 realpath
    
    # Export the command so the host knows to run it INSIDE the box
    log "Exporting binary to host..."
    distrobox enter "$CONTAINER_NAME" -- distrobox-export --bin "$BIN_DIR/linux-setup" --export-path "$BIN_DIR"
    ok "Export complete."
else
    # Standard Distro Logic
    log "Standard distro detected. Installing dependencies locally..."
    # (Add your standard sudo apt/dnf/pacman install logic here)
fi

# 4. Final Verification
if [ -f "$BIN_DIR/linux-setup" ]; then
    ok "linux-setup is now at $BIN_DIR/linux-setup"
    log "Running doctor..."
    "$BIN_DIR/linux-setup" doctor || true
else
    err "Installation failed: Binary not found in $BIN_DIR"
fi

ok "Install finished!"
