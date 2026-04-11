#!/bin/bash
# VoxScribe App Management Script
# Interactive menu with arrow key navigation
# Usage: ./app.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="VoxScribe"
BUNDLE_ID="com.voxscribe.app"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
INSTALL_DIR="/Applications"
MODELS_DIR="$HOME/Documents/VoxScribe Models"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'
REVERSE='\033[7m'

# Arrow key menu selector
# Usage: arrow_menu "title" options[@]
# Sets MENU_RESULT to the selected index (0-based)
arrow_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local count=${#options[@]}

    # Hide cursor
    tput civis

    while true; do
        # Clear screen and draw menu
        clear
        echo ""
        echo -e "  ${WHITE}===============================${NC}"
        echo -e "  ${WHITE}  ${title}${NC}"
        echo -e "  ${WHITE}===============================${NC}"
        echo ""

        for i in "${!options[@]}"; do
            if [ "$i" -eq "$selected" ]; then
                echo -e "  ${REVERSE} > ${options[$i]} ${NC}"
            else
                echo -e "    ${DIM}${options[$i]}${NC}"
            fi
        done

        echo ""
        echo -e "  ${DIM}Use arrow keys to navigate, Enter to select${NC}"

        # Read key input
        read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') # Up arrow
                        ((selected--))
                        [ "$selected" -lt 0 ] && selected=$((count - 1))
                        ;;
                    '[B') # Down arrow
                        ((selected++))
                        [ "$selected" -ge "$count" ] && selected=0
                        ;;
                esac
                ;;
            '') # Enter
                tput cnorm
                MENU_RESULT=$selected
                return
                ;;
        esac
    done
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local options=("Yes" "No")
    arrow_menu "$message" "${options[@]}"
    return $MENU_RESULT
}

# Press any key to continue
pause() {
    echo ""
    echo -e "  ${DIM}Press any key to continue...${NC}"
    read -rsn1
}

# ============================================================
# Core Functions
# ============================================================

find_build_dir() {
    find "$DERIVED_DATA" -maxdepth 1 -name "${APP_NAME}-*" -type d 2>/dev/null | head -1
}

get_built_app() {
    local build_dir
    build_dir=$(find_build_dir)
    if [ -n "$build_dir" ]; then
        echo "$build_dir/Build/Products/Debug/${APP_NAME}.app"
    fi
}

kill_app() {
    if pkill -9 -f "${APP_NAME}.app" 2>/dev/null; then
        echo -e "  ${GREEN}Killed running ${APP_NAME}${NC}"
    else
        echo -e "  ${DIM}No running instance found${NC}"
    fi
}

build_app() {
    echo ""
    echo -e "  ${CYAN}Building ${APP_NAME}...${NC}"
    echo ""
    cd "$PROJECT_DIR"
    xcodegen generate 2>&1 | tail -1
    xcodebuild build \
        -project ${APP_NAME}.xcodeproj \
        -scheme ${APP_NAME} \
        -destination 'platform=macOS' \
        2>&1 | grep -E '(error:|BUILD)' | grep -v "whisper.cpp" | tail -10

    local built_app
    built_app=$(get_built_app)
    if [ -n "$built_app" ] && [ -d "$built_app" ]; then
        echo ""
        echo -e "  ${GREEN}Build succeeded${NC}"
    else
        echo ""
        echo -e "  ${RED}Build failed${NC}"
    fi
}

install_app() {
    clear
    echo ""
    echo -e "  ${WHITE}Build & Install${NC}"
    echo ""

    local built_app
    built_app=$(get_built_app)

    if [ -z "$built_app" ] || [ ! -d "$built_app" ]; then
        echo -e "  ${YELLOW}No build found. Building first...${NC}"
        build_app
        built_app=$(get_built_app)
    fi

    if [ ! -d "$built_app" ]; then
        echo -e "  ${RED}Build failed. Cannot install.${NC}"
        pause
        return
    fi

    kill_app

    if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
        echo -e "  ${YELLOW}Removing existing installation...${NC}"
        rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    fi

    echo -e "  ${CYAN}Installing to ${INSTALL_DIR}...${NC}"
    cp -R "$built_app" "${INSTALL_DIR}/${APP_NAME}.app"
    echo -e "  ${GREEN}Installed ${APP_NAME} to ${INSTALL_DIR}/${APP_NAME}.app${NC}"
    echo -e "  ${CYAN}Launching ${APP_NAME}...${NC}"
    open "${INSTALL_DIR}/${APP_NAME}.app"
    echo -e "  ${GREEN}${APP_NAME} is running${NC}"
    pause
}

