import SwiftUI
import AVFoundation
import UserNotifications
#if os(macOS)
import AppKit

/// macOS 单实例单窗口管理器（拦截通知点击与Dock唤起，防止反复弹出多余窗口）
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 1. 启动即刻同步注册通知中心代理，防止系统找不到代理而通过 LaunchServices 再次唤起新进程
        UNUserNotificationCenter.current().delegate = self
        
        // 2. 强制单实例检查：如果已有同进程在运行，激活旧进程并优雅退出当前新进程
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.stnts.PiPTicker"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let otherApps = runningApps.filter { $0.processIdentifier != currentPID }
        
        if let existingApp = otherApps.first {
            existingApp.activate(options: [.activateIgnoringOtherApps])
            exit(0)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 当点击通知横幅或Dock图标时，直接复用并激活当前主窗口，坚决不新建第二个窗口！
        if let mainWindow = sender.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) ?? sender.windows.first(where: { !($0 is NSPanel) }) {
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
                mainWindow.makeKeyAndOrderFront(nil)
                mainWindow.orderFrontRegardless()
            }
            
            if let newsId = userInfo["newsId"] as? String {
                FinancialNewsManager.shared.locateAndOpenNewsDetail(newsId: newsId)
            }
        }
        completionHandler()
    }
}
#endif

@main
struct PiPTickerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    init() {
        // 在 App 启动时设置音频后台通道
        AudioSessionManager.shared.setupAudioSession()
    }
    
    var body: some Scene {
        #if os(macOS)
        Window("PiPTicker", id: "MainWindow") {
            ContentView()
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 880, height: 620)
        .handlesExternalEvents(matching: [])
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
