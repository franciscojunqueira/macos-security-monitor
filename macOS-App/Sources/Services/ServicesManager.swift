import Foundation
import UserNotifications
import os.log

// MARK: - Configuration Manager

class ConfigurationManager: ObservableObject {
    static let shared = ConfigurationManager()
    
    @Published var configuration: MonitorConfiguration
    
    private let userDefaults = UserDefaults.standard
    private let configurationKey = "com.securitymonitor.configuration"
    
    private init() {
        self.configuration = MonitorConfiguration()
        loadConfiguration()
    }
    
    var isAutoScanEnabled: Bool {
        configuration.autoScanEnabled
    }
    
    var runAsMenuBarApp: Bool {
        configuration.runAsMenuBarApp
    }
    
    func loadConfiguration() {
        if let data = userDefaults.data(forKey: configurationKey),
           let loadedConfig = try? JSONDecoder().decode(MonitorConfiguration.self, from: data) {
            DispatchQueue.main.async {
                self.configuration = loadedConfig
            }
        }
    }
    
    func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            userDefaults.set(data, forKey: configurationKey)
        }
    }
    
    func updateScanMode(_ mode: ScanMode) {
        configuration.scanMode = mode
        saveConfiguration()
    }
    
    func toggleAutoScan() {
        configuration.autoScanEnabled.toggle()
        saveConfiguration()
    }
    
    func updateNotificationFrequency(_ frequency: MonitorConfiguration.NotificationFrequency) {
        configuration.notificationFrequency = frequency
        saveConfiguration()
    }
    
    func addCriticalApp(_ appPath: String) {
        if !configuration.criticalApps.contains(appPath) {
            configuration.criticalApps.append(appPath)
            saveConfiguration()
        }
    }
    
    func removeCriticalApp(_ appPath: String) {
        configuration.criticalApps.removeAll { $0 == appPath }
        saveConfiguration()
    }
}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecurityMonitor",
                               category: "NotificationManager")
    
    @Published var permissionGranted = false
    
    private init() {
        center.delegate = self
        checkPermissionStatus()
    }
    
    func requestPermissions() {
        center.requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { granted, error in
            DispatchQueue.main.async {
                self.permissionGranted = granted
                if let error = error {
                    self.logger.error("Failed to request notification permissions: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func checkPermissionStatus() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.permissionGranted = settings.authorizationStatus == .authorized || 
                                        settings.authorizationStatus == .provisional
            }
        }
    }
    
    func sendSecurityAlert(_ alert: SecurityAlert) {
        guard permissionGranted else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Security Alert"
        content.subtitle = alert.title
        content.body = alert.message
        content.categoryIdentifier = "SECURITY_ALERT"
        content.userInfo = ["alertId": alert.id.uuidString]
        
        // Set sound based on priority
        switch alert.priority {
        case .critical:
            content.sound = .defaultCritical
        case .high:
            content.sound = .default
        default:
            content.sound = nil
        }
        
        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil
        )
        
        center.add(request) { error in
            if let error = error {
                self.logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    func sendScanCompleteNotification(result: ScanResult) {
        guard permissionGranted else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Security Scan Complete"
        
        switch result.status {
        case .secure:
            content.body = "No security issues detected"
            content.sound = nil
        case .warning:
            content.body = "\(result.alerts.count) warning(s) detected"
            content.sound = .default
        case .critical:
            content.body = "\(result.alerts.count) critical issue(s) found!"
            content.sound = .defaultCritical
        default:
            content.body = "Scan completed"
            content.sound = nil
        }
        
        let request = UNNotificationRequest(
            identifier: "scan_complete_\(result.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        center.add(request)
    }
    
    func clearAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - Data Manager

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var scanHistory: [ScanResult] = []
    @Published var recentAlerts: [SecurityAlert] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecurityMonitor",
                               category: "DataManager")
    
    private let scanHistoryKey = "com.securitymonitor.scanHistory"
    private let maxHistoryItems = 100
    private let maxRecentAlerts = 50
    
    private init() {
        loadScanHistory()
        updateRecentAlerts()
    }
    
    func addScanResult(_ result: ScanResult) {
        DispatchQueue.main.async {
            self.scanHistory.insert(result, at: 0)
            
            // Keep only the most recent scans
            if self.scanHistory.count > self.maxHistoryItems {
                self.scanHistory = Array(self.scanHistory.prefix(self.maxHistoryItems))
            }
            
            // Add new alerts to recent alerts
            self.recentAlerts.insert(contentsOf: result.alerts, at: 0)
            if self.recentAlerts.count > self.maxRecentAlerts {
                self.recentAlerts = Array(self.recentAlerts.prefix(self.maxRecentAlerts))
            }
            
            self.saveScanHistory()
        }
    }
    
    func clearOldData() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        scanHistory.removeAll { $0.timestamp < thirtyDaysAgo }
        recentAlerts.removeAll { $0.timestamp < thirtyDaysAgo }
        
        saveScanHistory()
    }
    
    private func loadScanHistory() {
        if let data = UserDefaults.standard.data(forKey: scanHistoryKey),
           let history = try? JSONDecoder().decode([ScanResult].self, from: data) {
            DispatchQueue.main.async {
                self.scanHistory = history
                self.updateRecentAlerts()
            }
        }
    }
    
    private func saveScanHistory() {
        if let data = try? JSONEncoder().encode(scanHistory) {
            UserDefaults.standard.set(data, forKey: scanHistoryKey)
        }
    }
    
    private func updateRecentAlerts() {
        let allAlerts = scanHistory.flatMap { $0.alerts }
        recentAlerts = Array(allAlerts.sorted { $0.timestamp > $1.timestamp }.prefix(maxRecentAlerts))
    }
    
    // MARK: - Statistics
    
    var dashboardStats: DashboardStats {
        let totalScans = scanHistory.count
        let lastScan = scanHistory.first?.timestamp
        let averageDuration = scanHistory.isEmpty ? 0 : 
            scanHistory.map { $0.duration }.reduce(0, +) / Double(scanHistory.count)
        
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let weeklyAlerts = recentAlerts.filter { $0.timestamp > oneWeekAgo }
        let criticalWeeklyAlerts = weeklyAlerts.filter { $0.priority == .critical }
        
        return DashboardStats(
            totalScans: totalScans,
            lastScanDate: lastScan,
            averageScanTime: averageDuration,
            alertsThisWeek: weeklyAlerts.count,
            criticalAlertsThisWeek: criticalWeeklyAlerts.count,
            systemUptime: ProcessInfo.processInfo.systemUptime,
            monitoringDays: calculateMonitoringDays()
        )
    }
    
    private func calculateMonitoringDays() -> Int {
        guard let firstScan = scanHistory.last?.timestamp else { return 0 }
        let daysSince = Calendar.current.dateComponents([.day], from: firstScan, to: Date()).day ?? 0
        return max(1, daysSince)
    }
}

// MARK: - App State Manager

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentStatus: SecurityStatus = .unknown
    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?
    @Published var scanProgress: ScanProgress?
    
    private var scanTimer: Timer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecurityMonitor",
                               category: "AppState")
    
    private init() {
        updateStatusFromHistory()
    }
    
    func startScan(mode: ScanMode) {
        guard !isScanning else { return }
        
        isScanning = true
        currentStatus = .scanning
        scanProgress = ScanProgress(mode: mode)
        
        Task {
            do {
                let result = try await ScriptRunner.shared.runSecurityScan(
                    mode: mode, 
                    progress: scanProgress
                )
                
                await MainActor.run {
                    self.handleScanCompletion(result)
                }
            } catch {
                await MainActor.run {
                    self.handleScanError(error)
                }
            }
        }
    }
    
    private func handleScanCompletion(_ result: ScanResult) {
        isScanning = false
        currentStatus = result.status
        lastScanDate = result.timestamp
        
        // Save result
        DataManager.shared.addScanResult(result)
        
        // Send notifications
        NotificationManager.shared.sendScanCompleteNotification(result: result)
        
        // Send individual critical alerts
        for alert in result.alerts where alert.priority == .critical {
            NotificationManager.shared.sendSecurityAlert(alert)
        }
        
        logger.info("Scan completed with status: \(result.status.rawValue)")
    }
    
    private func handleScanError(_ error: Error) {
        isScanning = false
        currentStatus = .unknown
        
        logger.error("Scan failed: \(error.localizedDescription)")
        
        // Could show error notification here
    }
    
    func schedulePeriodicScan() {
        let interval = ConfigurationManager.shared.configuration.autoScanInterval
        
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.startScan(mode: ConfigurationManager.shared.configuration.scanMode)
        }
        
        logger.info("Scheduled periodic scans every \(interval) seconds")
    }
    
    func stopPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        logger.info("Stopped periodic scans")
    }
    
    private func updateStatusFromHistory() {
        guard let lastResult = DataManager.shared.scanHistory.first else {
            currentStatus = .unknown
            return
        }
        
        currentStatus = lastResult.status
        lastScanDate = lastResult.timestamp
    }
}

// MARK: - Notification Delegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              willPresent notification: UNNotification, 
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              didReceive response: UNNotificationResponse, 
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        if let alertId = response.notification.request.content.userInfo["alertId"] as? String {
            // Navigate to alert details or take action
            logger.info("User tapped notification for alert: \(alertId)")
        }
        
        completionHandler()
    }
}