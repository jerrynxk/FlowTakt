import Foundation
import AVFoundation
import os

// MARK: - 白噪音类型

/// 白噪音类型（纯代码合成，无需外部音频文件）
/// - white：纯白噪音
/// - rain：雨声（低通滤波噪声，模拟平稳雨幕）
/// - stream：溪流（布朗噪声，低频流水声）
/// - cafe：咖啡厅（低频人声底噪 + 缓慢起伏）
enum WhiteNoiseType: String, CaseIterable {
    case white
    case rain
    case stream
    case cafe
    /// 新增真实环境音（bundle 内 m4a 真实录音，Mixkit License 免费商用，无需署名）：
    /// ocean 海浪 / forest 森林鸟鸣 / night 夜晚虫鸣 / wind 微风
    case ocean
    case forest
    case night
    case wind

    /// 运行时本地化名称（供 UI 展示）
    var localizedName: String {
        switch self {
        case .white:  return L10n.shared.白噪音类型白
        case .rain:   return L10n.shared.白噪音类型雨
        case .stream: return L10n.shared.白噪音类型溪流
            case .cafe:   return L10n.shared.白噪音类型咖啡厅
            case .ocean:  return L10n.shared.白噪音类型海浪
            case .forest: return L10n.shared.白噪音类型森林
            case .night:  return L10n.shared.白噪音类型夜晚
            case .wind:   return L10n.shared.白噪音类型风
            }
    }
}

// MARK: - AudioService 协议

protocol AudioServiceProtocol {
    func playStartSound()
    func playCompleteSound()
    func playAlarmSound()
    func toggleWhiteNoise()
    /// 切换白噪音类型（若正在播放则实时切换音色）
    func setWhiteNoiseType(_ type: WhiteNoiseType)
    func configureAudioSession()
    var isWhiteNoisePlaying: Bool { get }
}

// MARK: - 音频服务实现

final class AudioService: AudioServiceProtocol {
    /// 统一日志（供 `log stream` 抓取，验证音频加载路径）
    private static let log = Logger(subsystem: "com.flowtakt.FlowTakt", category: "AudioService")
    private var audioEngine: AVAudioEngine?
    private var whiteNoiseNode: AVAudioSourceNode?
    /// 环境音播放器（rain/stream/cafe）：循环播放 bundle 内真实录音
    private var ambientPlayer: AVAudioPlayer?
    private var isWhiteNoisePlayingInternal = false
    /// 多个音效引擎队列：避免快速连续播放时新引擎覆盖旧引擎导致前一个音被截断
    private var activeToneEngines: [AVAudioEngine] = []

    /// 音频对象销毁延迟（秒）。
    ///
    /// `AVAudioSourceNode` 的 render block 运行在**实时音频线程**（由音频硬件驱动，优先级高于
    /// 所有用户线程），而 `AVAudioEngine.stop()` 仅标记停止、不保证 render block 已退出。
    /// 若在 stop 后立刻释放节点，实时线程仍可能在 render block 内写入已被回收的捕获变量，
    /// 造成 use-after-free（EXC_BAD_ACCESS）——本类历史上 2 次线上崩溃的根因。
    /// 销毁前延迟一拍，并在期间由闭包持有强引用，可确保实时线程安全退出。
    private static let teardownDelay: TimeInterval = 0.2

    /// 当前白噪音类型（持久化到 UserDefaults，跨启动保持一致）
    private var currentWhiteNoiseType: WhiteNoiseType = {
        let raw = UserDefaults.standard.string(forKey: "whiteNoiseType") ?? WhiteNoiseType.white.rawValue
        return WhiteNoiseType(rawValue: raw) ?? .white
    }()

    // MARK: - 主线程收敛

