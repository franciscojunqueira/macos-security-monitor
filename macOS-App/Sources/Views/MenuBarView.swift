import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var configurationManager: ConfigurationManager
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status Section
            StatusSection()
            
            Divider()
            
            // Quick Actions
            QuickActionsSection()
            
            Divider()
            
            // Settings & Info
            SettingsSection()
        }
        .padding(8)
        .frame(width: 280)
    }
}

// MARK: - Status Section

struct StatusSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: appState.currentStatus.systemImage)
                    .foregroundColor(appState.currentStatus.color)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(appState.currentStatus.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                if appState.isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            if let lastScan = appState.lastScanDate {
                Text("Last scan: \(formatRelativeTime(lastScan))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                MenuBarButton(
                    title: "Quick Scan",
                    icon: "bolt.fill",
                    isEnabled: !appState.isScanning,
                    action: { appState.startScan(mode: .quick) }
                )
                
                MenuBarButton(
                    title: "Normal Scan", 
                    icon: "magnifyingglass.circle.fill",
                    isEnabled: !appState.isScanning,
                    action: { appState.startScan(mode: .normal) }
                )
                
                MenuBarButton(
                    title: "Deep Scan",
                    icon: "scope",
                    isEnabled: !appState.isScanning,
                    action: { appState.startScan(mode: .full) }
                )
            }
        }
    }
}

// MARK: - Settings Section

struct SettingsSection: View {
    @EnvironmentObject var configurationManager: ConfigurationManager
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuBarButton(
                title: "Open Dashboard",
                icon: "house.fill",
                action: { openWindow(id: "main") }
            )
            
            MenuBarButton(
                title: configurationManager.isAutoScanEnabled ? "Disable Auto-scan" : "Enable Auto-scan",
                icon: configurationManager.isAutoScanEnabled ? "pause.circle" : "play.circle",
                action: { 
                    configurationManager.toggleAutoScan()
                    if configurationManager.isAutoScanEnabled {
                        AppState.shared.schedulePeriodicScan()
                    } else {
                        AppState.shared.stopPeriodicScan()
                    }
                }
            )
            
            Divider()
            
            MenuBarButton(
                title: "Quit Security Monitor",
                icon: "power",
                action: { NSApplication.shared.terminate(nil) }
            )
        }
    }
}

// MARK: - Menu Bar Button

struct MenuBarButton: View {
    let title: String
    let icon: String
    var isEnabled: Bool = true
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
        )
        .onHover { isHovered in
            if isEnabled && isHovered {
                // Add hover effect if needed
            }
        }
    }
}