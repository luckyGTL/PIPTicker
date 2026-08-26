import SwiftUI
import AVFoundation
import UserNotifications
#if os(macOS)
import AppKit

/// 全局跨进程排他锁守卫（确保即使通过 LaunchServices、Finder、通知中心唤起，也绝不可能运行第二个进程）
final class SingleInstanceGuard {
    private static var isLocked = false
    private static var lockFD: Int32 = -1
    private static let lockFilePath = "/private/tmp/com.stnts.PiPTicker.lock"
    
    /// 在 App 启动最早期执行（早于 UI 和事件循环），如有旧实例直接激活旧实例并自杀
    @discardableResult
    static func enforceSingleInstance() -> Bool {
        guard !isLocked else { return true }
        
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.stnts.PiPTicker"
        
        // 1. 通过 NSWorkspace 全局扫描所有正在运行的应用
        let allApps = NSWorkspace.shared.runningApplications
        let otherApps = allApps.filter { app in
            app.processIdentifier != myPID &&
            !app.isTerminated &&
            (app.bundleIdentifier == bundleID ||
             app.localizedName == "PiPTicker" ||
             app.executableURL?.lastPathComponent == "PiPTicker")
        }
        if let existingApp = otherApps.first {
            NSLog("🔴 [PiPTicker] 发现已有实例 PID=\(existingApp.processIdentifier)，激活旧实例并立即退出当前进程 PID=\(myPID)")
            existingApp.activate(options: [.activateIgnoringOtherApps])
            _exit(0)
        }
        
        // 2. 文件锁双重保护（防止新启动应用尚未在 NSWorkspace 中登记）
        lockFD = open(lockFilePath, O_CREAT | O_RDWR, 0o666)
        if lockFD >= 0 {
            let result = flock(lockFD, LOCK_EX | LOCK_NB)
            if result != 0 {
                NSLog("🔴 [PiPTicker] 文件锁被占用，退出当前重复实例 PID=\(myPID)")
                // 尝试从文件读取主 PID 并激活
                var buffer = [CChar](repeating: 0, count: 32)
                let bytesRead = read(lockFD, &buffer, 31)
                if bytesRead > 0 {
                    let pidString = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let masterPID = pid_t(pidString), masterPID > 0, let masterApp = NSRunningApplication(processIdentifier: masterPID) {
                        masterApp.activate(options: [.activateIgnoringOtherApps])
                    }
                }
                _exit(0)
            }
            ftruncate(lockFD, 0)
            lseek(lockFD, 0, SEEK_SET)
            let myPIDString = "\(myPID)\n"
            myPIDString.withCString { ptr in
                _ = write(lockFD, ptr, strlen(ptr))
            }
        }
        
        isLocked = true
        NSLog("🔵 [PiPTicker] 唯一主实例初始化成功 ✅ PID=\(myPID)")
        return true
    }
    
    static func releaseLock() {
        if lockFD >= 0 {
            flock(lockFD, LOCK_UN)
            close(lockFD)
            lockFD = -1
            isLocked = false
        }
    }
}

/// macOS 单实例单窗口管理器 — 窗口由 AppDelegate 手动创建，绝无多窗口
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    
    /// 由我们手动创建的唯一主窗口
    var mainWindow: NSWindow?
    
    override init() {
        super.init()
        // 最早阶段执行单实例检查
        SingleInstanceGuard.enforceSingleInstance()
        // 最早阶段绑定通知中心 Delegate
        UNUserNotificationCenter.current().delegate = self
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UNUserNotificationCenter.current().delegate = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("🔵 [PiPTicker] applicationDidFinishLaunching — 初始化主窗口")
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
        
        createMainWindowIfNeeded()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSLog("🔵 [PiPTicker] applicationShouldHandleReopen — hasVisibleWindows=\(flag)")
        activateMainWindow()
        return false
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        SingleInstanceGuard.releaseLock()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // macOS 前台时：播放声音与角标，App 内自选弹窗负责展示，不重复弹系统横幅
        completionHandler([.sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        NSLog("🟢 [PiPTicker] didReceive 通知点击! identifier=\(response.notification.request.identifier)")
        
        DispatchQueue.main.async { [weak self] in
            self?.activateMainWindow()
            
            if let newsId = userInfo["newsId"] as? String {
                NSLog("🟢 [PiPTicker] 定位到 newsId=\(newsId)")
                FinancialNewsManager.shared.locateAndOpenNewsDetail(newsId: newsId)
            }
        }
        completionHandler()
    }
    
    // MARK: - NSWindowDelegate
    
    /// Command+W 时隐藏窗口而非关闭（防止内容视图被销毁）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    
    // MARK: - 窗口管理
    
    func createMainWindowIfNeeded() {
        guard mainWindow == nil else {
            NSLog("🔵 [PiPTicker] 主窗口已存在，跳过创建")
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PiPTicker"
        window.contentView = NSHostingView(rootView: ContentView())
        window.contentMinSize = NSSize(width: 780, height: 520)
        window.isRestorable = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        self.mainWindow = window
        NSLog("🔵 [PiPTicker] 主窗口已创建 ✅")
    }
    
    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        createMainWindowIfNeeded()
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
#endif

@main
struct PiPTickerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    init() {
        AudioSessionManager.shared.setupAudioSession()
    }
    
    var body: some Scene {
        #if os(macOS)
        Settings {
            EmptyView()
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
