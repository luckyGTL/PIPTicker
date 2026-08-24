import Foundation
import AVFoundation

/// 音频会话管理器：用于激活后台音频通道，配合画中画实现后台保活
public final class AudioSessionManager {
    public static let shared = AudioSessionManager()
    
    private init() {}
    
    public func setupAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // 使用 playback 类别与 moviePlayback 模式，支持后台画中画与声音混合
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
            print("[AudioSessionManager] 音频后台通道激活成功")
        } catch {
            print("[AudioSessionManager] 音频后台通道激活失败: \(error.localizedDescription)")
        }
        #endif
    }
}
