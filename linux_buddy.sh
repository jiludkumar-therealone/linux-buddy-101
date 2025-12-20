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
VERSION="0.8.6-alpha" 
CONFIG_DIR="$HOME/.config/linux-buddy"
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]:-$0}")

mkdir -p "$CONFIG_DIR"

# --- 2. Internal Helpers (Visuals & Logic) ---

# Colors for the visual search
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 
BOLD='\033[1m'

spinner() {
    local pid=$1
    local query=$2
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  ${CYAN}Searching for '$query'...${NC}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

visual_search() {
    local query=$1
    clear
    echo -e "${BOLD}${CYAN}========================================================${NC}"
    echo -e "${BOLD}${CYAN}                FILE SEARCH POWER-TOOL                  ${NC}"
    echo -e "${BOLD}${CYAN}========================================================${NC}"
    echo -e " ${YELLOW}Target:${NC} / (Whole PC)  ${YELLOW}Query:${NC} $query"
    echo -e " ${RED}Press Ctrl+C to cancel search anytime.${NC}"
    echo ""

    # Run in subshell to isolate the search process
    (
        TMP_RESULTS=$(mktemp)
        # Background the find command
        sudo find / -iname "*$query*" 2>/dev/null | head -n 30 > "$TMP_RESULTS" &
        FIND_PID=$!

        # Local trap for Ctrl+C inside search
        trap "kill $FIND_PID 2>/dev/null; echo -e '\n${RED}[!] Search Interrupted.${NC}'; return" INT
        
        spinner $FIND_PID "$query"

        if [ ! -s "$TMP_RESULTS" ]; then
            echo -e "${RED} [!] No files found matching your query.${NC}"
        else
            echo -e "${GREEN}${BOLD} TOP 30 RESULTS FOUND:${NC}"
            echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"
            printf "${BOLD}%-15s | %-50s${NC}\n" "TYPE" "LOCATION / PATH"
            echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"
            
            while IFS= read -r line; do
                if [ -d "$line" ]; then
                    printf "${YELLOW}%-15s${NC} | %-50s\n" "[FOLDER]" "$line"
                else
                    printf "${GREEN}%-15s${NC} | %-50s\n" "[FILE]" "$line"
                fi
            done < "$TMP_RESULTS"
            echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"
        fi
        rm -f "$TMP_RESULTS"
    )
    echo ""
    read -p "Press [Enter] to return to Linux Buddy..."
}

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
    local target=$2
    case $action in
        update|upgrade)
            case $DISTRO in
                ubuntu|debian|kali|pop|linuxmint) sudo apt-get update && sudo apt-get dist-upgrade -y ;;
                fedora|rhel|centos) sudo dnf upgrade -y ;;
                arch|manjaro) sudo pacman -Syu --noconfirm ;;
            esac
            ;;
        clean)
            case $DISTRO in
                ubuntu|debian|kali|pop|linuxmint) sudo apt-get autoremove -y && sudo apt-get clean ;;
                fedora|rhel|centos) sudo dnf autoremove -y ;;
                arch|manjaro) sudo pacman -Sc --noconfirm ;;
            esac
            ;;
        install)
            case $DISTRO in
                ubuntu|debian|kali|pop|linuxmint) sudo apt-get install -y "$target" ;;
                fedora|rhel|centos) sudo dnf install -y "$target" ;;
                arch|manjaro) sudo pacman -S --noconfirm "$target" ;;
            esac
            ;;
        search)
            case $DISTRO in
                ubuntu|debian|kali|pop|linuxmint) apt-cache show "$target" &>/dev/null ;;
                fedora|rhel|centos) dnf list "$target" &>/dev/null ;;
                arch|manjaro) pacman -Si "$target" &>/dev/null ;;
            esac
            ;;
        snap)
            if ! command -v snap &> /dev/null; then
                case $DISTRO in
                    ubuntu|debian|kali|pop|linuxmint) sudo apt-get install -y snapd ;;
                    fedora|rhel|centos) sudo dnf install -y snapd ;;
                    arch|manjaro) sudo pacman -S --noconfirm snapd && sudo systemctl enable --now snapd.socket ;;
                esac
                [ ! -L /snap ] && sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null
            fi
            [[ "$target" == "code" || "$target" == "discord" || "$target" == "spotify" || "$target" == "micro" ]] && sudo snap install "$target" --classic || sudo snap install "$target"
            ;;
    esac
}

