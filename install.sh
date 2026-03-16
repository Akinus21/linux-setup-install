#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$HOME/.linux-setup"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR" "$INSTALL_DIR"
log(){ echo -e "\033[34m➜\033[0m $1"; }
ok(){ echo -e "\033[32m✔\033[0m $1"; }

# Ensure gh is installed (use brew on macOS if needed)
if ! command -v gh &>/dev/null; then
    if command -v brew &>/dev/null; then
        log "Installing GitHub CLI via Homebrew..."
        brew install gh || { err "Failed to install gh via brew."; exit 1; }
        ok "GitHub CLI installed."
    else
        err "GitHub CLI (gh) not found and brew not available. Please install gh manually."
        exit 1
    fi
fi

# Authenticate GitHub CLI (non-interactive if GITHUB_TOKEN is set)
if ! gh auth status &>/dev/null; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log "Authenticating GitHub CLI using GITHUB_TOKEN..."
        echo "$GITHUB_TOKEN" | gh auth login --with-token || {
            err "GitHub auth failed. Please verify GITHUB_TOKEN is valid."
            exit 1
        }
    else
        gh auth login || {
            err "GitHub auth failed. Please run 'gh auth login' manually."
            exit 1
        }
    fi
    # Configure git credential helper [1]
    gh auth setup-git || true
fi

get_github_user() {
    local user=$(git config --global user.name || true)
    [[ -z "$user" ]] && user=$(gh api user --jq .login 2>/dev/null || true)
    echo "$user"
}

clone_or_sync_repo() {
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

# Ensure container exists and is properly configured (Atomic only)
if command -v rpm-ostree &>/dev/null; then
    log "Atomic host detected: ensuring Distrobox container..."
    if ! podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "linux-setup"; then
        log "Creating 'linux-setup' container with host GitHub auth..."
        distrobox create \
            --name "linux-setup" \
            --image fedora:latest \
            --volume "$HOME/.config/gh:$HOME/.config/gh:ro" \
            --pull
        sleep 3
        if ! podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "linux-setup"; then
            err "Container 'linux-setup' failed to appear. Check 'podman ps -a'."
            exit 1
        fi
        log "Installing dependencies in container..."
        distrobox enter "linux-setup" -- sudo dnf install -y git gh jq gnupg2 coreutils
        distrobox enter "linux-setup" -- gh auth git-credential > /dev/null 2>&1 || true
        ok "Container created and provisioned."
    else
        log "Container 'linux-setup' already exists."
    fi
else
    log "Non-Atomic host: no container required."
fi

ok "CLI installed."
"$BIN_DIR/linux-setup" doctor