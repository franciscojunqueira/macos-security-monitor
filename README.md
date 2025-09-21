# macOS Security Monitor

🛡️ **Advanced security monitoring system for macOS** - Intelligent detection of critical system changes with optimized performance for low-memory Macs.

[![macOS](https://img.shields.io/badge/macOS-10.15+-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash_3.2+-yellow.svg)](https://www.gnu.org/software/bash/)

## 🚀 Features

- **🎯 Smart Monitoring Modes**: Quick (30s), Normal (2-3min), Full (5-10min)
- **📱 Intelligent Notifications**: Priority-based with smart grouping
- **💾 Memory Optimized**: ~50% less RAM usage with intelligent caching
- **🔔 Critical App Detection**: Automatic security app monitoring
- **📊 Log Rotation**: Automated compression and cleanup
- **⚙️ Interactive Configuration**: GUI setup with LaunchAgent automation
- **🔋 Battery Aware**: Auto-switches to economy mode on low battery

## 🛠 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/macos-security-monitor.git
cd macos-security-monitor

# Make scripts executable
chmod +x scripts/*.sh

# Run interactive configuration
./scripts/config_monitor.sh
```

### Basic Usage

```bash
# Quick monitoring (30 seconds)
MONITOR_MODE=quick ./scripts/monitor_instalacoes_final.sh

# Normal monitoring (2-3 minutes) - default
./scripts/monitor_instalacoes_final.sh

# Full deep analysis (5-10 minutes)
MONITOR_MODE=full ./scripts/monitor_instalacoes_final.sh
```

## 📁 Project Structure

```
macos-security-monitor/
├── scripts/
│   ├── monitor_instalacoes_final.sh      # Main optimized script
│   ├── config_monitor.sh                 # Interactive configuration tool
│   ├── monitor_instalacoes_otimizado.sh  # Intermediate optimized version
│   └── monitor_instalacoes_legacy.sh     # Original script (with fixes)
├── docs/
│   └── README_Monitor.md                 # Detailed documentation
├── examples/
│   ├── launchagent.plist                # LaunchAgent example
│   ├── configuration.env                # Environment variables example
│   └── critical_apps.txt                # Critical apps list example
└── .github/
    └── workflows/                        # CI/CD workflows
```

## 🎯 Monitoring Coverage

### 🔍 **Applications**
- Complete fingerprinting (Bundle ID, version, build, TeamID, hash)
- Critical security apps prioritized monitoring
- Automatic security app detection
- Intelligent caching for performance

### 🖥 **System Components**
- LaunchDaemons and LaunchAgents
- PrivilegedHelperTools
- System Extensions
- Configuration Profiles (MDM)
- SSH and Sudoers configuration
- System Configuration changes
- /etc/hosts modifications
- Firewall rules

### 📦 **Package Management**
- macOS packages (pkgutil)
- Homebrew packages
- Login Items

## 📊 Performance Comparison

| Metric | Original Script | Optimized Version | Improvement |
|--------|----------------|------------------|-------------|
| **Execution Time** | 4-6 min | 30s-3min | **40-80% faster** |
| **Memory Usage** | 200-300MB | 80-150MB | **~50% less RAM** |
| **Disk I/O** | High (always recalc) | Low (smart cache) | **~60% reduction** |
| **Critical Detection** | Same priority | Immediate | **Real-time** |

## ⚙️ Configuration

### Environment Variables

```bash
export MONITOR_MODE="quick"                    # quick|normal|full
export NOTIFICATION_FREQUENCY="2"             # Hours between grouped notifications
export ENABLE_GROUPED_NOTIFICATIONS="true"    # Group minor changes
export LOG_MAX_SIZE_MB="25"                   # Max log size (MB)
export LOG_ROTATION_COUNT="3"                 # Number of rotated logs to keep
export CRITICAL_APPS="/Applications/LuLu.app:/Applications/Little Snitch.app"
```

### Recommended Scenarios

#### Low-Memory Mac
```bash
export MONITOR_MODE="quick"
export NOTIFICATION_FREQUENCY="4"
export LOG_MAX_SIZE_MB="10"
# Runs every 2 hours in quick mode
```

#### Workstation
```bash
export MONITOR_MODE="normal"
export NOTIFICATION_FREQUENCY="1"
# Runs every 30 minutes in normal mode
```

#### Server/Deep Analysis
```bash
export MONITOR_MODE="full"
export NOTIFICATION_FREQUENCY="6"
# Runs twice daily with full analysis
```

## 🔔 Notification System

### Priority Levels
- **CRITICAL**: Security apps changed → Immediate notification
- **HIGH**: LaunchDaemons, helpers, new apps → High priority
- **MEDIUM**: App updates, configurations → Grouped
- **LOW**: Packages, login items → Grouped

### Smart Grouping
```
Monitor: 7 changes (2 important)
├── CRITICAL: 0
├── HIGH: 2  
├── MEDIUM: 3
└── LOW: 2
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup
```bash
# Fork the repository
git clone https://github.com/YOUR_USERNAME/macos-security-monitor.git
cd macos-security-monitor

# Create a feature branch
git checkout -b feature/your-feature-name

# Make your changes and test
./scripts/config_monitor.sh  # Test configuration
MONITOR_MODE=quick ./scripts/monitor_instalacoes_final.sh  # Test execution

# Commit and push
git add .
git commit -m "Add your feature description"
git push origin feature/your-feature-name
```

## 📝 Changelog

### v2.0.0 (2024-09-21)
- ✅ **Fixed integer expression errors** in original script
- 🎯 **Smart monitoring modes** (quick/normal/full)
- 💾 **Advanced caching system** (~50% memory reduction)
- 📱 **Intelligent notification system** with priority levels
- 📊 **Log rotation** with automatic compression
- ⚙️ **Interactive configuration** GUI
- 🔋 **Battery awareness** with automatic economy mode
- 🛡️ **Critical app detection** with prioritized monitoring

### v1.0.0 (Original)
- Basic macOS security monitoring
- Application fingerprinting
- System component monitoring
- Simple notification system

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🛡️ Security

This tool is designed to enhance your Mac's security by monitoring critical system changes. It:
- Runs with user privileges (no unnecessary sudo)
- Uses cache in user directory (not /tmp)
- Has built-in failsafes and error handling
- Includes automatic cleanup mechanisms

## 📞 Support

- 📖 **Documentation**: [docs/README_Monitor.md](docs/README_Monitor.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/YOUR_USERNAME/macos-security-monitor/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/YOUR_USERNAME/macos-security-monitor/discussions)

---

⭐ **If you find this project helpful, please consider giving it a star!**