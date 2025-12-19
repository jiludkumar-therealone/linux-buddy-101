#!/usr/bin/env bash

# --- Configuration & Setup ---
APP_NAME="Linux Buddy"
VERSION="0.3.3-alpha"
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

# --- Dependencies Check & Auto-Install ---
check_deps() {
    local missing_deps=()
    for cmd in whiptail curl jq neofetch; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Linux Buddy needs to install some tools to work: ${missing_deps[*]}"
        echo "Please enter your password to allow this setup."
        
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
        msg_box "Shortcut Exists" "The 'hello' shortcut is already installed in $shell_rc.\n\nIf it's not working, run: $source_cmd"
    else
        echo "" >> "$shell_rc"
        echo "# Linux Buddy Shortcut" >> "$shell_rc"
        echo "alias hello='$SCRIPT_PATH'" >> "$shell_rc"
        msg_box "Shortcut Installed" "Success! To start using it, please run this command in your terminal:\n\n$source_cmd\n\nOr simply open a new terminal tab."
    fi
}

# --- Uninstaller ---
uninstall_buddy() {
    if whiptail --title "Uninstall Linux Buddy" --yesno "This will remove your API key, configuration, and the 'hello' shortcut. Are you sure?" 12 65; then
        # Remove config directory
        rm -rf "$CONFIG_DIR"
        
        # Remove aliases from .bashrc and .zshrc
        sed -i '/# Linux Buddy Shortcut/d' "$HOME/.bashrc" 2>/dev/null
        sed -i '/alias hello=/d' "$HOME/.bashrc" 2>/dev/null
        sed -i '/# Linux Buddy Shortcut/d' "$HOME/.zshrc" 2>/dev/null
        sed -i '/alias hello=/d' "$HOME/.zshrc" 2>/dev/null
        
        msg_box "Uninstalled" "Linux Buddy components removed. You can now manually delete the script file if you wish."
        exit 0
    fi
}

# --- API Key Guided Setup ---
get_api_key() {
    if [ -f "$CONFIG_FILE" ]; then
        API_KEY=$(cat "$CONFIG_FILE")
    else
        whiptail --title "AI Setup Required" --msgbox "To use the AI Assistant, you need a free Gemini API Key.\n\nI will now show you the link to get one for free." 12 65
        whiptail --title "Step 1: Get Your Key" --msgbox "1. Go to: https://aistudio.google.com/app/apikey\n2. Sign in with Google\n3. Click 'Create API key'\n4. Copy the key." 14 70
        
        API_KEY=$(whiptail --title "Step 2: Save Your Key" --passwordbox "Paste your Gemini API Key here (it will stay hidden):" 12 65 3>&1 1>&2 2>&3)
        
        if [ -n "$API_KEY" ]; then
            echo "$API_KEY" > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            msg_box "Setup Complete" "Your AI Brain is now connected!"
        else
            msg_box "Setup Skipped" "AI features will be disabled until a key is provided."
        fi
    fi
}

# --- UI Helpers ---
msg_box() { whiptail --title "$1" --msgbox "$2" 14 70; }

# --- Features ---
app_store() {
    local APP=$(whiptail --title "Popular Apps" --menu "Choose an app to install:" 16 65 5 \
        "vlc" "Universal Media Player" \
        "git" "The tool you use for GitHub" \
        "htop" "Visual system monitor" \
        "btop" "Modern colorful system monitor" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    if [ "$APP" != "Back" ] && [ -n "$APP" ]; then
        echo "Installing $APP..."
        case $DISTRO in
            ubuntu|debian) sudo apt-get install -y "$APP" ;;
            fedora) sudo dnf install -y "$APP" ;;
            arch) sudo pacman -S --noconfirm "$APP" ;;
        esac
        msg_box "Installation" "$APP task completed!"
    fi
}

ask_ai() {
    get_api_key
    if [ -z "$API_KEY" ]; then return; fi

    local user_query=$(whiptail --title "AI Assistant" --inputbox "What do you want to do in Linux? (e.g., 'Check my disk space')" 10 70 3>&1 1>&2 2>&3)
    if [ -z "$user_query" ]; then return; fi

    echo "Querying Gemini AI... please wait."
    
    local response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=${API_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"contents\": [{
                \"parts\": [{
                    \"text\": \"Role: Expert Linux Tutor. Task: Explain how to do '$user_query' for a total beginner. Format: One short sentence of explanation, then the exact bash command on the next line. Use no markdown code blocks.\"
                }]
            }]
        }")

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
    
    if [ "$ai_text" != "null" ] && [ -n "$ai_text" ]; then
        msg_box "Buddy's Answer" "$ai_text"
    else
        msg_box "Connection Error" "Failed to get an answer. Please check your internet or API key."
    fi
}

# --- Start ---
detect_distro
check_deps

while true; do
    CHOICE=$(whiptail --title "$APP_NAME v$VERSION ($DISTRO)" --menu "Main Menu" 18 75 7 \
        "1" "System Maintenance (Update & Upgrade)" \
        "2" "Install Popular Apps" \
        "3" "Ask AI Assistant" \
        "4" "Install 'hello' Shortcut" \
        "5" "Quick System Summary" \
        "6" "Uninstall Linux Buddy" \
        "7" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) sudo apt-get update && sudo apt-get upgrade -y || sudo dnf upgrade -y || sudo pacman -Syu --noconfirm ;;
        2) app_store ;;
        3) ask_ai ;;
        4) install_hello_shortcut ;;
        5) clear; neofetch; read -p "Press Enter to return to menu..." ;;
        6) uninstall_buddy ;;
        7) exit 0 ;;
        *) exit 0 ;;
    esac
done#!/usr/bin/env bash

