#!/usr/bin/env bash

# nvim-cat installer script
# Simple installer for users who prefer a single command

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share/nvim-cat"

print_usage() {
    cat << EOF
nvim-cat installer

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -u, --user          Install to user directory (default)
    -s, --system        Install system-wide (requires sudo)
    -p, --prefix DIR    Install to custom prefix
    -r, --uninstall     Uninstall nvim-cat
    -h, --help          Show this help

EXAMPLES:
    $0                  # Install to ~/.local/bin
    $0 --system         # Install to /usr/local/bin (requires sudo)
    $0 --prefix /opt    # Install to /opt/bin
    $0 --uninstall      # Remove nvim-cat
EOF
}

check_nvim() {
    if ! command -v nvim &> /dev/null; then
        echo -e "${RED}❌ Error: Neovim is not installed or not in PATH${NC}"
        echo "Please install Neovim 0.10+ first"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Neovim found:${NC} $(nvim --version | head -1)"
}

install_user() {
    echo -e "${BLUE}Installing nvim-cat to user directory...${NC}"
    
    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$SHARE_DIR"
    
    # Install binary
    cp bin/nvim-cat "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/nvim-cat"
    
    # Install Lua modules
    cp -r lua "$SHARE_DIR/"
    
    echo -e "${GREEN}✅ nvim-cat installed successfully!${NC}"
    echo -e "   Binary: ${INSTALL_DIR}/nvim-cat"
    echo -e "   Lua modules: ${SHARE_DIR}/lua"
    echo ""
    
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo -e "${YELLOW}⚠️  ~/.local/bin is not in your PATH${NC}"
        echo "Add this line to your ~/.bashrc or ~/.zshrc:"
        echo -e "${BLUE}export PATH=\"\$PATH:\$HOME/.local/bin\"${NC}"
        echo ""
    fi
    
    echo -e "You can now use: ${GREEN}nvim-cat <file>${NC}"
}

install_system() {
    local prefix="${1:-/usr/local}"
    local bin_dir="$prefix/bin"
    local share_dir="$prefix/share/nvim-cat"
    
    echo -e "${BLUE}Installing nvim-cat system-wide to $prefix...${NC}"
    
    # Check for sudo if needed
    if [[ ! -w "$prefix" ]]; then
        if ! command -v sudo &> /dev/null; then
            echo -e "${RED}❌ Error: Need sudo to install to $prefix${NC}"
            exit 1
        fi
        local SUDO="sudo"
    else
        local SUDO=""
    fi
    
    # Create directories
    $SUDO mkdir -p "$bin_dir"
    $SUDO mkdir -p "$share_dir"
    
    # Install binary
    $SUDO cp bin/nvim-cat "$bin_dir/"
    $SUDO chmod +x "$bin_dir/nvim-cat"
    
    # Install Lua modules  
    $SUDO cp -r lua "$share_dir/"
    
    echo -e "${GREEN}✅ nvim-cat installed successfully!${NC}"
    echo -e "   Binary: $bin_dir/nvim-cat"
    echo -e "   Lua modules: $share_dir/lua"
    echo ""
    echo -e "You can now use: ${GREEN}nvim-cat <file>${NC}"
}

uninstall_user() {
    echo -e "${BLUE}Uninstalling nvim-cat from user directory...${NC}"
    
    rm -f "$INSTALL_DIR/nvim-cat"
    rm -rf "$SHARE_DIR"
    
    echo -e "${GREEN}✅ nvim-cat uninstalled successfully!${NC}"
}

uninstall_system() {
    local prefix="${1:-/usr/local}"
    local bin_dir="$prefix/bin"
    local share_dir="$prefix/share/nvim-cat"
    
    echo -e "${BLUE}Uninstalling nvim-cat from $prefix...${NC}"
    
    # Check for sudo if needed
    if [[ ! -w "$prefix" ]]; then
        if ! command -v sudo &> /dev/null; then
            echo -e "${RED}❌ Error: Need sudo to uninstall from $prefix${NC}"
            exit 1
        fi
        local SUDO="sudo"
    else
        local SUDO=""
    fi
    
    $SUDO rm -f "$bin_dir/nvim-cat"
    $SUDO rm -rf "$share_dir"
    
    echo -e "${GREEN}✅ nvim-cat uninstalled successfully!${NC}"
}

# Main logic
main() {
    local install_type="user"
    local prefix="/usr/local"
    local uninstall=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                install_type="user"
                shift
                ;;
            -s|--system)
                install_type="system"
                shift
                ;;
            -p|--prefix)
                install_type="system"
                prefix="$2"
                shift 2
                ;;
            -r|--uninstall)
                uninstall=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                print_usage
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}nvim-cat installer${NC}"
    echo "=================="
    
    check_nvim
    echo ""
    
    if [[ $uninstall == true ]]; then
        case $install_type in
            user)
                uninstall_user
                ;;
            system)
                uninstall_system "$prefix"
                ;;
        esac
    else
        case $install_type in
            user)
                install_user
                ;;
            system)
                install_system "$prefix"
                ;;
        esac
    fi
}

main "$@"