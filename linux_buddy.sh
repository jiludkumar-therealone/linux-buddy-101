#!/usr/bin/env bash

# --- 0. TERMINAL-FIRST AUTHENTICATION ---
# Colors for the terminal
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m' 
BOLD='\033[1m'

if ! sudo -n true 2>/dev/null; then
    clear
    echo -e "${BOLD}${CYAN}========================================================${NC}"
    echo -e "${BOLD}${CYAN}                LINUX BUDDY: ADMIN ACCESS               ${NC}"
    echo -e "${BOLD}${CYAN}========================================================${NC}"
    echo -e " To manage your system and apps, I need your password.  "
    echo ""
    if ! sudo -v; then
        echo -e "\n ${RED}[!] Authentication failed. Exiting.${NC}"
        exit 1
    fi
    echo -e " ${GREEN}[+] Success! Loading menu...${NC}"
    sleep 0.5
    clear
fi

# Keep-alive sudo in background
( while true; do sudo -n -v >/dev/null 2>&1; sleep 60; done ) &
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null' EXIT

# --- 1. Configuration & Setup ---
APP_NAME="Linux Buddy"
VERSION="0.9.2-alpha" 
CONFIG_DIR="$HOME/.config/linux-buddy"
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]:-$0}")

mkdir -p "$CONFIG_DIR"

# --- 2. Internal Helpers (Visuals & Logic) ---

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

    (
        TMP_RESULTS=$(mktemp)
        sudo find / -iname "*$query*" 2>/dev/null | head -n 30 > "$TMP_RESULTS" &
        FIND_PID=$!
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
    for cmd in whiptail curl jq neofetch speedtest-cli; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Setting up dependencies: ${missing_deps[*]}...${NC}"
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
        remove)
            case $DISTRO in
                ubuntu|debian|kali|pop|linuxmint) sudo apt-get purge -y "$target" && sudo apt-get autoremove -y ;;
                fedora|rhel|centos) sudo dnf remove -y "$target" && sudo dnf autoremove -y ;;
                arch|manjaro) sudo pacman -Rs --noconfirm "$target" ;;
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
        snap-remove)
            sudo snap remove "$target"
            ;;
        flatpak-remove)
            sudo flatpak uninstall -y "$target"
            sudo flatpak uninstall --unused -y
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
    echo -e "${MAGENTA}Consulting the AI brain...${NC}"
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
    task=$(whiptail --title "System Doctor" --menu "Diagnostic tools:" 18 70 9 \
        "Speed Test" "Check Internet Download/Upload speeds" \
        "Check Internet" "Test your connection status (Ping)" \
        "Clean Disk" "Remove temporary files" \
        "Clean Orphan Packages" "Deep sweep for all unused system dependencies" \
        "Clear System Logs" "Clear old systemd journal logs (Save GBs!)" \
        "Fix Packages" "Repair broken installs or stale database locks" \
        "Restart Audio" "Fix sound issues (PulseAudio/Pipewire)" \
        "Restart Bluetooth" "Reset the Bluetooth service" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Speed Test")
            clear
            echo -e "${BOLD}${CYAN}========================================================${NC}"
            echo -e "${BOLD}${CYAN}               INTERNET SPEED TEST (BETA)               ${NC}"
            echo -e "${BOLD}${CYAN}========================================================${NC}"
            echo -e "${YELLOW} Connecting to the nearest server...${NC}"
            echo ""
            local result=$(speedtest-cli --simple)
            if [ -z "$result" ]; then
                echo -e "${RED}[!] Speed test failed. Check your connection.${NC}"
            else
                local ping=$(echo "$result" | grep "Ping" | awk '{print $2}')
                local down=$(echo "$result" | grep "Download" | awk '{print $2}')
                local up=$(echo "$result" | grep "Upload" | awk '{print $2}')
                echo -e " ${BOLD}Ping:${NC}      ${CYAN}$ping ms${NC}"
                echo -e " ${BOLD}Download:${NC}  ${BOLD}${GREEN}$down Mbit/s${NC}"
                echo -e " ${BOLD}Upload:${NC}    ${BOLD}${BLUE}$up Mbit/s${NC}"
            fi
            echo ""
            read -p "Press [Enter] to return..." ;;
        "Check Internet") ping -c 3 8.8.8.8 >/dev/null 2>&1 && msg_box "Status" "ONLINE" || msg_box "Status" "OFFLINE" ;;
        "Clean Disk") run_pkg_cmd clean && msg_box "Success" "Caches cleared." ;;
        "Clean Orphan Packages")
            echo -e "${YELLOW}Hunting for orphans...${NC}"
            run_pkg_cmd clean
            msg_box "Sweep Complete" "Unused dependencies have been removed." ;;
        "Clear System Logs")
            sudo journalctl --vacuum-time=1s
            msg_box "Logs Cleared" "Old system logs have been removed." ;;
        "Fix Packages")
            echo -e "${YELLOW}Attempting to repair package system for $DISTRO...${NC}"
            case $DISTRO in
                ubuntu|debian|kali|pop|linuxmint)
                    sudo dpkg --configure -a && sudo apt-get install -f
                    ;;
                arch|manjaro)
                    # Common Arch fix: Remove stale lock and sync
                    [ -f /var/lib/pacman/db.lck ] && sudo rm -f /var/lib/pacman/db.lck
                    sudo pacman -Syyu --noconfirm
                    ;;
                fedora|rhel|centos)
                    sudo dnf clean all && sudo dnf check
                    ;;
                *)
                    echo -e "${RED}Distro not explicitly supported for automated repair.${NC}"
                    ;;
            esac
            msg_box "Done" "Fix attempt finished for $DISTRO." ;;
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
        "Running Services") 
            clear
            echo -e "${BOLD}${CYAN}--------------------------------------------------------${NC}"
            echo -e " ${BOLD}Top Active Services (Systemd)${NC}"
            echo -e "${BOLD}${CYAN}--------------------------------------------------------${NC}"
            systemctl list-units --type=service --state=running | head -n 12
            echo ""
            read -p "Press [Enter] to return..." ;;
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
        "Find Huge Files") 
            clear
            echo -e "${BOLD}${YELLOW}Searching for files > 100MB in $HOME...${NC}"
            find "$HOME" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{ print $5, $9 }'
            echo ""
            read -p "Press [Enter] to return..." ;;
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