# --- Configuration & Setup ---
APP_NAME="Linux Buddy"
VERSION="0.3.3-alpha"
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

# --- Dependencies Check & Auto-Install ---
check_deps() {
    local missing_deps=()
    for cmd in whiptail curl jq neofetch; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Linux Buddy needs to install some tools to work: ${missing_deps[*]}"
        echo "Please enter your password to allow this setup."
        
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
        msg_box "Shortcut Exists" "The 'hello' shortcut is already installed in $shell_rc.\n\nIf it's not working, run: $source_cmd"
    else
        echo "" >> "$shell_rc"
        echo "# Linux Buddy Shortcut" >> "$shell_rc"
        echo "alias hello='$SCRIPT_PATH'" >> "$shell_rc"
        msg_box "Shortcut Installed" "Success! To start using it, please run this command in your terminal:\n\n$source_cmd\n\nOr simply open a new terminal tab."
    fi
}

# --- Uninstaller ---
uninstall_buddy() {
    if whiptail --title "Uninstall Linux Buddy" --yesno "This will remove your API key, configuration, and the 'hello' shortcut. Are you sure?" 12 65; then
        # Remove config directory
        rm -rf "$CONFIG_DIR"
        
        # Remove aliases from .bashrc and .zshrc
        sed -i '/# Linux Buddy Shortcut/d' "$HOME/.bashrc" 2>/dev/null
        sed -i '/alias hello=/d' "$HOME/.bashrc" 2>/dev/null
        sed -i '/# Linux Buddy Shortcut/d' "$HOME/.zshrc" 2>/dev/null
        sed -i '/alias hello=/d' "$HOME/.zshrc" 2>/dev/null
        
        msg_box "Uninstalled" "Linux Buddy components removed. You can now manually delete the script file if you wish."
        exit 0
    fi
}

# --- API Key Guided Setup ---
get_api_key() {
    if [ -f "$CONFIG_FILE" ]; then
        API_KEY=$(cat "$CONFIG_FILE")
    else
        whiptail --title "AI Setup Required" --msgbox "To use the AI Assistant, you need a free Gemini API Key.\n\nI will now show you the link to get one for free." 12 65
        whiptail --title "Step 1: Get Your Key" --msgbox "1. Go to: https://aistudio.google.com/app/apikey\n2. Sign in with Google\n3. Click 'Create API key'\n4. Copy the key." 14 70
        
        API_KEY=$(whiptail --title "Step 2: Save Your Key" --passwordbox "Paste your Gemini API Key here (it will stay hidden):" 12 65 3>&1 1>&2 2>&3)
        
        if [ -n "$API_KEY" ]; then
            echo "$API_KEY" > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            msg_box "Setup Complete" "Your AI Brain is now connected!"
        else
            msg_box "Setup Skipped" "AI features will be disabled until a key is provided."
        fi
    fi
}

# --- UI Helpers ---
msg_box() { whiptail --title "$1" --msgbox "$2" 14 70; }

# --- Features ---
app_store() {
    local APP=$(whiptail --title "Popular Apps" --menu "Choose an app to install:" 16 65 5 \
        "vlc" "Universal Media Player" \
        "git" "The tool you use for GitHub" \
        "htop" "Visual system monitor" \
        "btop" "Modern colorful system monitor" \
        "Back" "Return to main menu" 3>&1 1>&2 2>&3)

    if [ "$APP" != "Back" ] && [ -n "$APP" ]; then
        echo "Installing $APP..."
        case $DISTRO in
            ubuntu|debian) sudo apt-get install -y "$APP" ;;
            fedora) sudo dnf install -y "$APP" ;;
            arch) sudo pacman -S --noconfirm "$APP" ;;
        esac
        msg_box "Installation" "$APP task completed!"
    fi
}

ask_ai() {
    get_api_key
    if [ -z "$API_KEY" ]; then return; fi

    local user_query=$(whiptail --title "AI Assistant" --inputbox "What do you want to do in Linux? (e.g., 'Check my disk space')" 10 70 3>&1 1>&2 2>&3)
    if [ -z "$user_query" ]; then return; fi

    echo "Querying Gemini AI... please wait."
    
    local response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-09-2025:generateContent?key=${API_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{
            \"contents\": [{
                \"parts\": [{
                    \"text\": \"Role: Expert Linux Tutor. Task: Explain how to do '$user_query' for a total beginner. Format: One short sentence of explanation, then the exact bash command on the next line. Use no markdown code blocks.\"
                }]
            }]
        }")

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
    
    if [ "$ai_text" != "null" ] && [ -n "$ai_text" ]; then
        msg_box "Buddy's Answer" "$ai_text"
    else
        msg_box "Connection Error" "Failed to get an answer. Please check your internet or API key."
    fi
}

# --- Start ---
detect_distro
check_deps

while true; do
    CHOICE=$(whiptail --title "$APP_NAME v$VERSION ($DISTRO)" --menu "Main Menu" 18 75 7 \
        "1" "System Maintenance (Update & Upgrade)" \
        "2" "Install Popular Apps" \
        "3" "Ask AI Assistant" \
        "4" "Install 'hello' Shortcut" \
        "5" "Quick System Summary" \
        "6" "Uninstall Linux Buddy" \
        "7" "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) sudo apt-get update && sudo apt-get upgrade -y || sudo dnf upgrade -y || sudo pacman -Syu --noconfirm ;;
        2) app_store ;;
        3) ask_ai ;;
        4) install_hello_shortcut ;;
        5) clear; neofetch; read -p "Press Enter to return to menu..." ;;
        6) uninstall_buddy ;;
        7) exit 0 ;;
        *) exit 0 ;;
    esac
done