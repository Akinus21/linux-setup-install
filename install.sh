#!/usr/bin/env bash
set -e

REPO="YOURNAME/linux-setup"
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
# DETECT PACKAGE MANAGER
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
elif command -v zypper &>/dev/null; then
    PM="zypper"
else
    PM="unknown"
fi

}

########################################
# INSTALL PACKAGE
########################################

install_pkg(){

pkg="$1"

case "$PM" in

apt)
sudo apt update
sudo apt install -y "$pkg"
;;

dnf)
sudo dnf install -y "$pkg"
;;

pacman)
sudo pacman -S --noconfirm "$pkg"
;;

zypper)
sudo zypper install -y "$pkg"
;;

atomic)

warn "Atomic distro detected"

ensure_distrobox

distrobox enter cli -- sudo dnf install -y "$pkg" || \
distrobox enter cli -- sudo apt install -y "$pkg" || \
distrobox enter cli -- sudo pacman -S --noconfirm "$pkg"

;;

*)

err "Unsupported distro. Install $pkg manually."
exit 1

;;

esac

}

########################################
# ENSURE FLATPAK
########################################

ensure_flatpak(){

if command -v flatpak &>/dev/null; then
    return
fi

log "Installing flatpak"

detect_pm
install_pkg flatpak

}

########################################
# ENSURE DISTROBOX
########################################

ensure_distrobox(){

if command -v distrobox &>/dev/null; then
    return
fi

ensure_flatpak

log "Installing distrobox"

flatpak install -y flathub io.github.dvlv.boxbuddyrs || true

if ! command -v distrobox &>/dev/null; then
    warn "Installing distrobox via package manager"
    detect_pm
    install_pkg distrobox
fi

}

########################################
# ENSURE GIT
########################################

ensure_git(){

if command -v git &>/dev/null; then
    return
fi

log "Installing git"

detect_pm
install_pkg git

}

########################################
# ENSURE GITHUB CLI
########################################

ensure_gh(){

if command -v gh &>/dev/null; then
    return
fi

log "Installing GitHub CLI"

detect_pm
install_pkg gh

}

########################################
# AUTHENTICATE GITHUB
########################################

ensure_auth(){

if gh auth status &>/dev/null; then
    ok "GitHub already authenticated"
    return
fi

log "GitHub authentication required"
gh auth login

}

########################################
# CLONE PRIVATE REPO
########################################

clone_repo(){

if [ -d "$INSTALL_DIR" ]; then
    log "Updating existing install"
    cd "$INSTALL_DIR"
    git pull
    return
fi

log "Cloning private repo"

gh repo clone "$REPO" "$INSTALL_DIR"

}

########################################
# INSTALL CLI
########################################

install_cli(){

cp "$INSTALL_DIR/linux-setup" "$BIN_DIR/linux-setup"
chmod +x "$BIN_DIR/linux-setup"

}

########################################
# ENSURE PATH
########################################

ensure_path(){

if ! echo "$PATH" | grep -q "$BIN_DIR"; then

    warn "$BIN_DIR not in PATH"

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

    warn "Restart shell after install"

fi

}

########################################
# MAIN
########################################

log "Installing linux-setup"

ensure_git
ensure_gh
ensure_auth
clone_repo
install_cli
ensure_path

ok "linux-setup installed"

echo
echo "Run:"
echo
echo "  linux-setup --sync"
echo "  linux-setup list"
echo