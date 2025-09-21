import SwiftUI
import Combine
import os.log

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var securityStatus: SecurityStatus = .unknown
    @Published var isScanning: Bool = false
    @Published var dashboardStats: DashboardStats?
    @Published var recentAlerts: [SecurityAlert] = []
    @Published var scanProgress: ScanProgress?
    @Published var lastScanDate: Date?
    
    // MARK: - Dependencies
    private let appState = AppState.shared
    private let dataManager = DataManager.shared
    private let configurationManager = ConfigurationManager.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecurityMonitor", 
                               category: "DashboardViewModel")
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    
    // MARK: - Initialization
    init() {
        setupBindings()
        refreshData()
        startPeriodicRefresh()
    }
    
    // MARK: - Public Methods
    
    func startScan(mode: ScanMode) {
        guard !isScanning else { return }
        
        logger.info("Starting \(mode.rawValue) scan from dashboard")
        appState.startScan(mode: mode)
    }
    
    func refreshData() {
        securityStatus = appState.currentStatus
        lastScanDate = appState.lastScanDate
        dashboardStats = dataManager.dashboardStats
        recentAlerts = Array(dataManager.recentAlerts.prefix(5)) // Show only recent 5
    }
    
    func toggleAutoScan() {
        configurationManager.toggleAutoScan()
        
        if configurationManager.isAutoScanEnabled {
            appState.schedulePeriodicScan()
        } else {
            appState.stopPeriodicScan()
        }
        
        logger.info("Auto-scan toggled: \(configurationManager.isAutoScanEnabled)")
    }
    
    // MARK: - Computed Properties
    
    var statusIcon: String {
        securityStatus.systemImage
    }
    
    var statusColor: Color {
        securityStatus.color
    }
    
    var statusMessage: String {
        if isScanning {
            return scanProgress?.currentPhase ?? "Scanning..."
        }
        return securityStatus.displayName
    }
    
    var nextScanMessage: String {
        if !configurationManager.isAutoScanEnabled {
            return "Auto-scan disabled"
        }
        
        guard let lastScan = lastScanDate else {
            return "No previous scan"
        }
        
        let nextScanTime = lastScan.addingTimeInterval(configurationManager.configuration.autoScanInterval)
        let timeUntilNext = nextScanTime.timeIntervalSinceNow
        
        if timeUntilNext <= 0 {
            return "Scan due now"
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return "Next scan in \(formatter.string(from: timeUntilNext) ?? "unknown")"
    }
    
    var criticalAlertsCount: Int {
        recentAlerts.filter { $0.priority == .critical && $0.isRecent }.count
    }
    
    var shouldShowAlertsBadge: Bool {
        criticalAlertsCount > 0
    }
    
    var systemHealthScore: Double {
        guard let stats = dashboardStats else { return 0.0 }
        
        // Calculate health score based on recent activity
        let baseScore = 1.0
        let criticalPenalty = Double(stats.criticalAlertsThisWeek) * 0.2
        let warningPenalty = Double(stats.alertsThisWeek - stats.criticalAlertsThisWeek) * 0.05
        
        let score = max(0.0, min(1.0, baseScore - criticalPenalty - warningPenalty))
        return score
    }
    
    var systemHealthColor: Color {
        let score = systemHealthScore
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .red
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Bind to app state changes
        appState.$currentStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$securityStatus)
        
        appState.$isScanning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScanning)
        
        appState.$scanProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$scanProgress)
        
        appState.$lastScanDate
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastScanDate)
        
        // Bind to data manager changes
        dataManager.$recentAlerts
            .receive(on: DispatchQueue.main)
            .map { Array($0.prefix(5)) }
            .assign(to: &$recentAlerts)
        
        // Update dashboard stats when scan history changes
        dataManager.$scanHistory
            .receive(on: DispatchQueue.main)
            .map { _ in self.dataManager.dashboardStats }
            .assign(to: &$dashboardStats)
    }
    
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                self.refreshData()
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
}

// MARK: - Alert Formatting Helpers

extension DashboardViewModel {
    func formatAlertTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
    
    func getRecommendedScanMode() -> ScanMode {
        // Recommend scan mode based on system state and recent activity
        if criticalAlertsCount > 0 {
            return .full // Deep scan if critical issues detected
        }
        
        if let stats = dashboardStats, stats.alertsThisWeek > 10 {
            return .normal // Normal scan if many alerts
        }
        
        return .quick // Default to quick scan
    }
}