# --- 3. Features ---

get_api_key() {
    if [ -f "$CONFIG_FILE" ]; then API_KEY=$(cat "$CONFIG_FILE")
    else
        whiptail --title "AI Setup" --msgbox "You need a free Gemini API Key.\n\nGet one here: https://aistudio.google.com/app/apikey" 10 65
        API_KEY=$(whiptail --title "Paste Key" --passwordbox "Paste your key here (it will be hidden):" 10 65 3>&1 1>&2 2>&3)
        [ -n "$API_KEY" ] && echo "$API_KEY" > "$CONFIG_FILE" && chmod 600 "$CONFIG_FILE"
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
    [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc" || shell_rc="$HOME/.bashrc"
    cp "$shell_rc" "${shell_rc}.bak"
    grep -v "hello" "${shell_rc}.bak" > "$shell_rc"
    echo -e "\nhello() { \"$SCRIPT_PATH\" \"\$@\"; }" >> "$shell_rc"
    whiptail --title "Shortcut Installed" --inputbox "Linked 'hello' to script. Run this to finish:" 12 70 "source $shell_rc" 3>&1 1>&2 2>&3
}

system_doctor() {
    local task
    task=$(whiptail --title "System Doctor" --menu "Diagnostic tools:" 16 70 6 \
        "Check Internet" "Test your connection status" \
        "Clean Disk" "Remove temporary files" \
        "Fix Packages" "Fix broken installs (Ubuntu/Debian)" \
        "Restart Audio" "Fix sound issues (PulseAudio/Pipewire)" \
        "Restart Bluetooth" "Reset the Bluetooth service" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Check Internet") ping -c 3 8.8.8.8 >/dev/null 2>&1 && msg_box "Status" "ONLINE" || msg_box "Status" "OFFLINE" ;;
        "Clean Disk") run_pkg_cmd clean && msg_box "Success" "Caches cleared." ;;
        "Fix Packages") sudo dpkg --configure -a && sudo apt-get install -f && msg_box "Done" "Fix attempt finished." ;;
        "Restart Audio") systemctl --user restart pulseaudio || systemctl --user restart pipewire && msg_box "Audio" "Sound services restarted." ;;
        "Restart Bluetooth") sudo systemctl restart bluetooth && msg_box "Bluetooth" "Bluetooth service reset." ;;
    esac
}

system_info_suite() {
    local task
    task=$(whiptail --title "System Information" --menu "What would you like to check?" 16 70 5 \
        "Disk Usage" "Detailed breakdown of storage" \
        "Network Info" "Local and Public IP addresses" \
        "Kernel & OS" "Detailed versioning information" \
        "Running Services" "List active system services" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Disk Usage") msg_box "Disk Stats" "$(df -h --total | grep 'total')\nFree on Root: $(df -h / | awk 'NR==2 {print $4}')" ;;
        "Network Info") msg_box "Network Details" "Local IP: $(hostname -I | awk '{print $1}')\nPublic IP: $(curl -s ifconfig.me || echo 'Unknown')" ;;
        "Kernel & OS") msg_box "OS details" "Kernel: $(uname -r)\nArch: $(uname -m)\nDistro: $DISTRO" ;;
        "Running Services") clear; echo "Top Active Services:"; systemctl list-units --type=service --state=running | head -n 12; read -p "Press Enter to return..." ;;
    esac
}

