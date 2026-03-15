#!/usr/bin/env bash
set -euo pipefail
set -o errtrace

INSTALL_DIR="$HOME/.linux-setup"
BIN_DIR="$HOME/.local/bin"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$BIN_DIR" "$INSTALL_DIR"

########################################
# COLORS & UI
########################################
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"
BOLD="\033[1m"

########################################
# LOGGING
########################################
LOG_TAG="linux-setup-install"

detect_logging() {
    if command -v journalctl &>/dev/null; then LOG_BACKEND="journald"
    elif command -v logger &>/dev/null; then LOG_BACKEND="syslog"
    else LOG_BACKEND="file"; fi
}

log_sys() {
    local level="$1" msg="$2"
    case "$LOG_BACKEND" in
        journald) echo "$msg" | systemd-cat -t "$LOG_TAG" -p "$level" ;;
        syslog)   logger -t "$LOG_TAG" -p "user.$level" "$msg" ;;
        *)        echo "$(date '+%F %T') [$level] $msg" >> "$LOG_FILE" ;;
    esac
}

log(){ echo -e "${BLUE}➜${RESET} $1"; log_sys "info" "$1"; }
ok(){ echo -e "${GREEN}✔${RESET} $1"; log_sys "notice" "$1"; }
warn(){ echo -e "${YELLOW}!${RESET} $1"; log_sys "warning" "$1"; }
err(){ echo -e "${RED}✘${RESET} $1"; log_sys "err" "$1"; exit 1; }

trap 'err "Installation failed at line $LINENO. Check logs with: journalctl -t $LOG_TAG -xe"' ERR

########################################
# HELPERS & DEPS
########################################
detect_pm(){
    if command -v rpm-ostree &>/dev/null; then PM="atomic"
    elif command -v apt &>/dev/null; then PM="apt"
    elif command -v dnf &>/dev/null; then PM="dnf"
    elif command -v pacman &>/dev/null; then PM="pacman"
    else PM="unknown"; fi
}

install_pkg(){
    pkg="$1"
    case "$PM" in
        apt) sudo apt update && sudo apt install -y "$pkg" ;;
        dnf) sudo dnf install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        atomic) distrobox enter cli -- sudo dnf install -y "$pkg" || true ;;
        *) err "Unsupported distro" ;;
    esac
}

ensure_git(){ [[ ! -x $(command -v git) ]] && detect_pm && install_pkg git || true; }
ensure_gh(){ [[ ! -x $(command -v gh) ]] && detect_pm && install_pkg gh || true; }

########################################
# IDENTITY DETECTION (The Reverted Logic)
########################################
get_github_user() {
    # 1. Try Git Global Config
    local git_user=$(git config --global user.name || true)
    
    # 2. Try GH CLI as fallback
    if [[ -z "$git_user" ]] && command -v gh &>/dev/null && gh auth status &>/dev/null; then
        git_user=$(gh api user --jq .login 2>/dev/null || true)
    fi

    if [[ -z "$git_user" ]]; then
        read -p "Could not detect GitHub username. Please enter it: " git_user
        git config --global user.name "$git_user"
    fi
    echo "$git_user"
}

########################################
# SYNC LOGIC (Favoring Remote)
########################################
clone_or_sync_repo(){
    local user=$(get_github_user)
    local repo_url="git@github.com:$user/linux-setup.git"

    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Syncing existing installation for $user..."
        cd "$INSTALL_DIR"
        git remote set-url origin "$repo_url" 2>/dev/null || git remote add origin "$repo_url"
        log "Fetching latest from GitHub..."
        git fetch origin main || return 1
        log "Resetting local repo to match origin/main (favoring remote)..."
        git reset --hard origin/main
        ok "Local repo synchronized."
    else
        log "Cloning repository: $repo_url"
        git clone "$repo_url" "$INSTALL_DIR"
    fi
}

########################################
# MAIN
########################################
detect_logging
log "Starting linux-setup install/update"

ensure_git
ensure_gh

# Auth check
if ! gh auth status &>/dev/null; then
    log "Authenticating GitHub CLI"
    gh auth login -h github.com -p ssh -w
fi

# Ensure basic git identity
[[ -z "$(git config --global user.name)" ]] || [[ -z "$(git config --global user.email)" ]] && {
    read -p "Git Name: " GN; git config --global user.name "$GN"
    read -p "Git Email: " GE; git config --global user.email "$GE"
}

# SSH Setup
USER_LOGIN=$(get_github_user)
if ! git ls-remote "git@github.com:$USER_LOGIN/linux-setup.git" &>/dev/null; then
    log "Configuring SSH access"
    KEY="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    [[ ! -f "$KEY" ]] && ssh-keygen -t ed25519 -N "" -f "$KEY"
    gh ssh-key add "$KEY.pub" --title "$(hostname)-setup" || true
fi

gh auth setup-git >/dev/null 2>&1 || true

# Perform Sync
clone_or_sync_repo

# Deploy CLI
if [[ -f "$INSTALL_DIR/linux-setup.sh" ]]; then
    cp "$INSTALL_DIR/linux-setup.sh" "$BIN_DIR/linux-setup"
    chmod +x "$BIN_DIR/linux-setup"
    ok "CLI installed to $BIN_DIR"
else
    err "linux-setup.sh missing in repository"
fi

# Path Check
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    RC="$HOME/.bashrc"; [[ "$SHELL" == */zsh ]] && RC="$HOME/.zshrc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$RC"
    warn "Added $BIN_DIR to $RC. Please restart your terminal."
fi

# Final Check
log "Running post-install doctor..."
"$BIN_DIR/linux-setup" doctor || true

# Distrobox Export if needed
if [[ -f /run/.containerenv ]] || [[ -f /.dockerenv ]]; then
    if command -v distrobox-export &>/dev/null; then
        log "Container detected. Exporting binary to host..."
        distrobox-export --bin "$BIN_DIR/linux-setup" --export-path "$BIN_DIR"
        ok "Binary exported to host."
    fi
fi

ok "Installation complete!"
