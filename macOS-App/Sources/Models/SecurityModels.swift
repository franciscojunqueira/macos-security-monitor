import Foundation
import SwiftUI

// MARK: - Core Models

/// Represents different types of security scans
enum ScanMode: String, CaseIterable, Identifiable {
    case quick = "quick"
    case normal = "normal"
    case full = "full"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .quick: return "Quick Scan"
        case .normal: return "Normal Scan"
        case .full: return "Deep Scan"
        }
    }
    
    var description: String {
        switch self {
        case .quick: return "Critical apps only (~30s)"
        case .normal: return "Complete analysis (~2-3min)"
        case .full: return "Deep forensic scan (~5-10min)"
        }
    }
    
    var systemImage: String {
        switch self {
        case .quick: return "bolt.fill"
        case .normal: return "magnifyingglass.circle.fill"
        case .full: return "scope"
        }
    }
    
    var expectedDuration: TimeInterval {
        switch self {
        case .quick: return 30
        case .normal: return 150
        case .full: return 450
        }
    }
}

/// Represents the security status of the system
enum SecurityStatus: String, Codable {
    case secure = "secure"
    case warning = "warning"
    case critical = "critical"
    case scanning = "scanning"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .secure: return "System Secure"
        case .warning: return "Warnings Detected"
        case .critical: return "Critical Issues"
        case .scanning: return "Scanning..."
        case .unknown: return "Status Unknown"
        }
    }
    
    var color: Color {
        switch self {
        case .secure: return .green
        case .warning: return .orange
        case .critical: return .red
        case .scanning: return .blue
        case .unknown: return .gray
        }
    }
    
    var systemImage: String {
        switch self {
        case .secure: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.shield.fill"
        case .scanning: return "magnifyingglass"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

/// Represents priority levels for security alerts
enum AlertPriority: String, Codable, CaseIterable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    
    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
    
    var weight: Int {
        switch self {
        case .critical: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
}

// MARK: - Security Alert Model

struct SecurityAlert: Identifiable, Codable, Hashable {
    let id = UUID()
    let timestamp: Date
    let priority: AlertPriority
    let category: AlertCategory
    let title: String
    let message: String
    let details: String?
    let affectedPath: String?
    let recommendedAction: String?
    
    var isRecent: Bool {
        Date().timeIntervalSince(timestamp) < 3600 // Last hour
    }
    
    var shortDescription: String {
        if message.count > 60 {
            return String(message.prefix(57)) + "..."
        }
        return message
    }
}

enum AlertCategory: String, Codable, CaseIterable {
    case application = "application"
    case launchAgent = "launch_agent"
    case launchDaemon = "launch_daemon"
    case systemExtension = "system_extension"
    case configurationProfile = "configuration_profile"
    case systemConfiguration = "system_configuration"
    case package = "package"
    case loginItem = "login_item"
    
    var displayName: String {
        switch self {
        case .application: return "Applications"
        case .launchAgent: return "Launch Agents"
        case .launchDaemon: return "Launch Daemons"
        case .systemExtension: return "System Extensions"
        case .configurationProfile: return "Configuration Profiles"
        case .systemConfiguration: return "System Configuration"
        case .package: return "Packages"
        case .loginItem: return "Login Items"
        }
    }
    
    var systemImage: String {
        switch self {
        case .application: return "app.badge"
        case .launchAgent: return "gear.circle"
        case .launchDaemon: return "gearshape.2"
        case .systemExtension: return "puzzlepiece.extension"
        case .configurationProfile: return "doc.text.magnifyingglass"
        case .systemConfiguration: return "slider.horizontal.3"
        case .package: return "shippingbox"
        case .loginItem: return "person.crop.circle.badge.plus"
        }
    }
}

// MARK: - Scan Result Model

struct ScanResult: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let mode: ScanMode
    let duration: TimeInterval
    let alerts: [SecurityAlert]
    let statistics: ScanStatistics
    let systemSnapshot: SystemSnapshot
    
    var status: SecurityStatus {
        let criticalCount = alerts.filter { $0.priority == .critical }.count
        let highCount = alerts.filter { $0.priority == .high }.count
        
        if criticalCount > 0 { return .critical }
        if highCount > 0 { return .warning }
        return .secure
    }
    
    var alertsByCategory: [AlertCategory: [SecurityAlert]] {
        Dictionary(grouping: alerts, by: { $0.category })
    }
}

struct ScanStatistics: Codable {
    let totalApplications: Int
    let criticalApplications: Int
    let launchAgents: Int
    let launchDaemons: Int
    let systemExtensions: Int
    let configurationProfiles: Int
    let packages: Int
    let loginItems: Int
    
    var totalItems: Int {
        totalApplications + launchAgents + launchDaemons + 
        systemExtensions + configurationProfiles + packages + loginItems
    }
}

struct SystemSnapshot: Codable {
    let macOSVersion: String
    let systemIntegrityProtection: Bool
    let gatekeeper: Bool
    let firewall: Bool
    let automaticUpdates: Bool
    let timestamp: Date
}

// MARK: - Configuration Models

struct MonitorConfiguration: Codable {
    var scanMode: ScanMode = .normal
    var autoScanEnabled: Bool = true
    var autoScanInterval: TimeInterval = 1800 // 30 minutes
    var notificationFrequency: NotificationFrequency = .immediate
    var criticalApps: [String] = []
    var enabledCategories: Set<AlertCategory> = Set(AlertCategory.allCases)
    var runAsMenuBarApp: Bool = false
    var enableSounds: Bool = true
    var logMaxSizeMB: Int = 50
    var logRotationCount: Int = 5
    
    enum NotificationFrequency: String, Codable, CaseIterable {
        case immediate = "immediate"
        case hourly = "hourly"
        case daily = "daily"
        case disabled = "disabled"
        
        var displayName: String {
            switch self {
            case .immediate: return "Immediate"
            case .hourly: return "Hourly Summary"
            case .daily: return "Daily Summary"
            case .disabled: return "Disabled"
            }
        }
        
        var interval: TimeInterval? {
            switch self {
            case .immediate: return nil
            case .hourly: return 3600
            case .daily: return 86400
            case .disabled: return nil
            }
        }
    }
}

// MARK: - Dashboard Statistics

struct DashboardStats: Identifiable {
    let id = UUID()
    let totalScans: Int
    let lastScanDate: Date?
    let averageScanTime: TimeInterval
    let alertsThisWeek: Int
    let criticalAlertsThisWeek: Int
    let systemUptime: TimeInterval
    let monitoringDays: Int
    
    var formattedUptime: String {
        let hours = Int(systemUptime) / 3600
        let days = hours / 24
        
        if days > 0 {
            return "\(days)d \(hours % 24)h"
        } else {
            return "\(hours)h"
        }
    }
    
    var averageScanTimeFormatted: String {
        let minutes = Int(averageScanTime) / 60
        let seconds = Int(averageScanTime) % 60
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - Progress Tracking

class ScanProgress: ObservableObject {
    @Published var isScanning: Bool = false
    @Published var currentPhase: String = ""
    @Published var progress: Double = 0.0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    
    private var startTime: Date?
    private let phases: [String]
    private var currentPhaseIndex: Int = 0
    
    init(mode: ScanMode) {
        switch mode {
        case .quick:
            phases = ["Loading critical apps...", "Scanning applications...", "Analyzing results..."]
        case .normal:
            phases = ["Initializing scan...", "Scanning applications...", "Checking launch agents...", 
                     "Analyzing system...", "Processing results..."]
        case .full:
            phases = ["Preparing deep scan...", "Scanning applications...", "Checking launch agents...", 
                     "Checking launch daemons...", "Analyzing system extensions...", 
                     "Checking configuration profiles...", "Scanning packages...", 
                     "Processing comprehensive results..."]
        }
    }
    
    func start() {
        isScanning = true
        startTime = Date()
        currentPhaseIndex = 0
        updatePhase()
    }
    
    func nextPhase() {
        guard currentPhaseIndex < phases.count - 1 else { return }
        currentPhaseIndex += 1
        updatePhase()
    }
    
    func complete() {
        progress = 1.0
        currentPhase = "Scan completed"
        
        // Add small delay for UI feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isScanning = false
            self.progress = 0.0
            self.currentPhase = ""
        }
    }
    
    private func updatePhase() {
        currentPhase = phases[currentPhaseIndex]
        progress = Double(currentPhaseIndex) / Double(phases.count)
        
        if let startTime = startTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let estimatedTotal = elapsed / progress
            estimatedTimeRemaining = max(0, estimatedTotal - elapsed)
        }
    }
}