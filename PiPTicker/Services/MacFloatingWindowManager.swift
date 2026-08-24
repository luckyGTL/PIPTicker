import SwiftUI
import Combine

#if canImport(AppKit)
import AppKit
#endif

/// 悬浮窗收起靠边的方向
public enum DockEdge {
    case none
    case left
    case right
}

/// Mac 跨桌面全局置顶悬浮窗管理中心 (支持靠近屏幕边缘 3 秒自动收起隐藏，鼠标移入即时滑出)
public final class MacFloatingWindowManager: ObservableObject {
    public static let shared = MacFloatingWindowManager()
    
    @Published public var isFloatingWindowOpen: Bool = false
    @Published public var windowOpacity: Double = 0.95
    @Published public var isLockedOnTop: Bool = true
    @Published public var isDocked: Bool = false
    @Published public var dockedEdge: DockEdge = .none
    @Published public var autoHideEnabled: Bool = true
    @Published public var autoHideDelay: Double = 1.0   // 贴边自动收起等待时间，默认 1.0 秒
    
    #if canImport(AppKit)
    private var floatingPanel: NSPanel?
    private var autoDockTimer: Timer?
    private var expandedFrame: NSRect = .zero
    private var isMouseInside: Bool = false
    private let peekWidth: CGFloat = 18.0        // 靠边收起后露出的触发把手宽度
    private let edgeThreshold: CGFloat = 35.0    // 判定为靠近屏幕边缘的吸附阈值（像素）
    private var moveObserver: NSObjectProtocol?
    private var isProgrammaticMoving: Bool = false
    #endif
    
    private init() {}
    
    /// 开启 / 切换 Mac 跨桌面置顶悬浮窗
    public func toggleFloatingWindow() {
        if isFloatingWindowOpen {
            closeFloatingWindow()
        } else {
            showFloatingWindow()
        }
    }
    
