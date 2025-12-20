#!/usr/bin/env bash

# --- 0. TERMINAL-FIRST AUTHENTICATION ---
if ! sudo -n true 2>/dev/null; then
    clear
    echo "========================================================"
    echo "                LINUX BUDDY: ADMIN ACCESS               "
    echo "========================================================"
    echo " To manage your system and apps, I need your password.  "
    echo ""
    if ! sudo -v; then
        echo ""
        echo " [!] Authentication failed. Exiting."
        exit 1
    fi
    echo " [+] Success! Loading menu..."
    sleep 0.5
    clear
fi

# Keep-alive sudo in background
( while true; do sudo -n -v >/dev/null 2>&1; sleep 60; done ) &
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null' EXIT

# --- 1. Configuration & Setup ---
APP_NAME="Linux Buddy"
VERSION="0.5.7-alpha"
CONFIG_DIR="$HOME/.config/linux-buddy"
CONFIG_FILE="$CONFIG_DIR/config"

# Robust path detection
raw_path="${BASH_SOURCE[0]:-$0}"
SCRIPT_PATH=$(readlink -f "$raw_path")

mkdir -p "$CONFIG_DIR"

# --- 2. Internal Logic ---

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi
}

check_deps() {
    local missing_deps=()
    for cmd in whiptail curl jq neofetch; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Setting up dependencies: ${missing_deps[*]}..."
        case $DISTRO in
            ubuntu|debian|kali|pop|linuxmint)
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}" ;;
            fedora|rhel|centos)
                sudo dnf install -y "${missing_deps[@]}" ;;
            arch|manjaro)
                sudo pacman -S --noconfirm "${missing_deps[@]}" ;;
        esac
        clear
    fi
}

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

# --- 3. Features ---

get_api_key() {
    if [ -f "$CONFIG_FILE" ]; then
        API_KEY=$(cat "$CONFIG_FILE")
    else
        whiptail --title "AI Setup" --msgbox "You need a free Gemini API Key.\n\nGet one here: https://aistudio.google.com/app/apikey" 10 65
        API_KEY=$(whiptail --title "Paste Key" --passwordbox "Paste your key here (it will be hidden):" 10 65 3>&1 1>&2 2>&3)
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
    msg_box "Buddy's Answer" "${ai_text:-Error: Could not reach Gemini. Check your key or internet.}"
}

install_hello_shortcut() {
    local shell_rc=""
    local source_cmd=""
    
    [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc" || shell_rc="$HOME/.bashrc"
    source_cmd="source $shell_rc"

    # Scrub old entries to avoid conflicts
    cp "$shell_rc" "${shell_rc}.bak"
    grep -v "hello" "${shell_rc}.bak" > "$shell_rc"

    # Save as a Function
    echo "" >> "$shell_rc"
    echo "# Linux Buddy Shortcut" >> "$shell_rc"
    echo "hello() { \"$SCRIPT_PATH\" \"\$@\"; }" >> "$shell_rc"
    
    whiptail --title "Shortcut Installed" --inputbox \
    "I've linked 'hello' to your script. Copy (Ctrl+C) and run this to finish activation:" \
    12 70 "$source_cmd" 3>&1 1>&2 2>&3
}

uninstall_buddy() {
    if whiptail --title "Uninstall" --yesno "Remove your API key and the 'hello' shortcut?" 10 60; then
        rm -rf "$CONFIG_DIR"
        sed -i '/hello/d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null
        msg_box "Uninstalled" "Components removed."
        exit 0
    fi
}

system_doctor() {
    local task
    task=$(whiptail --title "System Doctor" --menu "Select a diagnostic task:" 16 70 5 \
        "Check Internet" "Test your connection status" \
        "Clean Disk" "Remove temporary files" \
        "Fix Packages" "Fix broken installs (Ubuntu/Debian)" \
        "Health Report" "Check RAM and CPU load" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Check Internet") ping -c 3 8.8.8.8 >/dev/null 2>&1 && msg_box "Status" "ONLINE" || msg_box "Status" "OFFLINE" ;;
        "Clean Disk") run_pkg_cmd clean && msg_box "Success" "Caches cleared." ;;
        "Fix Packages") 
            if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
                sudo dpkg --configure -a && sudo apt-get install -f
                msg_box "Done" "Fix attempt finished."
            else
                msg_box "Unsupported" "This tool is for Ubuntu/Debian."
            fi
            ;;
        "Health Report")
            local ram=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
            local load=$(uptime | awk -F'load average:' '{ print $2 }')
            msg_box "Health" "RAM Usage: $ram\nCPU Load: $load"
            ;;
    esac
}

app_store() {
    local APP
    APP=$(whiptail --title "App Store" --menu "Choose an app to install:" 20 75 12 \
        "vlc" "Multimedia: Universal Media Player" \
        "git" "Dev: Version Control System" \
        "htop" "System: Interactive Process Monitor" \
        "btop" "System: Modern Resource Monitor" \
        "tree" "Utilities: Visual Directory Structure" \
        "vim" "Editors: Advanced Text Editor" \
        "nano" "Editors: Simple Text Editor" \
        "gimp" "Graphics: Image Manipulation Program" \
        "firefox" "Web: Modern Browser" \
        "chromium" "Web: Open-source Chrome Alternative" \
        "python3" "Dev: Python Programming Language" \
        "docker" "Dev: Containerization Platform" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    if [ "$APP" != "Back" ] && [ -n "$APP" ]; then
        echo "Installing $APP... Please wait."
        run_pkg_cmd install "$APP"
        msg_box "Complete" "$APP task finished."
    fi
}

msg_box() { whiptail --title "$1" --msgbox "$2" 14 70; }

# --- 4. Main Execution ---
detect_distro
check_deps

while true; do
    CHOICE=$(whiptail --title "$APP_NAME v$VERSION ($DISTRO)" --menu "Main Menu" 18 75 8 \
        "1" "System Maintenance (Update & Upgrade)" \
        "2" "System Doctor (Fix & Check Health)" \
        "3" "Ask AI Assistant (English to Bash)" \
        "4" "App Store (Install Popular Apps)" \
        "5" "Install/Fix 'hello' Shortcut" \
        "6" "Quick System Summary (Neofetch)" \
        "7" "Uninstall Linux Buddy" \
        "8" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) run_pkg_cmd update && msg_box "Success" "System updated!" ;;
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