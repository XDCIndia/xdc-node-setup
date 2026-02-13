#!/bin/bash
#==============================================================================
# XDC Node Setup - ASCII Art Banners and Branding
#==============================================================================

# Colors
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_MAGENTA='\033[0;35m'
readonly C_BOLD='\033[1m'

#==============================================================================
# Banner Functions
#==============================================================================

# Main XDC banner (large)
banner_xdc_large() {
    echo -e "${C_CYAN}"
    cat << 'EOF'
 _   _  _____   _____ 
| | | ||  _  \ /  ___|
| | | || | | || |    
| | | || | | || |    
| |_| || |/ / | |___ 
 \___/ |___/   \____|
                      
 _   _           _       _       
| | | | ___   __| | ___ | |_ ___ 
| |_| |/ _ \ / _` |/ _ \| __/ __|
|  _  | (_) | (_| | (_) | |_\__ \
|_| |_|\___/ \__,_|\___/ \__|___/
                                  
EOF
    echo -e "${C_RESET}"
}

# Compact XDC banner
banner_xdc_compact() {
    echo -e "${C_CYAN}"
    cat << 'EOF'
╔════════════════════════════════╗
║     XDC Node Setup v2.1.0      ║
║   Enterprise Node Deployment   ║
╚════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
}

# Setup banner
banner_setup() {
    echo -e "${C_GREEN}"
    cat << 'EOF'
 _____      _            _____       _   
/  ___|    | |          /  ___|     | |  
\ `--.  ___| |_ ___ _ __\ `--.  ___ | |_ 
 `--. \/ _ \ __/ _ \ '__|`--. \/ _ \| __|
/\__/ /  __/ ||  __/ |  /\__/ / (_) | |_ 
\____/ \___|\__\___|_|  \____/ \___/ \__|
                                          
EOF
    echo -e "${C_RESET}"
}

# Security banner
banner_security() {
    echo -e "${C_YELLOW}"
    cat << 'EOF'
 _____                _             _ 
/  ___|              | |           | |
\ `--.  ___ _ __ ___ | | ___   __ _| |
 `--. \/ _ \ '_ ` _ \| |/ _ \ / _` | |
/\__/ /  __/ | | | | | | (_) | (_| | |
\____/ \___|_| |_| |_|_|\___/ \__,_|_|
                                       
EOF
    echo -e "${C_RESET}"
}

# Health check banner
banner_health() {
    echo -e "${C_GREEN}"
    cat << 'EOF'
 _   _            _   _           
| | | |          | | | |          
| |_| | __ ___  _| |_| |__   ___  
|  _  |/ _` \ \/ / __| '_ \ / _ \ 
| | | | (_| |>  <| |_| | | |  __/ 
\_| |_/\__,_/_/\_\\__|_| |_|\___| 
                                  
EOF
    echo -e "${C_RESET}"
}

# Backup banner
banner_backup() {
    echo -e "${C_BLUE}"
    cat << 'EOF'
______            _             
| ___ \          | |            
| |_/ / __ _  ___| | _____ _ __ 
| ___ \/ _` |/ __| |/ / _ \ '__|
| |_/ / (_| | (__|   <  __/ |   
\____/ \__,_|\___|_|\_\___|_|   
                                 
EOF
    echo -e "${C_RESET}"
}

# Monitoring banner
banner_monitoring() {
    echo -e "${C_MAGENTA}"
    cat << 'EOF'
___  ___            _   _             
|  \/  |           | | (_)            
| .  . |_   _  ___ | |_ _ _ __   __ _ 
| |\/| | | | |/ _ \| __| | '_ \ / _` |
| |  | | |_| | (_) | |_| | | | | (_| |
\_|  |_/\__, |\___/ \__|_|_| |_|\__, |
         __/ |                   __/ |
        |___/                   |___/ 
EOF
    echo -e "${C_RESET}"
}

# Success banner
banner_success() {
    echo -e "${C_GREEN}${C_BOLD}"
    cat << 'EOF'
╔══════════════════════════════════╗
║        ✓ OPERATION SUCCESS       ║
╚══════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
}

# Error banner
banner_error() {
    echo -e "${C_RED}${C_BOLD}"
    cat << 'EOF'
╔══════════════════════════════════╗
║        ✗ OPERATION FAILED        ║
╚══════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
}

# Warning banner
banner_warning() {
    echo -e "${C_YELLOW}${C_BOLD}"
    cat << 'EOF'
╔══════════════════════════════════╗
║         ⚠ WARNING                ║
╚══════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
}

# Info banner
banner_info() {
    echo -e "${C_BLUE}${C_BOLD}"
    cat << 'EOF'
╔══════════════════════════════════╗
║         ℹ INFORMATION            ║
╚══════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
}

# Progress indicator
banner_progress() {
    local message="${1:-Processing...}"
    local width=40
    local filled=${2:-0}  # 0-100
    local empty=$((width - (filled * width / 100)))
    local filled_chars=$((width - empty))

    printf "\r${C_CYAN}["
    printf "%${filled_chars}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]${C_RESET} %3d%% %s" "$filled" "$message"
}

# Section divider
banner_divider() {
    echo -e "${C_CYAN}"
    printf '=%.0s' {1..60}
    echo -e "${C_RESET}"
}

# Subsection divider
banner_subdivider() {
    echo -e "${C_BLUE}"
    printf -- '-%.0s' {1..40}
    echo -e "${C_RESET}"
}

#==============================================================================
# Utility Functions
#==============================================================================

# Print status with icon
print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        ok|success)
            echo -e "${C_GREEN}✓${C_RESET} $message"
            ;;
        error|fail)
            echo -e "${C_RED}✗${C_RESET} $message"
            ;;
        warn|warning)
            echo -e "${C_YELLOW}⚠${C_RESET} $message"
            ;;
        info)
            echo -e "${C_BLUE}ℹ${C_RESET} $message"
            ;;
        pending)
            echo -e "${C_CYAN}○${C_RESET} $message"
            ;;
        *)
            echo -e "  $message"
            ;;
    esac
}

# Print a step in the process
print_step() {
    local step="$1"
    local total="${2:-?}"
    local message="$3"

    echo -e "${C_CYAN}[${step}/${total}]${C_RESET} $message"
}

# Clear screen with banner
clear_with_banner() {
    clear
    banner_xdc_compact
    banner_divider
}

#==============================================================================
# Interactive Menu Helpers
#==============================================================================

# Display a menu header
menu_header() {
    local title="$1"
    clear
    banner_xdc_compact
    banner_divider
    echo -e "${C_BOLD}${title}${C_RESET}"
    banner_subdivider
    echo ""
}

# Display a menu option
menu_option() {
    local number="$1"
    local label="$2"
    local description="${3:-}"

    printf "  ${C_CYAN}%2d)${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$number" "$label"
    if [[ -n "$description" ]]; then
        printf "      %s\n" "$description"
    fi
}

# Display a prompt
menu_prompt() {
    local prompt="${1:-Select an option:}"
    echo ""
    echo -ne "${C_CYAN}▶${C_RESET} $prompt "
}

#==============================================================================
# Export Functions
#==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f banner_xdc_large
    export -f banner_xdc_compact
    export -f banner_setup
    export -f banner_security
    export -f banner_health
    export -f banner_backup
    export -f banner_monitoring
    export -f banner_success
    export -f banner_error
    export -f banner_warning
    export -f banner_info
    export -f banner_progress
    export -f banner_divider
    export -f banner_subdivider
    export -f print_status
    export -f print_step
    export -f clear_with_banner
    export -f menu_header
    export -f menu_option
    export -f menu_prompt
fi