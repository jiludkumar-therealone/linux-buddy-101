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
VERSION="0.8.1-alpha" 
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
                echo "Snap not found. Installing snapd..."
                case $DISTRO in
                    ubuntu|debian|kali|pop|linuxmint) sudo apt-get install -y snapd ;;
                    fedora|rhel|centos) sudo dnf install -y snapd ;;
                    arch|manjaro) sudo pacman -S --noconfirm snapd && sudo systemctl enable --now snapd.socket ;;
                esac
                [ ! -L /snap ] && sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null
            fi
            
            if [[ "$target" == "code" || "$target" == "discord" || "$target" == "spotify" || "$target" == "micro" ]]; then
                sudo snap install "$target" --classic
            else
                sudo snap install "$target"
            fi
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

    cp "$shell_rc" "${shell_rc}.bak"
    grep -v "hello" "${shell_rc}.bak" > "$shell_rc"
    echo "" >> "$shell_rc"
    echo "# Linux Buddy Shortcut" >> "$shell_rc"
    echo "hello() { \"$SCRIPT_PATH\" \"\$@\"; }" >> "$shell_rc"
    
    whiptail --title "Shortcut Installed" --inputbox \
    "Linked 'hello' to script. Copy (Ctrl+C) and run this to finish:" \
    12 70 "$source_cmd" 3>&1 1>&2 2>&3
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
        "Fix Packages") 
            sudo dpkg --configure -a && sudo apt-get install -f
            msg_box "Done" "Fix attempt finished."
            ;;
        "Restart Audio")
            systemctl --user restart pulseaudio || systemctl --user restart pipewire
            msg_box "Audio" "Sound services restarted."
            ;;
        "Restart Bluetooth")
            sudo systemctl restart bluetooth
            msg_box "Bluetooth" "Bluetooth service has been reset."
            ;;
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
        "Disk Usage")
            local usage=$(df -h --total | grep 'total')
            local root_free=$(df -h / | awk 'NR==2 {print $4}')
            msg_box "Disk Stats" "Total Usage: $usage\nFree space on Root (/): $root_free"
            ;;
        "Network Info")
            local local_ip=$(hostname -I | awk '{print $1}')
            local public_ip=$(curl -s ifconfig.me || echo "Unknown")
            msg_box "Network Details" "Local IP: $local_ip\nPublic IP: $public_ip"
            ;;
        "Kernel & OS")
            local kernel=$(uname -r)
            local arch=$(uname -m)
            msg_box "OS details" "Kernel Version: $kernel\nArchitecture: $arch\nDistro ID: $DISTRO"
            ;;
        "Running Services")
            clear
            echo "Top 10 Active Services (Systemd):"
            echo "--------------------------------"
            systemctl list-units --type=service --state=running | head -n 12
            read -p "Press Enter to return..."
            ;;
    esac
}

power_tools() {
    local task
    task=$(whiptail --title "Power User Tools" --menu "Advanced automations:" 16 75 6 \
        "Setup GitHub Identity" "Set your Git Name & Email" \
        "Generate SSH Key" "Create a key for GitHub/GitLab" \
        "Find Huge Files" "Find files larger than 100MB" \
        "Fix Permissions" "Fix 'Read Only' Home folder issues" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $task in
        "Setup GitHub Identity")
            local name=$(whiptail --inputbox "Enter your Full Name:" 10 60 3>&1 1>&2 2>&3)
            local email=$(whiptail --inputbox "Enter your Email:" 10 60 3>&1 1>&2 2>&3)
            if [ -n "$name" ] && [ -n "$email" ]; then
                git config --global user.name "$name"
                git config --global user.email "$email"
                msg_box "Success" "Git identity set to: $name <$email>"
            fi
            ;;
        "Generate SSH Key")
            if [ -f "$HOME/.ssh/id_ed25519" ]; then
                msg_box "Key Exists" "You already have an SSH key at ~/.ssh/id_ed25519"
            else
                local email=$(whiptail --inputbox "Enter email for the key:" 10 60 3>&1 1>&2 2>&3)
                ssh-keygen -t ed25519 -C "$email" -N "" -f "$HOME/.ssh/id_ed25519"
                msg_box "Success" "Key generated! Look in ~/.ssh/id_ed25519.pub"
            fi
            whiptail --title "Copy your Public Key" --inputbox "Paste this into GitHub settings:" 12 75 "$(cat $HOME/.ssh/id_ed25519.pub)" 3>&1 1>&2 2>&3
            ;;
        "Find Huge Files")
            clear
            echo "Searching for files larger than 100MB in your Home folder..."
            echo "--------------------------------------------------------"
            find "$HOME" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{ print $5, $9 }'
            echo "--------------------------------------------------------"
            read -p "Press Enter to return..."
            ;;
        "Fix Permissions")
            sudo chown -R "$USER":"$USER" "$HOME"
            msg_box "Fixed" "Ownership of your home folder has been reset to you."
            ;;
    esac
}

