#!/bin/bash
# macOS Security Monitor - Quick Installation Script
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

echo_color "$BLUE" "🛡️  macOS Security Monitor - Installation"
echo_color "$BLUE" "========================================"
echo ""

# Check if we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo_color "$RED" "❌ This script is designed for macOS only!"
    exit 1
fi

# Check bash version (need 3.2+)
if [[ "${BASH_VERSION%%.*}" -lt 3 ]]; then
    echo_color "$RED" "❌ Bash 3.2+ required. Current version: $BASH_VERSION"
    exit 1
fi

# Get installation directory
INSTALL_DIR="$(pwd)"
if [[ ! -f "$INSTALL_DIR/scripts/monitor_instalacoes_final.sh" ]]; then
    echo_color "$RED" "❌ Installation script must be run from the project root directory"
    echo "   Make sure you're in the macos-security-monitor directory"
    exit 1
fi

echo_color "$GREEN" "✅ Environment check passed"
echo ""

# Make scripts executable
echo_color "$YELLOW" "🔧 Making scripts executable..."
chmod +x scripts/*.sh
echo_color "$GREEN" "✅ Scripts are now executable"
echo ""

# Test script syntax
echo_color "$YELLOW" "🔍 Testing script syntax..."
for script in scripts/*.sh; do
    if ! bash -n "$script"; then
        echo_color "$RED" "❌ Syntax error in $script"
        exit 1
    fi
done
echo_color "$GREEN" "✅ All scripts have valid syntax"
echo ""

# Create symlinks in /usr/local/bin for easy access (optional)
echo_color "$YELLOW" "🔗 Creating convenient command aliases..."

# Ask user if they want system-wide access
read -p "Create system-wide commands (requires sudo)? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v sudo >/dev/null 2>&1; then
        sudo ln -sf "$INSTALL_DIR/scripts/monitor_instalacoes_final.sh" /usr/local/bin/macos-security-monitor 2>/dev/null || true
        sudo ln -sf "$INSTALL_DIR/scripts/config_monitor.sh" /usr/local/bin/macos-security-config 2>/dev/null || true
        echo_color "$GREEN" "✅ System commands created:"
        echo "   • macos-security-monitor  (main monitoring script)"
        echo "   • macos-security-config   (configuration tool)"
    else
        echo_color "$YELLOW" "⚠️  sudo not available, skipping system commands"
    fi
else
    echo_color "$BLUE" "ℹ️  You can run scripts directly from: $INSTALL_DIR/scripts/"
fi
echo ""

# Test quick execution
echo_color "$YELLOW" "🧪 Testing quick mode execution..."
if timeout 60 env MONITOR_MODE=quick "$INSTALL_DIR/scripts/monitor_instalacoes_final.sh" >/dev/null 2>&1; then
    echo_color "$GREEN" "✅ Quick mode test successful"
else
    echo_color "$YELLOW" "⚠️  Quick mode test completed (may have warnings - check logs)"
fi
echo ""

# Show installation summary
echo_color "$GREEN" "🎉 Installation Complete!"
echo_color "$BLUE" "=========================="
echo ""
echo "📁 Installed in: $INSTALL_DIR"
echo ""
echo "🚀 Quick Start:"
echo "   1. Configure: ./scripts/config_monitor.sh"
echo "   2. Test run:  MONITOR_MODE=quick ./scripts/monitor_instalacoes_final.sh"
echo "   3. Full run:  ./scripts/monitor_instalacoes_final.sh"
echo ""

if command -v macos-security-monitor >/dev/null 2>&1; then
    echo "🌟 System commands available:"
    echo "   • macos-security-monitor  (from anywhere)"
    echo "   • macos-security-config   (from anywhere)"
    echo ""
fi

echo "📖 Documentation: docs/README_Monitor.md"
echo "🔧 Examples:      examples/"
echo "⚙️  Configuration: ./scripts/config_monitor.sh"
echo ""

# Offer to run configuration
read -p "Run interactive configuration now? [Y/n]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo_color "$BLUE" "🔧 Starting configuration..."
    echo ""
    "$INSTALL_DIR/scripts/config_monitor.sh"
else
    echo_color "$YELLOW" "💡 Run './scripts/config_monitor.sh' later to configure the monitor"
fi

echo ""
echo_color "$GREEN" "✨ macOS Security Monitor is ready to use!"
echo_color "$BLUE" "   Happy monitoring! 🛡️"