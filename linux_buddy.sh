#!/usr/bin/env bash

# --- Configuration & Setup ---
APP_NAME="Linux Buddy"
VERSION="0.4.1-alpha"
CONFIG_DIR="$HOME/.config/linux-buddy"
CONFIG_FILE="$CONFIG_DIR/config"
SCRIPT_PATH=$(realpath "$0")

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# --- Distro Detection ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi
}

# --- Permissions Check ---
# Keeps sudo active so the TUI doesn't flicker when asking for passwords
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo "Linux Buddy needs administrator permissions for some tasks."
        if ! sudo -v; then
            echo "Authentication failed. Exiting."
            exit 1
        fi
    fi
    # Keep-alive sudo in the background
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_PID=$!
    trap 'kill $SUDO_PID 2>/dev/null' EXIT
}

# --- Dependencies Check & Auto-Install ---
check_deps() {
    local missing_deps=()
    for cmd in whiptail curl jq neofetch; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Linux Buddy needs to install some tools to work: ${missing_deps[*]}"
        case $DISTRO in
            ubuntu|debian|kali|pop|linuxmint)
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}" ;;
            fedora|rhel|centos)
                sudo dnf install -y "${missing_deps[@]}" ;;
            arch|manjaro)
                sudo pacman -S --noconfirm "${missing_deps[@]}" ;;
            *)
                echo "Unknown distro. Please manually install: ${missing_deps[*]}"
                exit 1
                ;;
        esac
    fi
}

# --- Unified Package Runner ---
run_pkg_cmd() {
    local action=$1
    case $DISTRO in
        ubuntu|debian|kali|pop|linuxmint)
            case $action in
                update)  sudo apt-get update && sudo apt-get dist-upgrade -y ;;
                clean)   sudo apt-get autoremove -y && sudo apt-get clean ;;
                install) sudo apt-get install -y "${@:2}" ;;
            esac
            ;;
        fedora|rhel|centos)
            case $action in
                update)  sudo dnf upgrade -y ;;
                clean)   sudo dnf autoremove -y ;;
                install) sudo dnf install -y "${@:2}" ;;
            esac
            ;;
        arch|manjaro)
            case $action in
                update)  sudo pacman -Syu --noconfirm ;;
                clean)   sudo pacman -Sc --noconfirm ;;
                install) sudo pacman -S --noconfirm "${@:2}" ;;
            esac
            ;;
    esac
}

# --- Shortcuts & Aliases ---
install_hello_shortcut() {
    local shell_rc=""
    local source_cmd=""

    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
        source_cmd="source ~/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
        source_cmd="source ~/.bashrc"
    fi

    if grep -q "alias hello=" "$shell_rc"; then
        msg_box "Shortcut Exists" "The 'hello' shortcut is already installed.\n\nIf it's not working, run: $source_cmd"
    else
        echo "" >> "$shell_rc"
        echo "# Linux Buddy Shortcut" >> "$shell_rc"
        echo "alias hello='$SCRIPT_PATH'" >> "$shell_rc"
        msg_box "Shortcut Installed" "Success! To start using it, please run:\n\n$source_cmd"
    fi
}

# --- Uninstaller ---
uninstall_buddy() {
    if whiptail --title "Uninstall Linux Buddy" --yesno "This will remove your API key, configuration, and the 'hello' shortcut. Are you sure?" 12 65; then
        rm -rf "$CONFIG_DIR"
        sed -i '/# Linux Buddy Shortcut/d' "$HOME/.bashrc" 2>/dev/null
        sed -i '/alias hello=/d' "$HOME/.bashrc" 2>/dev/null
        sed -i '/# Linux Buddy Shortcut/d' "$HOME/.zshrc" 2>/dev/null
        sed -i '/alias hello=/d' "$HOME/.zshrc" 2>/dev/null
        msg_box "Uninstalled" "Components removed. You can now delete this script file."
        exit 0
    fi
}