custom_install() {
    local target
    target=$(whiptail --title "Custom App Search" --inputbox "Type the name of the app you want to install:" 10 60 3>&1 1>&2 2>&3)
    
    if [ -n "$target" ]; then
        echo "Searching for '$target' in your repositories..."
        if run_pkg_cmd search "$target"; then
            if whiptail --title "App Found" --yesno "I found '$target'. Would you like to install it now?" 10 60; then
                run_pkg_cmd install "$target"
                msg_box "Success" "$target has been installed!"
            fi
        else
            msg_box "Not Found" "I couldn't find '$target' in your repositories."
        fi
    fi
}

app_store() {
    local APP
    APP=$(whiptail --title "App Store" --menu "Choose an app to install:" 20 82 14 \
        "SEARCH" "[ NEW ] Search & Install Any Custom App" \
        "ncdu" "TUI: Interactive disk usage analyzer" \
        "ranger" "TUI: Advanced terminal file manager" \
        "micro" "TUI: Modern, intuitive text editor" \
        "glances" "TUI: Comprehensive system monitor" \
        "htop" "TUI: Classic process monitor" \
        "btop" "TUI: Modern colorful system monitor" \
        "git" "Dev: Version Control System" \
        "docker" "Dev: Containerization Platform" \
        "python3" "Dev: Python Language Environment" \
        "code" "Snap: Visual Studio Code" \
        "spotify" "Snap: Music Streaming Client" \
        "discord" "Snap: Communication Platform" \
        "vlc" "App: Universal Media Player" \
        "firefox" "Web: Modern Browser" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    case $APP in
        "SEARCH") custom_install ;;
        "Back"|"") return ;;
        *)
            clear
            if [[ "$APP" == "code" || "$APP" == "spotify" || "$APP" == "discord" ]]; then
                run_pkg_cmd snap "$APP"
            else
                run_pkg_cmd install "$APP"
            fi
            msg_box "Complete" "Installation for $APP finished."
            ;;
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
        "3" "Power Tools (SSH, Git, Permissions)" \
        "4" "System Information Suite (IP, Disk, OS)" \
        "5" "Ask AI Assistant (English to Bash)" \
        "6" "App Store (TUI, Apps & Snaps)" \
        "7" "Install/Fix 'hello' Shortcut" \
        "8" "Quick System Summary (Neofetch)" \
        "9" "Uninstall Linux Buddy" \
        "10" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) run_pkg_cmd update && msg_box "Success" "System updated!" ;;
        2) system_doctor ;;
        3) power_tools ;;
        4) system_info_suite ;;
        5) ask_ai ;;
        6) app_store ;;
        7) install_hello_shortcut ;;
        8) clear; neofetch; echo ""; read -p "Press Enter to return to menu..." ;;
        9) if whiptail --title "Uninstall" --yesno "Remove everything?" 10 60; then rm -rf "$CONFIG_DIR"; sed -i '/hello/d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null; exit 0; fi ;;
        10) exit 0 ;;
        *) exit 0 ;;
    esac
done