    /// 将音频操作收敛到主线程执行。
    ///
    /// `AVAudioEngine` / `AVAudioPlayer` 均非线程安全，且其内部回调依赖主线程 RunLoop。
    /// 此前所有音频操作都跑在自建串行队列 `audioQueue` 上，属线程违规，是偶发
    /// EXC_BAD_ACCESS 的放大器，故改为统一在主线程执行。
    ///
    /// 死锁说明：本类已完全移除 `audioQueue`，不存在「主线程等待 audioQueue、audioQueue
    /// 又 sync 回主线程」的交叉等待，因此下面的 `main.sync` 是安全的。
    /// 未采用 `@MainActor` 是因为项目为 `SWIFT_APPROACHABLE_CONCURRENCY` + Swift 5.0，
    /// 标注主 actor 会级联要求协议、调用方与测试一并标注，危及 0 警告基线。
    private func onMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    /// 延迟销毁音频对象：闭包持有强引用，确保实时音频线程已退出 render block。
    private static func releaseLater(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + teardownDelay, execute: work)
    }

    init() {
        configureAudioSession()
    }

    /// 是否正在播放白噪音（调用方均在主线程；状态读写已由 `onMain` 统一收敛）
    var isWhiteNoisePlaying: Bool {
        isWhiteNoisePlayingInternal
    }

    // MARK: - 音频会话配置

    func configureAudioSession() {
        onMain {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                print("音频会话配置失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 音效播放

    func playStartSound() {
        onMain { self.playTone(frequency: 880, duration: 0.15) }
    }

    func playCompleteSound() {
        // 第一个音使用独立引擎，不会因为第二个音启动而被覆盖
        onMain { self.playTone(frequency: 660, duration: 0.2) }
        // asyncAfter 的回调本身位于主线程，无需再包 onMain
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.playTone(frequency: 880, duration: 0.3)
        }
    }

    func playAlarmSound() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) { [weak self] in
                self?.playTone(frequency: 1200, duration: 0.25)
            }
        }
    }

    // MARK: - 白噪音

    func toggleWhiteNoise() {
        onMain {
            if isWhiteNoisePlayingInternal {
                stopWhiteNoiseLocked()
            } else {
                startWhiteNoiseLocked()
            }
        }
    }

    func setWhiteNoiseType(_ type: WhiteNoiseType) {
        onMain {
            let wasPlaying = isWhiteNoisePlayingInternal
            // 先停后建：旧对象的销毁已延迟到 0.2s 后，
            // 新对象在此刻创建，二者生命周期不再重叠，避免切换类型时的释放竞态
            if wasPlaying {
                stopWhiteNoiseLocked()
            }
            currentWhiteNoiseType = type
            UserDefaults.standard.set(type.rawValue, forKey: "whiteNoiseType")
            if wasPlaying {
                startWhiteNoiseLocked()
            }
        }
    }

    private func startWhiteNoiseLocked() {
        guard !isWhiteNoisePlayingInternal else { return }

        // rain / stream / cafe：使用 bundle 内真实录音循环播放
        // white：保持纯代码合成（最简单基底，无需音频文件）
        switch currentWhiteNoiseType {
        case .rain, .stream, .cafe, .ocean, .forest, .night, .wind:
            startAmbientPlayerLocked()
            if ambientPlayer != nil {
                isWhiteNoisePlayingInternal = true
            } else {
                Self.log.error("AMBIENT_FALLBACK_SYNTH type=\(self.currentWhiteNoiseType.rawValue)")
                startSynthesizedWhiteNoiseLocked()
                isWhiteNoisePlayingInternal = true
            }
        case .white:
            Self.log.info("SYNTH_START white")
            startSynthesizedWhiteNoiseLocked()
            isWhiteNoisePlayingInternal = true
        }
    }

    private func stopWhiteNoiseLocked() {
        guard isWhiteNoisePlayingInternal else { return }

        stopSynthesizedWhiteNoiseLocked()
        stopAmbientPlayerLocked()
        isWhiteNoisePlayingInternal = false
    }

    /// 启动代码合成白噪音（仅 .white）
    private func startSynthesizedWhiteNoiseLocked() {
        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)

        let type = currentWhiteNoiseType
        // 节点内独立的滤波状态（环境音连续性损失可忽略，避免跨线程共享可变状态）
        var last: Float = 0

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample: Float
                switch type {
                case .white:
                    sample = Float.random(in: -0.06...0.06)
                case .rain:
                    let w = Float.random(in: -1...1)
                    last = last * 0.92 + w * 0.08
                    sample = last * 0.06
                case .stream:
                    let w = Float.random(in: -1...1)
                    last = (last + 0.02 * w) / 1.02
                    sample = last * 0.06
                case .cafe:
                    let w = Float.random(in: -1...1)
                    last = last * 0.96 + w * 0.04
                    let mod = 0.7 + 0.3 * sin(Float(frame) * 0.01)
                    sample = last * 0.06 * mod
                default:
                    // 仅 .white 走合成路径；其余类型均经由 bundle 真实录音播放，不会进入此分支
                    sample = 0
                }
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: outputFormat)
        engine.connect(mainMixer, to: engine.outputNode, format: outputFormat)

        do {
            try engine.start()
            audioEngine = engine
            whiteNoiseNode = sourceNode
        } catch {
            print("白噪音引擎启动失败：\(error.localizedDescription)")
        }
    }

    private func stopSynthesizedWhiteNoiseLocked() {
        // 先摘引用，避免重入时重复 stop
        guard let engine = audioEngine, let node = whiteNoiseNode else {
            audioEngine = nil
            whiteNoiseNode = nil
            return
        }
        audioEngine = nil
        whiteNoiseNode = nil

        engine.disconnectNodeOutput(node)
        engine.stop()

        // 延迟 reset 与销毁：闭包强引用 engine / node，保证实时音频线程的
        // render block 完全退出后才回收内存（修复 use-after-free 崩溃）
        Self.releaseLater {
            engine.reset()
            withExtendedLifetime(node) { }
        }
    }

    // MARK: - 环境音播放器（rain / stream / cafe，bundle 真实录音）

    /// 将 WhiteNoiseType 映射到 bundle 内的音频资源文件名（无后缀）
    private func ambientResourceName(for type: WhiteNoiseType) -> String? {
        switch type {
        case .rain:   return "rain"
        case .stream: return "stream"
        case .cafe:   return "cafe"
        case .ocean:  return "ocean"
        case .forest: return "forest"
        case .night:  return "night"
        case .wind:   return "wind"
        case .white:  return nil
        }
    }

    private func startAmbientPlayerLocked() {
        guard let resource = ambientResourceName(for: currentWhiteNoiseType),
              let url = Bundle.main.url(forResource: resource, withExtension: "m4a") else {
            Self.log.error("AMBIENT_MISSING type=\(self.currentWhiteNoiseType.rawValue) bundle=\(Bundle.main.bundlePath)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1        // 无限循环（专注时长内连续播放）
            player.volume = 1.0
            player.prepareToPlay()
            let ok = player.play()
            ambientPlayer = player
            Self.log.info("AMBIENT_START type=\(self.currentWhiteNoiseType.rawValue) file=\(url.lastPathComponent) duration=\(player.duration) play=\(ok)")
        } catch {
            Self.log.error("AMBIENT_PLAY_FAIL \(error.localizedDescription)")
        }
    }

    private func stopAmbientPlayerLocked() {
        guard let player = ambientPlayer else { return }
        ambientPlayer = nil
        player.stop()
        // 延迟销毁：stop() 是异步的，大文件（rain.m4a 约 5.1MB）解码收尾期间
        // 立即释放会导致内部回调访问已回收对象。闭包强引用延长生命周期至收尾完成。
        Self.releaseLater {
            withExtendedLifetime(player) { }
        }
    }

    // MARK: - 私有：纯音生成

    private func playTone(frequency: Double, duration: TimeInterval) {
        let sampleRate: Double = 44100
        let frameCount = Int(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(format.channelCount))

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let envelope = 1.0 - (Double(frame) / Double(frameCount))
            let sample = Float(sin(2 * .pi * frequency * t) * envelope * 0.4)
            for channel in channels {
                channel[frame] = sample
            }
        }

        let playerNode = AVAudioPlayerNode()
        let engine = AVAudioEngine()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("音效引擎启动失败：\(error.localizedDescription)")
            return
        }

        // 将引擎加入活动队列，避免被 ARC 提前释放（修复音效截断）
        activeToneEngines.append(engine)

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                engine.stop()
                self.activeToneEngines.removeAll { $0 === engine }
                // 延迟销毁：playerNode 的渲染回调在实时线程执行，
                // 立即释放同样会触发 use-after-free
                Self.releaseLater {
                    withExtendedLifetime(engine) { }
                    withExtendedLifetime(playerNode) { }
                }
            }
        }
        playerNode.play()
    }
}

// MARK: - 语音播报服务

protocol SpeechServiceProtocol {
    /// 播报文本（内部会根据开关判断是否实际发音）
    func speak(_ text: String)
    /// 是否启用语音播报（与设置页 speechEnabled 共享同一 UserDefaults 键）
    var isSpeechEnabled: Bool { get }
}

final class SpeechService: SpeechServiceProtocol {
    private let synthesizer = AVSpeechSynthesizer()

    var isSpeechEnabled: Bool {
        UserDefaults.standard.object(forKey: "speechEnabled") as? Bool ?? true
    }

    func speak(_ text: String) {
        guard isSpeechEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: L10n.shared.isEnglish ? "en-US" : "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }
}
