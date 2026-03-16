#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$HOME/.linux-setup"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR" "$INSTALL_DIR"
log(){ echo -e "\033[34m➜\033[0m $1"; }
ok(){ echo -e "\033[32m✔\033[0m $1"; }

get_github_user() {
    local user=$(git config --global user.name || true)
    [[ -z "$user" ]] && user=$(gh api user --jq .login 2>/dev/null || true)
    echo "$user"
}

clone_or_sync_repo(){
    local user=$(get_github_user)
    local repo_url="git@github.com:$user/linux-setup.git"
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR"
        git fetch origin main && git reset --hard origin/main
    else
        git clone "$repo_url" "$INSTALL_DIR"
    fi
}

log "Starting installation..."
clone_or_sync_repo
cp "$INSTALL_DIR/linux-setup.sh" "$BIN_DIR/linux-setup"
chmod +x "$BIN_DIR/linux-setup"

# Do NOT run distrobox-export here — it must be run from inside the container
# Only warn if on Atomic, remind user to run `linux-setup doctor` inside the container
if command -v rpm-ostree &>/dev/null; then
    log "Atomic host detected: remember to run 'linux-setup doctor' inside the Distrobox container to export the binary."
fi

ok "CLI installed."
"$BIN_DIR/linux-setup" doctor || true