uninstall_app() {
    clear
    echo ""
    echo -e "  ${WHITE}Uninstall ${APP_NAME}${NC}"
    echo ""

    kill_app

    if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
        rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
        echo -e "  ${GREEN}Removed ${APP_NAME} from ${INSTALL_DIR}${NC}"
    else
        echo -e "  ${DIM}${APP_NAME} is not installed in ${INSTALL_DIR}${NC}"
    fi

    echo ""
    confirm_action "Also remove preferences and models?"
    if [ $MENU_RESULT -eq 0 ]; then
        defaults delete "$BUNDLE_ID" 2>/dev/null && echo -e "  ${GREEN}Removed preferences${NC}" || true
        rm -rf "$MODELS_DIR" && echo -e "  ${GREEN}Removed models directory${NC}" || true
        rm -rf "$HOME/Library/Containers/$BUNDLE_ID" 2>/dev/null || true
        echo -e "  ${GREEN}Full cleanup complete${NC}"
    fi
    pause
}

run_app() {
    clear
    echo ""
    echo -e "  ${WHITE}Run ${APP_NAME}${NC}"
    echo ""

    local app_path="${INSTALL_DIR}/${APP_NAME}.app"

    if [ ! -d "$app_path" ]; then
        local built_app
        built_app=$(get_built_app)
        if [ -n "$built_app" ] && [ -d "$built_app" ]; then
            app_path="$built_app"
        else
            echo -e "  ${RED}No app found. Build and install first.${NC}"
            pause
            return
        fi
    fi

    kill_app
    echo -e "  ${GREEN}Launching ${APP_NAME}...${NC}"
    open "$app_path"
    pause
}

run_app_debug() {
    clear
    echo ""
    echo -e "  ${WHITE}Run ${APP_NAME} (Debug)${NC}"
    echo ""

    local built_app
    built_app=$(get_built_app)

    if [ -z "$built_app" ] || [ ! -d "$built_app" ]; then
        echo -e "  ${YELLOW}No debug build found. Building first...${NC}"
        build_app
        built_app=$(get_built_app)
    fi

    kill_app
    echo -e "  ${GREEN}Launching in debug mode... Press Ctrl+C to stop${NC}"
    echo -e "  ${DIM}---${NC}"
    "$built_app/Contents/MacOS/${APP_NAME}" 2>&1
}

clean_build() {
    clear
    echo ""
    echo -e "  ${WHITE}Clean & Rebuild${NC}"
    echo ""

    local build_dir
    build_dir=$(find_build_dir)
    if [ -n "$build_dir" ]; then
        rm -rf "$build_dir"
        echo -e "  ${GREEN}Removed DerivedData${NC}"
    fi
    build_app
    pause
}

download_model() {
    local models=("tiny.en  (English  ~75 MB)" "tiny     (Multi    ~75 MB)" "base.en  (English  ~142 MB)" "base     (Multi    ~142 MB)" "small.en (English  ~466 MB)" "small    (Multi    ~466 MB)" "medium.en(English  ~1.5 GB)" "medium   (Multi    ~1.5 GB)" "large-v3 (Multi    ~3.1 GB)" "Back")
    local model_names=("tiny.en" "tiny" "base.en" "base" "small.en" "small" "medium.en" "medium" "large-v3")
    local base_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    # Mark downloaded models
    local display_models=()
    for i in "${!model_names[@]}"; do
        local name="${model_names[$i]}"
        local file="$MODELS_DIR/ggml-${name}.bin"
        local mark=" "
        if [ -f "$file" ]; then
            mark="*"
        fi
        display_models+=("[${mark}] ${models[$i]}")
    done
    display_models+=("Back")

    arrow_menu "Download Model (* = downloaded)" "${display_models[@]}"

    if [ "$MENU_RESULT" -ge "${#model_names[@]}" ]; then
        return
    fi

    local model="${model_names[$MENU_RESULT]}"
    local filename="ggml-${model}.bin"
    local filepath="$MODELS_DIR/$filename"

    if [ -f "$filepath" ]; then
        confirm_action "${model} already downloaded. Re-download?"
        if [ $MENU_RESULT -ne 0 ]; then
            return
        fi
    fi

    clear
    echo ""
    echo -e "  ${CYAN}Downloading ${model}...${NC}"
    echo ""
    mkdir -p "$MODELS_DIR"
    curl -L -o "$filepath" "${base_url}/${filename}" --progress-bar
    echo ""
    echo -e "  ${GREEN}Downloaded ${model}${NC}"
    pause
}