    public func showFloatingWindow() {
        #if canImport(AppKit)
        if floatingPanel == nil {
            createFloatingPanel()
        }
        
        floatingPanel?.alphaValue = CGFloat(windowOpacity)
        floatingPanel?.orderFrontRegardless()
        floatingPanel?.makeKeyAndOrderFront(nil)
        isFloatingWindowOpen = true
        isDocked = false
        dockedEdge = .none
        
        // 检查初始位置是否靠边，若是则启动 3 秒收起倒计时
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkEdgeAndScheduleDock()
        }
        #else
        // iOS 运行环境下 fallback
        print("[MacFloatingWindowManager] 仅在 macOS / Mac 环境下可用")
        #endif
    }
    
    public func closeFloatingWindow() {
        #if canImport(AppKit)
        cancelAutoDockTimer()
        if let observer = moveObserver {
            NotificationCenter.default.removeObserver(observer)
            moveObserver = nil
        }
        floatingPanel?.close()
        floatingPanel = nil
        isFloatingWindowOpen = false
        isDocked = false
        dockedEdge = .none
        #else
        isFloatingWindowOpen = false
        #endif
    }
    
    #if canImport(AppKit)
    private func createFloatingPanel() {
        // 初始位置放置在主屏幕左侧靠边区域
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultWidth: CGFloat = 360
        let defaultHeight: CGFloat = 202.5
        let initialX: CGFloat = screenRect.minX + 20
        let initialY: CGFloat = screenRect.maxY - defaultHeight - 80
        
        let panel = NSPanel(
            contentRect: NSRect(x: initialX, y: initialY, width: defaultWidth, height: defaultHeight),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .nonactivatingPanel,
                .utilityWindow,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        
        // 1. 跨所有桌面 Space 始终可见
        panel.collectionBehavior = [
            .canJoinAllSpaces,          // 切换桌面时始终停留在当前桌面
            .fullScreenAuxiliary,        // 在全屏 App（如全屏 Xcode、全屏视频）上方始终可见
            .stationary
        ]
        
        // 2. 全局悬浮置顶 (Always on Top)
        panel.level = .floating
        
        // 3. 视觉与交互属性
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true // 允许鼠标点按背景任意区域自由拖拽
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 220, height: 124)
        panel.maxSize = NSSize(width: 800, height: 450)
        panel.isFloatingPanel = true
        
        // 4. 挂载 SwiftUI 悬浮看板视图
        let hostingView = NSHostingView(
            rootView: MacFloatingStockView(onClose: { [weak self] in
                self?.closeFloatingWindow()
            })
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        
        // 5. 监听窗口移动通知，检测是否靠近屏幕边缘
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.isProgrammaticMoving else { return }
            self.handleWindowUserMoved()
        }
        
        self.floatingPanel = panel
    }
    
    // MARK: - 屏幕边缘贴边收起与展开逻辑
    
    /// 用户手动拖拽窗口后的贴边检测
    private func handleWindowUserMoved() {
        guard let panel = floatingPanel, let screen = panel.screen else { return }
        let frame = panel.frame
        let screenFrame = screen.visibleFrame
        
        let isNearLeft = (frame.minX - screenFrame.minX) <= edgeThreshold
        let isNearRight = (screenFrame.maxX - frame.maxX) <= edgeThreshold
        
        if isNearLeft || isNearRight {
            // 记录展开时的正常尺寸与位置
            if !isDocked {
                expandedFrame = frame
            }
            scheduleAutoDockTimer()
        } else {
            // 离开边缘区域，取消计时并重置收起状态
            cancelAutoDockTimer()
            if isDocked {
                isDocked = false
                dockedEdge = .none
            }
        }
    }
    
    /// 检查边缘位置并安排 3 秒后收起
    private func checkEdgeAndScheduleDock() {
        guard let panel = floatingPanel, let screen = panel.screen else { return }
        let frame = panel.frame
        let screenFrame = screen.visibleFrame
        
        let isNearLeft = (frame.minX - screenFrame.minX) <= edgeThreshold
        let isNearRight = (screenFrame.maxX - frame.maxX) <= edgeThreshold
        
        if isNearLeft || isNearRight {
            if !isDocked {
                expandedFrame = frame
            }
            scheduleAutoDockTimer()
        }
    }
    
    /// 安排贴边自动收起倒计时 (基于配置的延迟秒数，默认 1.0 秒)
    private func scheduleAutoDockTimer() {
        guard autoHideEnabled, !isDocked, !isMouseInside else { return }
        cancelAutoDockTimer()
        
        autoDockTimer = Timer.scheduledTimer(withTimeInterval: max(0.2, autoHideDelay), repeats: false) { [weak self] _ in
            guard let self = self, !self.isMouseInside, !self.isDocked else { return }
            self.performAutoDock()
        }
    }
    
    /// 取消收起倒计时
    public func cancelAutoDockTimer() {
        autoDockTimer?.invalidate()
        autoDockTimer = nil
    }
    
    /// 执行收起漂出屏幕动画（左侧向左收起，右侧向右收起）
    private func performAutoDock() {
        guard let panel = floatingPanel, let screen = panel.screen else { return }
        let frame = panel.frame
        let screenFrame = screen.visibleFrame
        
        let isNearLeft = (frame.minX - screenFrame.minX) <= edgeThreshold + 50
        let isNearRight = (screenFrame.maxX - frame.maxX) <= edgeThreshold + 50
        
        guard isNearLeft || isNearRight else { return }
        
        let edge: DockEdge = isNearLeft ? .left : .right
        expandedFrame = frame
        
        var targetRect = frame
        if edge == .left {
            // 向左漂出屏幕，仅露出右边缘 peekWidth 像素的把手
            targetRect.origin.x = screenFrame.minX - frame.width + peekWidth
        } else {
            // 向右漂出屏幕，仅露出左边缘 peekWidth 像素的把手
            targetRect.origin.x = screenFrame.maxX - peekWidth
        }
        
        isProgrammaticMoving = true
        isDocked = true
        dockedEdge = edge
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetRect, display: true)
        }, completionHandler: { [weak self] in
            self?.isProgrammaticMoving = false
        })
    }
    
    /// 执行展开滑入屏幕动画
    public func expandDockedWindow() {
        guard let panel = floatingPanel, let screen = panel.screen, isDocked else { return }
        let screenFrame = screen.visibleFrame
        
        var targetRect = panel.frame
        if dockedEdge == .left {
            targetRect.origin.x = screenFrame.minX
        } else if dockedEdge == .right {
            targetRect.origin.x = screenFrame.maxX - panel.frame.width
        } else if expandedFrame != .zero {
            targetRect = expandedFrame
        }
        
        isProgrammaticMoving = true
        isDocked = false
        dockedEdge = .none
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetRect, display: true)
        }, completionHandler: { [weak self] in
            self?.isProgrammaticMoving = false
        })
    }
    
    /// 鼠标移入/移出悬浮窗时调用
    public func setMouseHovering(_ hovering: Bool) {
        self.isMouseInside = hovering
        if hovering {
            cancelAutoDockTimer()
            if isDocked {
                expandDockedWindow()
            }
        } else {
            // 鼠标移出后，如果依然靠近边缘，则重新启动 3 秒收起计时
            if !isDocked {
                checkEdgeAndScheduleDock()
            }
        }
    }
    
    public func updateOpacity(_ opacity: Double) {
        self.windowOpacity = opacity
        floatingPanel?.alphaValue = CGFloat(opacity)
    }
    
    public func setAlwaysOnTop(_ onTop: Bool) {
        self.isLockedOnTop = onTop
        floatingPanel?.level = onTop ? .floating : .normal
    }
    #else
    public func setMouseHovering(_ hovering: Bool) {}
    public func updateOpacity(_ opacity: Double) {}
    public func setAlwaysOnTop(_ onTop: Bool) {}
    public func expandDockedWindow() {}
    public func cancelAutoDockTimer() {}
    #endif
}