# --- System Doctor ---
system_doctor() {
    local task
    task=$(whiptail --title "System Doctor" --menu "Select a diagnostic task:" 16 70 5 \
        "Check Internet" "Test your connection status" \
        "Clean Disk" "Remove temporary files" \
        "Fix Packages" "Fix broken installs (Ubuntu/Debian)" \
        "Health Report" "Check RAM and CPU load" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Check Internet")
            ping -c 3 8.8.8.8 > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                msg_box "Status" "ONLINE: Connection is stable."
            else
                msg_box "Status" "OFFLINE: Check your network settings."
            fi
            ;;
        "Clean Disk")
            run_pkg_cmd clean
            msg_box "Success" "Temporary files cleared."
            ;;
        "Fix Packages")
            if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
                sudo dpkg --configure -a && sudo apt-get install -f
                msg_box "Done" "Fix attempt finished."
            else
                msg_box "Unsupported" "This tool is currently for Ubuntu/Debian only."
            fi
            ;;
        "Health Report")
            local ram
            local load
            ram=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
            load=$(uptime | awk -F'load average:' '{ print $2 }')
            msg_box "Health" "RAM Usage: $ram\nCPU Load: $load"
            ;;
    esac
}

# --- App Store ---
app_store() {
    local APP
    APP=$(whiptail --title "Popular Apps" --menu "Choose an app to install:" 16 65 5 \
        "vlc" "Universal Media Player" \
        "git" "Version Control System" \
        "htop" "Interactive Process Monitor" \
        "btop" "Modern Resource Monitor" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    if [ "$APP" != "Back" ] && [ -n "$APP" ]; then
        run_pkg_cmd install "$APP"
        msg_box "Complete" "$APP installation process finished."
    fi
}

# --- AI Brain ---
get_api_key() {
    if [ -f "$CONFIG_FILE" ]; then
        API_KEY=$(cat "$CONFIG_FILE")
    else
        whiptail --title "AI Setup" --msgbox "Get a free key at: https://aistudio.google.com/app/apikey" 10 65
        API_KEY=$(whiptail --passwordbox "Paste your Gemini API Key here:" 10 65 3>&1 1>&2 2>&3)
        if [ -n "$API_KEY" ]; then
            echo "$API_KEY" > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        fi
    fi
}

ask_ai() {
    get_api_key
    if [ -z "$API_KEY" ]; then return; fi
    local user_query
    user_query=$(whiptail --title "AI Assistant" --inputbox "What would you like to do in Linux?" 10 70 3>&1 1>&2 2>&3)
    [ -z "$user_query" ] && return
    
    echo "Consulting the AI brain..."
    local response
    response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=${API_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{\"contents\": [{\"parts\": [{\"text\": \"Role: Expert Linux Tutor. Task: Explain '$user_query' in one short sentence, then the exact command. No markdown.\"}]}]}")
    
    local ai_text
    ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
    msg_box "Buddy's Answer" "${ai_text:-Error: Could not reach Gemini. Verify your API key.}"
}

# --- UI Helpers ---
msg_box() { whiptail --title "$1" --msgbox "$2" 14 70; }

# --- Main Logic ---
detect_distro
check_deps
check_sudo

while true; do
    CHOICE=$(whiptail --title "$APP_NAME v$VERSION ($DISTRO)" --menu "Main Menu" 18 75 8 \
        "1" "System Maintenance (Update & Upgrade)" \
        "2" "System Doctor (Fix & Check Health)" \
        "3" "Ask AI Assistant (English to Bash)" \
        "4" "App Store (Install Popular Apps)" \
        "5" "Install 'hello' Shortcut" \
        "6" "Quick System Summary (Neofetch)" \
        "7" "Uninstall Linux Buddy" \
        "8" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) run_pkg_cmd update && msg_box "Success" "System is now up to date!" ;;
        2) system_doctor ;;
        3) ask_ai ;;
        4) app_store ;;
        5) install_hello_shortcut ;;
        6) clear; neofetch; echo ""; read -p "Press Enter to return to menu..." ;;
        7) uninstall_buddy ;;
        8) exit 0 ;;
        *) exit 0 ;;
    esac
done