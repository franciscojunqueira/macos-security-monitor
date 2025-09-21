import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var configurationManager: ConfigurationManager
    @StateObject private var dashboardViewModel = DashboardViewModel()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            DashboardView()
                .environmentObject(dashboardViewModel)
        }
        .navigationTitle("macOS Security Monitor")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Spacer()
                
                // Quick scan button in toolbar
                Button(action: { 
                    dashboardViewModel.startScan(mode: .quick) 
                }) {
                    Label("Quick Scan", systemImage: "bolt.fill")
                }
                .disabled(dashboardViewModel.isScanning)
                .keyboardShortcut("r", modifiers: .command)
                
                // Settings button
                Button(action: { 
                    // Open settings window
                }) {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SidebarItem = .dashboard
    
    enum SidebarItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case alerts = "Alerts"
        case reports = "Reports"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var systemImage: String {
            switch self {
            case .dashboard: return "house.fill"
            case .alerts: return "exclamationmark.triangle.fill"
            case .reports: return "chart.bar.fill"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        List(SidebarItem.allCases, selection: $selectedTab) { item in
            NavigationLink(value: item) {
                Label(item.rawValue, systemImage: item.systemImage)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Status Header
                StatusHeaderCard()
                
                // Scan Controls
                ScanControlsCard()
                
                // Statistics
                StatisticsCard()
                
                // Recent Alerts
                if !dashboardViewModel.recentAlerts.isEmpty {
                    RecentAlertsCard()
                }
            }
            .padding(24)
        }
        .background(Color(.controlBackgroundColor))
        .navigationTitle("Dashboard")
    }
}

// MARK: - Status Header Card

struct StatusHeaderCard: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        Card {
            HStack(spacing: 20) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(dashboardViewModel.statusColor.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: dashboardViewModel.statusIcon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(dashboardViewModel.statusColor)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(dashboardViewModel.statusMessage)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let lastScan = dashboardViewModel.lastScanDate {
                        Text("Last scan: \(dashboardViewModel.formatAlertTime(lastScan))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if dashboardViewModel.isScanning {
                        ScanProgressView()
                    } else {
                        Text(dashboardViewModel.nextScanMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Health Score
                SystemHealthIndicator()
            }
        }
    }
}

// MARK: - Scan Progress View

struct ScanProgressView: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = dashboardViewModel.scanProgress {
                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("Estimated: \(formatTimeRemaining(progress.estimatedTimeRemaining))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s remaining"
    }
}

// MARK: - System Health Indicator

struct SystemHealthIndicator: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: dashboardViewModel.systemHealthScore)
                    .stroke(dashboardViewModel.systemHealthColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: dashboardViewModel.systemHealthScore)
                
                Text("\(Int(dashboardViewModel.systemHealthScore * 100))")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(dashboardViewModel.systemHealthColor)
            }
            
            Text("Health Score")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Scan Controls Card

struct ScanControlsCard: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        Card {
            VStack(spacing: 16) {
                HStack {
                    Text("Security Scans")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: dashboardViewModel.toggleAutoScan) {
                        Label(
                            dashboardViewModel.configurationManager.isAutoScanEnabled ? "Auto-scan On" : "Auto-scan Off",
                            systemImage: dashboardViewModel.configurationManager.isAutoScanEnabled ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(dashboardViewModel.configurationManager.isAutoScanEnabled ? .green : .secondary)
                }
                
                HStack(spacing: 12) {
                    ForEach(ScanMode.allCases) { mode in
                        ScanButton(
                            mode: mode,
                            isScanning: dashboardViewModel.isScanning,
                            action: { dashboardViewModel.startScan(mode: mode) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Scan Button

struct ScanButton: View {
    let mode: ScanMode
    let isScanning: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: mode.systemImage)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 2) {
                    Text(mode.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(mode.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
        .opacity(isScanning ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isScanning)
    }
}

// MARK: - Statistics Card

struct StatisticsCard: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("System Overview")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let stats = dashboardViewModel.dashboardStats {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        StatItem(title: "Total Scans", value: "\(stats.totalScans)", icon: "magnifyingglass.circle")
                        StatItem(title: "Avg. Scan Time", value: stats.averageScanTimeFormatted, icon: "clock")
                        StatItem(title: "Alerts This Week", value: "\(stats.alertsThisWeek)", icon: "exclamationmark.triangle")
                        StatItem(title: "Critical Alerts", value: "\(stats.criticalAlertsThisWeek)", icon: "xmark.shield", color: .red)
                        StatItem(title: "System Uptime", value: stats.formattedUptime, icon: "power")
                        StatItem(title: "Monitoring Days", value: "\(stats.monitoringDays)", icon: "calendar")
                    }
                } else {
                    Text("No data available")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .accentColor
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Recent Alerts Card

struct RecentAlertsCard: View {
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Recent Alerts")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if dashboardViewModel.shouldShowAlertsBadge {
                        Badge("\(dashboardViewModel.criticalAlertsCount)")
                            .foregroundColor(.red)
                    }
                }
                
                LazyVStack(spacing: 8) {
                    ForEach(dashboardViewModel.recentAlerts) { alert in
                        AlertRow(alert: alert)
                    }
                }
            }
        }
    }
}

// MARK: - Alert Row

struct AlertRow: View {
    let alert: SecurityAlert
    @EnvironmentObject var dashboardViewModel: DashboardViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Priority indicator
            Circle()
                .fill(alert.priority.color)
                .frame(width: 8, height: 8)
            
            // Alert content
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(alert.shortDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Time stamp
            Text(dashboardViewModel.formatAlertTime(alert.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(alert.priority.color.opacity(0.05))
        )
    }
}

// MARK: - Support Views

struct Card<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
    }
}

struct Badge: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.red)
            )
            .foregroundColor(.white)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .environmentObject(ConfigurationManager.shared)
        .environmentObject(NotificationManager.shared)
}