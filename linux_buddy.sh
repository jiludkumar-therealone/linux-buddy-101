#!/usr/bin/env bash

# --- Configuration & Setup ---
APP_NAME="Linux Buddy"
VERSION="0.2.0-multi"
ALIAS_FILE="$HOME/.linux_buddy_aliases"
LOG_FILE="/tmp/linux_buddy.log"

# --- Distro Detection Logic ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi
}

# Generic Package Manager Wrapper
# Usage: run_pkg_cmd "update" or "upgrade" or "install <pkg>"
run_pkg_cmd() {
    local action=$1
    case $DISTRO in
        ubuntu|debian|kali|pop|linuxmint)
            case $action in
                update)  sudo apt-get update ;;
                upgrade) sudo apt-get dist-upgrade -y ;;
                clean)   sudo apt-get autoremove -y && sudo apt-get clean ;;
                install) sudo apt-get install -y "${@:2}" ;;
            esac
            ;;
        fedora|rhel|centos)
            case $action in
                update)  sudo dnf check-update ;;
                upgrade) sudo dnf upgrade -y ;;
                clean)   sudo dnf autoremove -y ;;
                install) sudo dnf install -y "${@:2}" ;;
            esac
            ;;
        arch|manjaro|endeavouros)
            case $action in
                update)  sudo pacman -Sy ;;
                upgrade) sudo pacman -Syu --noconfirm ;;
                clean)   sudo pacman -Sc --noconfirm ;;
                install) sudo pacman -S --noconfirm "${@:2}" ;;
            esac
            ;;
        opensuse*)
            case $action in
                update)  sudo zypper refresh ;;
                upgrade) sudo zypper update -y ;;
                clean)   sudo zypper clean ;;
                install) sudo zypper install -y "${@:2}" ;;
            esac
            ;;
        *)
            msg_box "Unsupported Distro" "Sorry, I don't know how to handle $DISTRO yet!"
            return 1
            ;;
    esac
}

# --- UI Functions ---
msg_box() { whiptail --title "$1" --msgbox "$2" 12 65; }
confirm() { whiptail --title "$1" --yesno "$2" 12 65; }

# --- Core Logic ---
check_sudo() {
    echo "Authenticating for system tasks..."
    if ! sudo -v; then
        msg_box "Authentication Failed" "Administrator permissions are required."
        exit 1
    fi
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_PID=$!
    trap 'kill $SUDO_PID' EXIT
}

run_with_retry() {
    local cmd="$1"
    local description="$2"
    local attempt=1
    while [ $attempt -le 2 ]; do
        echo "Running: $description..."
        if eval "$cmd" > "$LOG_FILE" 2>&1; then return 0; fi
        msg_box "Retry" "$description failed. Retrying..."
        ((attempt++))
    done
    msg_box "Error" "Failed after 2 attempts. See $LOG_FILE"
    return 1
}

# --- Features ---
update_system() {
    msg_box "System Update" "Detected Distro: $DISTRO\n\nWe will now refresh your app list and install updates."
    run_with_retry "run_pkg_cmd update" "Refreshing repositories" && \
    run_with_retry "run_pkg_cmd upgrade" "Installing updates" && \
    run_with_retry "run_pkg_cmd clean" "Cleaning up" && \
    msg_box "Finished" "Your $DISTRO system is up to date!"
}

setup_shortcuts() {
    if confirm "Install Shortcuts?" "Make terminal easier?\n\n- 'install <pkg>' instead of long commands\n- 'whatsmyip' for network info"; then
        touch "$ALIAS_FILE"
        # Distro-aware alias
        case $DISTRO in
            arch*) echo "alias install='sudo pacman -S'" > "$ALIAS_FILE" ;;
            fedora*) echo "alias install='sudo dnf install'" > "$ALIAS_FILE" ;;
            *) echo "alias install='sudo apt install'" > "$ALIAS_FILE" ;;
        esac
        echo "alias whatsmyip='hostname -I | awk \"{print \$1}\"'" >> "$ALIAS_FILE"
        
        [[ ! $(grep "linux_buddy_aliases" "$HOME/.bashrc") ]] && echo -e "\n[[ -f $ALIAS_FILE ]] && . $ALIAS_FILE" >> "$HOME/.bashrc"
        msg_box "Success" "Shortcuts installed. Restart terminal to use them!"
    fi
}

# --- Main Menu ---
main_menu() {
    detect_distro
    while true; do
        CHOICE=$(whiptail --title "$APP_NAME ($DISTRO)" --menu "Main Menu" 16 65 6 \
            "1" "Full System Update" \
            "2" "Install Beginner Shortcuts" \
            "3" "AI Helper (Coming Soon)" \
            "4" "Show System Info" \
            "5" "Exit" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) update_system ;;
            2) setup_shortcuts ;;
            3) msg_box "AI" "This feature requires a Gemini API key. Integration coming in v0.3!" ;;
            4) clear; [ -x "$(command -v neofetch)" ] && neofetch || uname -a; read -p "Press Enter..." ;;
            5) exit 0 ;;
            *) exit 0 ;;
        esac
    done
}

check_sudo
main_menu
