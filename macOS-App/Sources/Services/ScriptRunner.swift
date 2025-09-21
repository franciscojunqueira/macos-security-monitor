import Foundation
import os.log

/// Service responsible for executing security monitoring scripts
class ScriptRunner: ObservableObject {
    static let shared = ScriptRunner()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecurityMonitor", 
                               category: "ScriptRunner")
    private let scriptQueue = DispatchQueue(label: "com.securitymonitor.scripts", qos: .userInitiated)
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Execute security monitoring script with specified mode
    func runSecurityScan(mode: ScanMode, progress: ScanProgress? = nil) async throws -> ScanResult {
        logger.info("Starting security scan with mode: \(mode.rawValue)")
        
        progress?.start()
        
        return try await withCheckedThrowingContinuation { continuation in
            scriptQueue.async {
                do {
                    let result = try self.executeScript(mode: mode, progress: progress)
                    continuation.resume(returning: result)
                } catch {
                    self.logger.error("Script execution failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Test script availability and permissions
    func validateScriptEnvironment() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            scriptQueue.async {
                do {
                    let isValid = try self.checkScriptPermissions()
                    continuation.resume(returning: isValid)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func executeScript(mode: ScanMode, progress: ScanProgress?) throws -> ScanResult {
        let startTime = Date()
        
        // Get script path from bundle
        guard let scriptPath = Bundle.main.path(forResource: "monitor_instalacoes_final", 
                                              ofType: "sh", 
                                              inDirectory: "Resources/scripts") else {
            throw ScriptError.scriptNotFound("monitor_instalacoes_final.sh")
        }
        
        // Setup process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        
        // Setup environment
        var environment = ProcessInfo.processInfo.environment
        environment["MONITOR_MODE"] = mode.rawValue
        environment["NOTIFICATION_FREQUENCY"] = "0" // Disable script notifications
        environment["ENABLE_GROUPED_NOTIFICATIONS"] = "false"
        environment["OUTPUT_FORMAT"] = "json" // Request JSON output if supported
        process.environment = environment
        
        // Setup pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Start process
        try process.run()
        
        // Monitor progress if provided
        if let progress = progress {
            monitorScriptProgress(process: process, progress: progress, mode: mode)
        }
        
        // Wait for completion
        process.waitUntilExit()
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Check exit status
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ScriptError.executionFailed(errorMessage)
        }
        
        // Parse output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let outputString = String(data: outputData, encoding: .utf8) else {
            throw ScriptError.invalidOutput("Could not decode script output")
        }
        
        progress?.complete()
        
        return try parseScriptOutput(output: outputString, mode: mode, duration: duration)
    }
    
    private func monitorScriptProgress(process: Process, progress: ScanProgress, mode: ScanMode) {
        let timer = Timer.scheduledTimer(withTimeInterval: mode.expectedDuration / 8, repeats: true) { timer in
            if process.isRunning {
                DispatchQueue.main.async {
                    progress.nextPhase()
                }
            } else {
                timer.invalidate()
            }
        }
        
        // Cleanup timer when process completes
        DispatchQueue.global().async {
            process.waitUntilExit()
            DispatchQueue.main.async {
                timer.invalidate()
            }
        }
    }
    
    private func parseScriptOutput(output: String, mode: ScanMode, duration: TimeInterval) throws -> ScanResult {
        // For now, we'll parse the existing script output format
        // In a real implementation, we'd modify the scripts to output structured JSON
        
        let alerts = try parseAlertsFromOutput(output)
        let statistics = try parseStatisticsFromOutput(output)
        let systemSnapshot = try parseSystemSnapshotFromOutput(output)
        
        return ScanResult(
            timestamp: Date(),
            mode: mode,
            duration: duration,
            alerts: alerts,
            statistics: statistics,
            systemSnapshot: systemSnapshot
        )
    }
    
    private func parseAlertsFromOutput(_ output: String) throws -> [SecurityAlert] {
        var alerts: [SecurityAlert] = []
        
        // Parse different types of changes from script output
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if let alert = parseAlertLine(line) {
                alerts.append(alert)
            }
        }
        
        return alerts
    }
    
    private func parseAlertLine(_ line: String) -> SecurityAlert? {
        // Simplified parsing - in production, this would be more robust
        if line.contains("CRITICAL") && line.contains("app") {
            return SecurityAlert(
                timestamp: Date(),
                priority: .critical,
                category: .application,
                title: "Critical Application Change",
                message: line,
                details: nil,
                affectedPath: extractPath(from: line),
                recommendedAction: "Review application changes immediately"
            )
        } else if line.contains("LaunchAgent") {
            return SecurityAlert(
                timestamp: Date(),
                priority: .high,
                category: .launchAgent,
                title: "Launch Agent Change",
                message: line,
                details: nil,
                affectedPath: extractPath(from: line),
                recommendedAction: "Verify launch agent legitimacy"
            )
        }
        // Add more parsing logic for other alert types
        
        return nil
    }
    
    private func extractPath(from line: String) -> String? {
        // Extract file paths from output lines
        let pathPattern = #"(/[^\s]+\.(?:app|plist|pkg))"#
        if let regex = try? NSRegularExpression(pattern: pathPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            return String(line[Range(match.range, in: line)!])
        }
        return nil
    }
    
    private func parseStatisticsFromOutput(_ output: String) throws -> ScanStatistics {
        // Parse statistics from script output
        // This would be replaced with proper JSON parsing in production
        
        return ScanStatistics(
            totalApplications: countMatches(in: output, pattern: "app"),
            criticalApplications: countMatches(in: output, pattern: "critical.*app"),
            launchAgents: countMatches(in: output, pattern: "LaunchAgent"),
            launchDaemons: countMatches(in: output, pattern: "LaunchDaemon"),
            systemExtensions: countMatches(in: output, pattern: "SystemExtension"),
            configurationProfiles: countMatches(in: output, pattern: "ConfigurationProfile"),
            packages: countMatches(in: output, pattern: "package"),
            loginItems: countMatches(in: output, pattern: "LoginItem")
        )
    }
    
    private func parseSystemSnapshotFromOutput(_ output: String) throws -> SystemSnapshot {
        // Parse system information from script output
        return SystemSnapshot(
            macOSVersion: getMacOSVersion(),
            systemIntegrityProtection: checkSIP(),
            gatekeeper: checkGatekeeper(),
            firewall: checkFirewall(),
            automaticUpdates: checkAutomaticUpdates(),
            timestamp: Date()
        )
    }
    
    private func countMatches(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return 0
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
    
    private func checkScriptPermissions() throws -> Bool {
        guard let scriptPath = Bundle.main.path(forResource: "monitor_instalacoes_final", 
                                              ofType: "sh", 
                                              inDirectory: "Resources/scripts") else {
            throw ScriptError.scriptNotFound("monitor_instalacoes_final.sh")
        }
        
        let fileManager = FileManager.default
        return fileManager.isExecutableFile(atPath: scriptPath)
    }
    
    // MARK: - System Information Helpers
    
    private func getMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private func checkSIP() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("enabled")
        } catch {
            return false
        }
    }
    
    private func checkGatekeeper() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--status"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func checkFirewall() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        process.arguments = ["--getglobalstate"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("enabled")
        } catch {
            return false
        }
    }
    
    private func checkAutomaticUpdates() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "/Library/Preferences/com.apple.SoftwareUpdate", "AutomaticCheckEnabled"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        } catch {
            return false
        }
    }
}

// MARK: - Error Types

enum ScriptError: LocalizedError {
    case scriptNotFound(String)
    case executionFailed(String)
    case invalidOutput(String)
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let script):
            return "Script not found: \(script)"
        case .executionFailed(let message):
            return "Script execution failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid script output: \(message)"
        case .permissionDenied:
            return "Permission denied to execute security scripts"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .scriptNotFound:
            return "Ensure the security monitoring scripts are included in the app bundle."
        case .executionFailed:
            return "Check system permissions and try again."
        case .invalidOutput:
            return "The security script may need to be updated."
        case .permissionDenied:
            return "Grant necessary permissions in System Preferences > Security & Privacy."
        }
    }
}