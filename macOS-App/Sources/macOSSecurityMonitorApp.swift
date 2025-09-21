import SwiftUI
import UserNotifications

@main
struct macOSSecurityMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var configurationManager = ConfigurationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(configurationManager)
                .environmentObject(notificationManager)
                .onAppear {
                    setupApplication()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            MenuCommands()
        }
        
        // Menu bar extra
        MenuBarExtra("Security Monitor", systemImage: "shield.checkered") {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(configurationManager)
        }
    }
    
    private func setupApplication() {
        // Request notification permissions
        notificationManager.requestPermissions()
        
        // Load saved configuration
        configurationManager.loadConfiguration()
        
        // Setup periodic scanning if enabled
        if configurationManager.isAutoScanEnabled {
            appState.schedulePeriodicScan()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon if running as menu bar only app
        if ConfigurationManager.shared.runAsMenuBarApp {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window is closed if running as menu bar app
        return !ConfigurationManager.shared.runAsMenuBarApp
    }
}