delete_model() {
    local downloaded=()
    local downloaded_names=()

    if [ -d "$MODELS_DIR" ]; then
        for f in "$MODELS_DIR"/ggml-*.bin; do
            if [ -f "$f" ]; then
                local name
                name=$(basename "$f" | sed 's/ggml-//' | sed 's/.bin//')
                local size
                size=$(ls -lh "$f" | awk '{print $5}')
                downloaded+=("${name} (${size})")
                downloaded_names+=("$name")
            fi
        done
    fi

    if [ ${#downloaded[@]} -eq 0 ]; then
        clear
        echo ""
        echo -e "  ${DIM}No models downloaded${NC}"
        pause
        return
    fi

    downloaded+=("Back")

    arrow_menu "Delete Model" "${downloaded[@]}"

    if [ "$MENU_RESULT" -ge "${#downloaded_names[@]}" ]; then
        return
    fi

    local model="${downloaded_names[$MENU_RESULT]}"
    confirm_action "Delete ${model}?"
    if [ $MENU_RESULT -eq 0 ]; then
        rm -f "$MODELS_DIR/ggml-${model}.bin"
        echo -e "  ${GREEN}Deleted ${model}${NC}"
        pause
    fi
}

show_logs() {
    clear
    echo ""
    echo -e "  ${WHITE}Recent Logs${NC}"
    echo ""

    if [ -f /tmp/voxscribe.log ]; then
        tail -40 /tmp/voxscribe.log
    else
        echo -e "  ${DIM}No log file found. Run in debug mode to capture logs.${NC}"
    fi
    pause
}

show_status() {
    clear
    echo ""
    echo -e "  ${WHITE}${APP_NAME} Status${NC}"
    echo ""

    if pgrep -f "${APP_NAME}.app" >/dev/null 2>&1; then
        echo -e "  Running:     ${GREEN}YES${NC} (PID $(pgrep -f "${APP_NAME}.app" | head -1))"
    else
        echo -e "  Running:     ${DIM}NO${NC}"
    fi

    if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
        echo -e "  Installed:   ${GREEN}${INSTALL_DIR}/${APP_NAME}.app${NC}"
    else
        echo -e "  Installed:   ${DIM}NO${NC}"
    fi

    local built_app
    built_app=$(get_built_app)
    if [ -n "$built_app" ] && [ -d "$built_app" ]; then
        echo -e "  Debug build: ${GREEN}YES${NC}"
    else
        echo -e "  Debug build: ${DIM}NO${NC}"
    fi

    echo ""
    echo -e "  ${WHITE}Models:${NC}"
    if [ -d "$MODELS_DIR" ]; then
        local found=0
        for f in "$MODELS_DIR"/ggml-*.bin; do
            if [ -f "$f" ]; then
                local name
                name=$(basename "$f" | sed 's/ggml-//' | sed 's/.bin//')
                local size
                size=$(ls -lh "$f" | awk '{print $5}')
                echo -e "    ${GREEN}${name}${NC} (${size})"
                found=1
            fi
        done
        if [ "$found" -eq 0 ]; then
            echo -e "    ${DIM}(none)${NC}"
        fi
    else
        echo -e "    ${DIM}(directory not found)${NC}"
    fi

    echo ""
    echo -e "  ${WHITE}Preferences:${NC}"
    local selected_model
    selected_model=$(defaults read "$BUNDLE_ID" selectedModelName 2>/dev/null || echo "tiny")
    echo -e "    Model:     ${CYAN}${selected_model}${NC}"
    local hotkey
    hotkey=$(defaults read "$BUNDLE_ID" hotkeyKeyCode 2>/dev/null || echo "not set")
    echo -e "    Hotkey:    ${CYAN}${hotkey}${NC}"
    local login
    login=$(defaults read "$BUNDLE_ID" launchAtLogin 2>/dev/null || echo "0")
    if [ "$login" = "1" ]; then
        echo -e "    Login:     ${GREEN}enabled${NC}"
    else
        echo -e "    Login:     ${DIM}disabled${NC}"
    fi

    pause
}

# ============================================================
# Main Menu Loop
# ============================================================

main_options=(
    "Build & Install & Start"
    "Uninstall"
    "Run"
    "Run (Debug with logs)"
    "Kill"
    "Clean & Rebuild"
    "Download Model"
    "Delete Model"
    "Show Logs"
    "Status"
    "Exit"
)

# Restore cursor on exit
trap 'tput cnorm; exit' INT TERM EXIT

while true; do
    arrow_menu "${APP_NAME} Management" "${main_options[@]}"

    case $MENU_RESULT in
        0) install_app ;;
        1) uninstall_app ;;
        2) run_app ;;
        3) run_app_debug ;;
        4) kill_app; pause ;;
        5) clean_build ;;
        6) download_model ;;
        7) delete_model ;;
        8) show_logs ;;
        9) show_status ;;
        10) clear; exit 0 ;;
    esac
done
