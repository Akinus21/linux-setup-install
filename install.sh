#!/usr/bin/env bash
set -e

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

log(){ echo -e "${BLUE}➜${RESET} $1"; }
ok(){ echo -e "${GREEN}✔${RESET} $1"; }
warn(){ echo -e "${YELLOW}!${RESET} $1"; }
err(){ echo -e "${RED}✘${RESET} $1"; }

########################################
# Detect package manager
########################################

detect_pm(){

if command -v rpm-ostree &>/dev/null; then
    PM="atomic"
elif command -v apt &>/dev/null; then
    PM="apt"
elif command -v dnf &>/dev/null; then
    PM="dnf"
elif command -v pacman &>/dev/null; then
    PM="pacman"
else
    PM="unknown"
fi

}

########################################
# Install package
########################################

install_pkg(){

pkg="$1"

case "$PM" in

apt) sudo apt update && sudo apt install -y "$pkg" ;;
dnf) sudo dnf install -y "$pkg" ;;
pacman) sudo pacman -S --noconfirm "$pkg" ;;

atomic)

log "Atomic distro detected"

if ! command -v distrobox &>/dev/null; then

    if ! command -v flatpak &>/dev/null; then
        warn "flatpak required. install manually."
        exit 1
    fi

    flatpak install -y flathub io.github.dvlv.boxbuddyrs
fi

distrobox enter cli -- sudo dnf install -y "$pkg" || true

;;

*) err "Unsupported distro"; exit 1 ;;

esac

}

########################################
# Ensure git
########################################

ensure_git(){

if ! command -v git &>/dev/null; then
    detect_pm
    install_pkg git
fi

}

########################################
# Ensure GitHub CLI
########################################

ensure_gh(){

if ! command -v gh &>/dev/null; then
    detect_pm
    install_pkg gh
fi

}

########################################
# GitHub authentication
########################################

ensure_gh_auth(){

if ! gh auth status &>/dev/null; then
    log "Authenticating GitHub"
    gh auth login
fi

}

########################################
# Configure git identity
########################################

ensure_git_identity(){

NAME=$(git config --global user.name || true)
EMAIL=$(git config --global user.email || true)

if [[ -z "$NAME" ]]; then
    read -p "Git user.name: " NAME
    git config --global user.name "$NAME"
fi

if [[ -z "$EMAIL" ]]; then
    read -p "Git user.email: " EMAIL
    git config --global user.email "$EMAIL"
fi

}

########################################
# Setup SSH authentication
########################################

setup_ssh(){

log "Checking GitHub SSH access"

if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    ok "GitHub SSH already configured"
    return
fi

KEY="$HOME/.ssh/id_ed25519"

if [[ ! -f "$KEY" ]]; then

    log "Generating SSH key"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    ssh-keygen -t ed25519 -N "" -f "$KEY"

fi

log "Uploading SSH key to GitHub"

gh ssh-key add "$KEY.pub" --title "$(hostname)"

log "Testing SSH authentication"

ssh -T git@github.com || true

ok "SSH authentication configured"

}

########################################
# Configure git to use gh credentials
########################################

setup_git_auth(){

gh auth setup-git

}

########################################
# Clone repo via SSH
########################################

clone_repo(){

USER=$(gh api user --jq .login)

REPO="$USER/linux-setup"

if [ -d "$INSTALL_DIR" ]; then
    log "Updating existing install"
    git -C "$INSTALL_DIR" pull
    return
fi

log "Cloning repo via SSH"

git clone "git@github.com:$REPO.git" "$INSTALL_DIR"

}

########################################
# Install CLI
########################################

install_cli(){

cp "$INSTALL_DIR/linux-setup.sh" "$BIN_DIR/linux-setup"
chmod +x "$BIN_DIR/linux-setup"

}

########################################
# Ensure PATH
########################################

ensure_path(){

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

}

########################################
# MAIN
########################################

log "Installing linux-setup"

ensure_git
ensure_gh
ensure_gh_auth
ensure_git_identity
setup_ssh
setup_git_auth
clone_repo
install_cli
ensure_path

ok "linux-setup installed"