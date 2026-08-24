import Foundation
import Combine
import AVKit

#if canImport(UIKit)
import UIKit

public final class PiPManager: NSObject, ObservableObject {
    public static let shared = PiPManager()
    
    @Published public var isPiPActive: Bool = false
    @Published public var isPiPSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    @Published public var isAutoPiPEnabled: Bool = true
    
    public private(set) var pipController: AVPictureInPictureController?
    public let tickerViewController = PiPTickerViewController()
    private var pipVideoCallViewController: AVPictureInPictureVideoCallViewController?
    private weak var currentSourceView: UIView?
    
    // 16:9 极宽满屏基准尺寸（解锁 iOS 画中画最大屏幕全宽）
    public static let wideScreenSize = CGSize(width: 360, height: 202.5)
    
    private override init() {
        super.init()
    }
    
    public func setupPiP(with sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[PiPManager] 当前设备/系统不支持画中画")
            return
        }
        
        self.currentSourceView = sourceView
        
        // 创建用于 VoIP / 视频通话画中画的专用控制器
        let videoCallVC = AVPictureInPictureVideoCallViewController()
        self.pipVideoCallViewController = videoCallVC
        
        // 设置 16:9 宽屏尺寸
        videoCallVC.preferredContentSize = Self.wideScreenSize
        tickerViewController.preferredContentSize = Self.wideScreenSize
        
        // 将自定义行情视图添加为子视图并进行 100% 满屏刚性约束
        videoCallVC.addChild(tickerViewController)
        videoCallVC.view.addSubview(tickerViewController.view)
        tickerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tickerViewController.view.topAnchor.constraint(equalTo: videoCallVC.view.topAnchor),
            tickerViewController.view.leadingAnchor.constraint(equalTo: videoCallVC.view.leadingAnchor),
            tickerViewController.view.trailingAnchor.constraint(equalTo: videoCallVC.view.trailingAnchor),
            tickerViewController.view.bottomAnchor.constraint(equalTo: videoCallVC.view.bottomAnchor)
        ])
        tickerViewController.didMove(toParent: videoCallVC)
        
        // 设置画中画内容源
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: videoCallVC
        )
        
        let pip = AVPictureInPictureController(contentSource: contentSource)
        pip.delegate = self
        // 允许回到桌面时自动进入画中画
        pip.canStartPictureInPictureAutomaticallyFromInline = isAutoPiPEnabled
        self.pipController = pip
        
        print("[PiPManager] 16:9 极宽画中画控制器初始化完成")
    }
    
    public func startPiP() {
        guard let pip = pipController, !pip.isPictureInPictureActive else { return }
        pipVideoCallViewController?.preferredContentSize = Self.wideScreenSize
        tickerViewController.preferredContentSize = Self.wideScreenSize
        pip.startPictureInPicture()
    }
    
    public func stopPiP() {
        guard let pip = pipController, pip.isPictureInPictureActive else { return }
        pip.stopPictureInPicture()
    }
    
    public func setAutoPiP(enabled: Bool) {
        self.isAutoPiPEnabled = enabled
        pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiPManager] 即将启动 16:9 极宽画中画")
        pipVideoCallViewController?.preferredContentSize = Self.wideScreenSize
        tickerViewController.preferredContentSize = Self.wideScreenSize
    }
    
    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiPManager] 已启动画中画")
        DispatchQueue.main.async {
            self.isPiPActive = true
        }
    }
    
    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiPManager] 即将停止画中画")
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiPManager] 已停止画中画")
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[PiPManager] 画中画启动失败: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
    }
}
#else
// macOS 环境下的 PiPManager 适配桩 (Mac 上优先使用 MacFloatingWindowManager 跨桌面置顶悬浮窗)
public final class PiPManager: ObservableObject {
    public static let shared = PiPManager()
    @Published public var isPiPActive: Bool = false
    @Published public var isPiPSupported: Bool = false
    @Published public var isAutoPiPEnabled: Bool = false
    
    private init() {}
    public func startPiP() {
        MacFloatingWindowManager.shared.showFloatingWindow()
    }
    public func stopPiP() {
        MacFloatingWindowManager.shared.closeFloatingWindow()
    }
    public func setAutoPiP(enabled: Bool) {}
}
#endif