uninstaller_utility() {
    local query
    query=$(whiptail --title "App Uninstaller" --inputbox "Type the name of the app to search and remove:" 10 60 3>&1 1>&2 2>&3)
    [ -z "$query" ] && return

    echo -e "${YELLOW}Searching for installed packages matching '$query'...${NC}"
    
    local list=()
    # Search Native
    case $DISTRO in
        ubuntu|debian|kali|pop|linuxmint) 
            while read -r pkg; do list+=("$pkg" "[Native]"); done < <(dpkg-query -W -f='${Package}\n' "*$query*" 2>/dev/null) ;;
        fedora|rhel|centos) 
            while read -r pkg; do list+=("$pkg" "[Native]"); done < <(rpm -qa --queryformat '%{NAME}\n' "*$query*" 2>/dev/null) ;;
        arch|manjaro) 
            while read -r pkg; do list+=("$pkg" "[Native]"); done < <(pacman -Qq | grep "$query") ;;
    esac
    
    # Search Snaps
    if command -v snap &> /dev/null; then
        while read -r pkg; do list+=("$pkg" "[Snap]"); done < <(snap list | awk 'NR>1 {print $1}' | grep -i "$query")
    fi

    # Search Flatpaks
    if command -v flatpak &> /dev/null; then
        while read -r pkg; do list+=("$pkg" "[Flatpak]"); done < <(flatpak list --columns=application | grep -i "$query")
    fi

    if [ ${#list[@]} -eq 0 ]; then
        msg_box "Not Found" "No installed packages found matching '$query'."
        return
    fi

    local choice
    choice=$(whiptail --title "Uninstall Selection" --menu "Choose an item to remove:" 20 70 10 "${list[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$choice" ]; then
        local type=""
        for ((i=0; i<${#list[@]}; i+=2)); do
            if [[ "${list[i]}" == "$choice" ]]; then type="${list[i+1]}"; break; fi
        done

        if whiptail --title "Confirm" --yesno "Are you sure you want to remove $choice ($type)?" 10 60; then
            clear
            if [[ "$type" == "[Snap]" ]]; then
                run_pkg_cmd snap-remove "$choice"
            elif [[ "$type" == "[Flatpak]" ]]; then
                run_pkg_cmd flatpak-remove "$choice"
            else
                run_pkg_cmd remove "$choice"
            fi
            
            # Layered Safety Deep Clean Prompt
            # Layer 1: Guard against generic or core-system names
            if [[ ${#choice} -lt 3 || "$choice" =~ ^(bin|etc|lib|var|usr|sys|root|home|boot|dev)$ ]]; then
                msg_box "Deep Clean Skipped" "The app name '$choice' is too generic or matches core system paths. Skipping deep clean for safety."
            else
                if whiptail --title "Deep Clean" --yesno "Would you like to search for and remove leftover configuration files in your Home folder?" 10 65; then
                    echo -e "${YELLOW}Hunting for leftover configuration folders...${NC}"
                    
                    # Layer 2: Targeted Search in specific non-critical hidden folders
                    local scan_targets=("$HOME/.config" "$HOME/.local/share" "$HOME/.cache")
                    local config_found=""
                    for target in "${scan_targets[@]}"; do
                        if [ -d "$target" ]; then
                            # Find hidden folders specifically matching the app name within standard locations
                            local match=$(find "$target" -maxdepth 2 -name "*$choice*" -type d 2>/dev/null)
                            [ -n "$match" ] && config_found+="$match"$'\n'
                        fi
                    done

                    if [ -n "$config_found" ]; then
                        # Layer 3: Final User Verification
                        if whiptail --title "Confirm Delete" --yesno "Found these leftover folders. Delete them?\n\n$config_found" 15 70; then
                            # Sudo is NOT used here for home directory deletion to prevent accidentally touching system files
                            echo "$config_found" | xargs rm -rf
                            msg_box "Deep Clean Complete" "Leftover data removed safely."
                        fi
                    else
                        msg_box "Clean" "No leftover config folders found in standard locations."
                    fi
                fi
            fi
            
            msg_box "Removed" "$choice has been uninstalled."
        fi
    fi
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
    APP=$(whiptail --title "App Store" --menu "Software Management:" 20 82 14 \
        "SEARCH" "[ NEW ] Search & Install Any Custom App" \
        "UNINSTALL" "[ NEW ] Smart Uninstaller (Native, Snap & Flatpak)" \
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
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $APP in
        "SEARCH") custom_install ;;
        "UNINSTALL") uninstaller_utility ;;
        "Back"|"") return ;;
        *) 
            clear
            echo -e "${YELLOW}Requesting installation for $APP...${NC}"
            [[ "$APP" == "code" || "$APP" == "spotify" || "$APP" == "discord" ]] && run_pkg_cmd snap "$APP" || run_pkg_cmd install "$APP"
            msg_box "Complete" "Done." ;;
    esac
}

msg_box() { whiptail --title "$1" --msgbox "$2" 14 70; }

# --- 4. Main Execution ---
detect_distro
check_deps

while true; do
    CHOICE=$(whiptail --title "$APP_NAME v$VERSION ($DISTRO)" --menu "Main Menu" 22 78 11 \
        "1" "System Maintenance (Update & Upgrade)" \
        "2" "System Doctor (Fix Audio, Speed Test, etc.)" \
        "3" "Power Tools (SSH, Git, Visual Search)" \
        "4" "System Information Suite (IP, Disk, OS)" \
        "5" "Ask AI Assistant (English to Bash)" \
        "6" "App Store & Smart Uninstaller" \
        "7" "Install/Fix 'hello' Shortcut" \
        "8" "Quick System Summary (Neofetch)" \
        "9" "Uninstall Linux Buddy" \
        "10" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) 
            echo -e "${YELLOW}Starting system maintenance...${NC}"
            run_pkg_cmd update && msg_box "Success" "Updated!" ;;
        2) system_doctor ;;
        3) power_tools ;;
        4) system_info_suite ;;
        5) ask_ai ;;
        6) app_store ;;
        7) install_hello_shortcut ;;
        8) 
            clear
            echo -e "${BOLD}${CYAN}========================================================${NC}"
            echo -e " ${BOLD}System Summary${NC}"
            echo -e "${BOLD}${CYAN}========================================================${NC}"
            neofetch; echo ""; read -p "Press [Enter] to return..." ;;
        9) 
            if whiptail --yesno "Remove everything?" 10 60; then 
                rm -rf "$CONFIG_DIR"
                sed -i '/hello/d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null
                echo -e "${RED}Uninstalled Linux Buddy successfully.${NC}"
                exit 0
            fi ;;
        10) exit 0 ;;
        *) exit 0 ;;
    esac
done