power_tools() {
    local task
    task=$(whiptail --title "Power User Tools" --menu "Advanced automations:" 16 75 7 \
        "Search for File" "VISUAL: Find files with spinner & colors" \
        "Find Huge Files" "Find files larger than 100MB" \
        "Setup GitHub Identity" "Set your Git Name & Email" \
        "Generate SSH Key" "Create a key for GitHub/GitLab" \
        "Fix Permissions" "Fix 'Read Only' Home folder issues" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Search for File")
            local query
            query=$(whiptail --title "File Search" --inputbox "Enter a file or folder name to search for:" 10 60 3>&1 1>&2 2>&3)
            [ -n "$query" ] && visual_search "$query"
            ;;
        "Find Huge Files") clear; echo "Searching for files > 100MB..."; find "$HOME" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{ print $5, $9 }'; read -p "Press Enter..." ;;
        "Setup GitHub Identity")
            local name=$(whiptail --inputbox "Enter Name:" 10 60 3>&1 1>&2 2>&3)
            local email=$(whiptail --inputbox "Enter Email:" 10 60 3>&1 1>&2 2>&3)
            [ -n "$name" ] && git config --global user.name "$name" && git config --global user.email "$email" && msg_box "Success" "Identity set."
            ;;
        "Generate SSH Key")
            [ ! -f "$HOME/.ssh/id_ed25519" ] && ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
            whiptail --title "Copy Public Key" --inputbox "Paste into GitHub:" 12 75 "$(cat $HOME/.ssh/id_ed25519.pub)" 3>&1 1>&2 2>&3
            ;;
        "Fix Permissions") sudo chown -R "$USER":"$USER" "$HOME" && msg_box "Fixed" "Home folder permissions reset." ;;
    esac
}

custom_install() {
    local target
    target=$(whiptail --title "Custom App Search" --inputbox "Type app name:" 10 60 3>&1 1>&2 2>&3)
    if [ -n "$target" ] && run_pkg_cmd search "$target"; then
        whiptail --title "Found" --yesno "Install '$target'?" 10 60 && run_pkg_cmd install "$target" && msg_box "Success" "Installed!"
    else
        [ -n "$target" ] && msg_box "Not Found" "Couldn't find '$target'."
    fi
}

app_store() {
    local APP
    APP=$(whiptail --title "App Store" --menu "Choose an app:" 20 82 14 \
        "SEARCH" "[ NEW ] Search & Install Any Custom App" \
        "ncdu" "TUI: Interactive disk usage analyzer" \
        "ranger" "TUI: Advanced terminal file manager" \
        "micro" "TUI: Modern text editor" \
        "glances" "TUI: Comprehensive monitor" \
        "htop" "TUI: Classic process monitor" \
        "btop" "TUI: Modern colorful monitor" \
        "git" "Dev: Version Control" \
        "docker" "Dev: Containers" \
        "python3" "Dev: Python Environment" \
        "code" "Snap: VS Code" \
        "spotify" "Snap: Spotify" \
        "discord" "Snap: Discord" \
        "vlc" "App: VLC Player" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $APP in
        "SEARCH") custom_install ;;
        "Back"|"") return ;;
        *) clear; [[ "$APP" == "code" || "$APP" == "spotify" || "$APP" == "discord" ]] && run_pkg_cmd snap "$APP" || run_pkg_cmd install "$APP"; msg_box "Complete" "Done." ;;
    esac
}

msg_box() { whiptail --title "$1" --msgbox "$2" 14 70; }

# --- 4. Main Execution ---
detect_distro
check_deps

while true; do
    CHOICE=$(whiptail --title "$APP_NAME v$VERSION ($DISTRO)" --menu "Main Menu" 22 78 11 \
        "1" "System Maintenance (Update & Upgrade)" \
        "2" "System Doctor (Fix Audio, BT, Internet)" \
        "3" "Power Tools (SSH, Git, Visual Search)" \
        "4" "System Information Suite (IP, Disk, OS)" \
        "5" "Ask AI Assistant (English to Bash)" \
        "6" "App Store (TUI, Apps & Snaps)" \
        "7" "Install/Fix 'hello' Shortcut" \
        "8" "Quick System Summary (Neofetch)" \
        "9" "Uninstall Linux Buddy" \
        "10" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) run_pkg_cmd update && msg_box "Success" "Updated!" ;;
        2) system_doctor ;;
        3) power_tools ;;
        4) system_info_suite ;;
        5) ask_ai ;;
        6) app_store ;;
        7) install_hello_shortcut ;;
        8) clear; neofetch; echo ""; read -p "Press Enter to return..." ;;
        9) whiptail --yesno "Remove everything?" 10 60 && rm -rf "$CONFIG_DIR" && sed -i '/hello/d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null && exit 0 ;;
        10) exit 0 ;;
        *) exit 0 ;;
    esac
done