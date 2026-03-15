#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.linux-setup"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

########################################
# COLORS
########################################
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"
BOLD="\033[1m"

log(){ echo -e "${BLUE}➜${RESET} $1"; }
ok(){ echo -e "${GREEN}✔${RESET} $1"; }
warn(){ echo -e "${YELLOW}!${RESET} $1"; }
err(){ echo -e "${RED}✘${RESET} $1"; }

########################################
# Detect package manager
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
        atomic)
            log "Atomic distro detected"
            if ! command -v distrobox &>/dev/null; then
                warn "distrobox required for atomic installs."
                exit 1
            fi
            distrobox enter cli -- sudo dnf install -y "$pkg" || true
            ;;
        *) err "Unsupported distro"; exit 1 ;;
    esac
}

ensure_git(){ [[ ! -x $(command -v git) ]] && detect_pm && install_pkg git || true; }
ensure_gh(){ [[ ! -x $(command -v gh) ]] && detect_pm && install_pkg gh || true; }

ensure_gh_auth(){
    if ! gh auth status &>/dev/null; then
        log "Authenticating GitHub"
        gh auth login -h github.com -p ssh -w
    fi
}

ensure_git_identity(){
    [[ -z "$(git config --global user.name)" ]] && read -p "Git user.name: " NAME && git config --global user.name "$NAME"
    [[ -z "$(git config --global user.email)" ]] && read -p "Git user.email: " EMAIL && git config --global user.email "$EMAIL"
}

setup_ssh(){
    USER=$(gh api user --jq .login)
    REPO="$USER/linux-setup"
    log "Checking GitHub SSH access"

    if git ls-remote "git@github.com:$REPO.git" &>/dev/null; then
        ok "GitHub SSH already configured"
        return
    fi

    log "SSH not configured — setting it up"
    KEY="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

    if [[ ! -f "$KEY" ]]; then
        log "Generating SSH key"
        ssh-keygen -t ed25519 -N "" -f "$KEY"
    fi

    log "Uploading SSH key to GitHub"
    gh ssh-key add "$KEY.pub" --title "$(hostname)-setup" || true
    ok "SSH authentication configured"
}

########################################
# SYNC / CLONE LOGIC (Interactive)
########################################
clone_or_sync_repo(){
    USER=$(gh api user --jq .login)
    REPO_URL="git@github.com:$USER/linux-setup.git"

    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Existing installation found. Syncing..."
        cd "$INSTALL_DIR"
        
        git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
        
        if ! git diff --quiet || ! git diff --cached --quiet; then
            warn "Local changes detected in $INSTALL_DIR. Committing..."
            git add -A
            git commit -m "Auto-commit before update: $(date '+%Y-%m-%d')"
        fi

        log "Fetching latest from GitHub..."
        git fetch origin main || { err "Fetch failed"; exit 1; }

        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "none")
        
        if [[ "$REMOTE" == "none" ]]; then
            log "Remote branch not found. Pushing local to GitHub..."
            git push -u origin main
            return
        fi

        BASE=$(git merge-base HEAD origin/main)

        if [[ "$LOCAL" == "$REMOTE" ]]; then
            ok "Installation is already up to date."
        elif [[ "$LOCAL" == "$BASE" ]]; then
            log "Updating local files from GitHub..."
            git pull --no-rebase origin main
        elif [[ "$REMOTE" == "$BASE" ]]; then
            log "Local is ahead. Pushing to GitHub..."
            git push origin main
        else
            warn "Local and Remote have diverged."
            echo -e "${BOLD}Conflict Resolution Required:${RESET}"
            echo -e "  [l] Keep ${GREEN}LOCAL${RESET} (Force push your version to GitHub)"
            echo -e "  [r] Use ${BLUE}REMOTE${RESET} (Reset local to match GitHub)"
            read -r -p "Selection (l/r): " choice
            case "$choice" in
                r|R) log "Resetting to remote..."; git reset --hard origin/main ;;
                l|L) log "Force pushing local..."; git push --force-with-lease origin main ;;
                *) err "Invalid choice. Aborting sync."; exit 1 ;;
            esac
        fi
    else
        log "Cloning linux-setup repo..."
        git clone "$REPO_URL" "$INSTALL_DIR" || {
            err "Clone failed. Verify '$USER/linux-setup' exists on GitHub."
            exit 1
        }
    fi
}

install_cli(){
    if [[ ! -f "$INSTALL_DIR/linux-setup.sh" ]]; then
        err "linux-setup.sh not found in $INSTALL_DIR"
        exit 1
    fi
    cp "$INSTALL_DIR/linux-setup.sh" "$BIN_DIR/linux-setup"
    chmod +x "$BIN_DIR/linux-setup"
    ok "CLI installed to $BIN_DIR"
}

ensure_path(){
    if ! echo "$PATH" | grep -q "$BIN_DIR"; then
        warn "$BIN_DIR not in PATH"
        SHELL_RC="$HOME/.bashrc"
        [[ "$SHELL" == */zsh ]] && SHELL_RC="$HOME/.zshrc"
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
        ok "Added $BIN_DIR to $SHELL_RC"
        warn "Restart shell or run: source $SHELL_RC"
    fi
}

########################################
# MAIN
########################################
log "Installing/Updating linux-setup"

ensure_git
ensure_gh
ensure_gh_auth
ensure_git_identity
setup_ssh
gh auth setup-git >/dev/null 2>&1 || true

clone_or_sync_repo
install_cli
ensure_path

# Execute doctor immediately using the local path to ensure it runs even if PATH isn't updated yet
log "Running post-install system check..."
"$BIN_DIR/linux-setup" sync || true
"$BIN_DIR/linux-setup" list || true

ok "Installation complete!"
