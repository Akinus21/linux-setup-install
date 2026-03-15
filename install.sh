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
# LOGGING (Cross-Distro)
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
err(){ echo -e "${RED}✘${RESET} $1"; log_sys "err" "$1"; }

trap 'handle_error' ERR
handle_error() {
    err "Installation failed at line $LINENO"
    echo -e "\n${BOLD}Check logs:${NC}"
    [[ "$LOG_BACKEND" == "journald" ]] && echo "  journalctl -t $LOG_TAG -xe" || echo "  cat $LOG_FILE"
    exit 1
}

########################################
# HELPERS
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
        *) err "Unsupported distro"; exit 1 ;;
    esac
}

ensure_git(){ [[ ! -x $(command -v git) ]] && detect_pm && install_pkg git || true; }
ensure_gh(){ [[ ! -x $(command -v gh) ]] && detect_pm && install_pkg gh || true; }

########################################
# GIT SYNC LOGIC
########################################
clone_or_sync_repo(){
    USER=$(gh api user --jq .login)
    REPO_URL="git@github.com:$USER/linux-setup.git"

    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Syncing existing installation..."
        cd "$INSTALL_DIR"
        git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
        
        if ! git diff --quiet || ! git diff --cached --quiet; then
            log "Committing local changes..."
            git add -A && git commit -m "Install-sync: $(date '+%F')"
        fi

        log "Fetching from GitHub..."
        git fetch origin main || { err "Fetch failed"; return 1; }

        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "none")
        [[ "$REMOTE" == "none" ]] && { git push -u origin main; return; }

        BASE=$(git merge-base HEAD origin/main)

        if [[ "$LOCAL" == "$REMOTE" ]]; then
            ok "Up to date"
        elif [[ "$LOCAL" == "$BASE" ]]; then
            git pull --no-rebase origin main
        elif [[ "$REMOTE" == "$BASE" ]]; then
            git push origin main
        else
            warn "Diverged branch detected!"
            read -p "Keep [l]ocal or use [r]emote? " choice
            [[ "$choice" =~ ^[rR]$ ]] && git reset --hard origin/main || git push --force-with-lease origin main
        fi
    else
        log "Cloning repository..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
}

########################################
# MAIN
########################################
detect_logging
log "Starting linux-setup installation"

ensure_git
ensure_gh

if ! gh auth status &>/dev/null; then
    log "Authenticating GitHub CLI"
    gh auth login -h github.com -p ssh -w
fi

[[ -z "$(git config --global user.name)" ]] && read -p "Git Name: " GN && git config --global user.name "$GN"
[[ -z "$(git config --global user.email)" ]] && read -p "Git Email: " GE && git config --global user.email "$GE"

# SSH Setup
USER=$(gh api user --jq .login)
REPO="$USER/linux-setup"
if ! git ls-remote "git@github.com:$REPO.git" &>/dev/null; then
    log "Configuring SSH access"
    KEY="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    [[ ! -f "$KEY" ]] && ssh-keygen -t ed25519 -N "" -f "$KEY"
    gh ssh-key add "$KEY.pub" --title "$(hostname)-setup" || true
fi

gh auth setup-git >/dev/null 2>&1 || true

clone_or_sync_repo
ok "Repository synced"

# Install CLI
if [[ -f "$INSTALL_DIR/linux-setup.sh" ]]; then
    cp "$INSTALL_DIR/linux-setup.sh" "$BIN_DIR/linux-setup"
    chmod +x "$BIN_DIR/linux-setup"
    ok "CLI installed to $BIN_DIR"
else
    err "linux-setup.sh missing in repo"
    exit 1
fi

# Ensure Path
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    RC="$HOME/.bashrc"; [[ "$SHELL" == */zsh ]] && RC="$HOME/.zshrc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$RC"
    warn "Added to $RC. Restart shell after finish."
fi

log "Running post-install doctor..."
# Using full path in case PATH isn't refreshed yet
"$BIN_DIR/linux-setup" list || true

ok "Installation complete!"
