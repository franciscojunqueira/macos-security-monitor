# LaunchAgent Installation Instructions

## Overview
This guide explains how to install the macOS Security Monitor as a LaunchAgent to run automatically in the background.

## Installation Steps

### 1. Copy the plist file
```bash
cp examples/launchagent.plist ~/Library/LaunchAgents/com.user.macos-security-monitor.plist
```

### 2. Update the paths in the copied file
Edit `~/Library/LaunchAgents/com.user.macos-security-monitor.plist` and replace:
- `/path/to/your/scripts/` with the actual path to your scripts directory
- `YOUR_USERNAME` with your actual macOS username

### 3. Load the LaunchAgent
```bash
launchctl load ~/Library/LaunchAgents/com.user.macos-security-monitor.plist
```

### 4. Verify installation
```bash
launchctl list | grep com.user.macos-security-monitor
```

### 5. Unload (if needed)
```bash
launchctl unload ~/Library/LaunchAgents/com.user.macos-security-monitor.plist
```

## Configuration
The LaunchAgent is configured to:
- Run every 30 minutes (1800 seconds)
- Log to `~/Library/Application Support/monitor_instalacoes/logs/`
- Only run when user is logged in (Aqua session)
- Run in background mode

## Troubleshooting
- Check logs in `~/Library/Application Support/monitor_instalacoes/logs/`
- Ensure script has execute permissions: `chmod +x /path/to/your/scripts/monitor_instalacoes_final.sh`
- Verify paths are correct in the plist file