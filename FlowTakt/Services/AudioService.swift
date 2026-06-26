import Foundation
import AVFoundation

// MARK: - AudioService 协议

protocol AudioServiceProtocol {
    func playStartSound()
    func playCompleteSound()
    func playAlarmSound()
    func toggleWhiteNoise()
    func configureAudioSession()
    var isWhiteNoisePlaying: Bool { get }
}

// MARK: - 音频服务实现（纯代码生成，无需外部音频文件）

final class AudioService: AudioServiceProtocol {
    private var audioEngine: AVAudioEngine?
    private var whiteNoiseNode: AVAudioSourceNode?
    private var isWhiteNoisePlayingInternal = false
    /// 多个音效引擎队列：避免快速连续播放时新引擎覆盖旧引擎导致前一个音被截断
    private var activeToneEngines: [AVAudioEngine] = []
    /// 私有串行队列，保证音频引擎状态变更的线程安全
    private let audioQueue = DispatchQueue(label: "com.flowtakt.audio.engine")

    init() {
        configureAudioSession()
    }

    var isWhiteNoisePlaying: Bool {
        audioQueue.sync { isWhiteNoisePlayingInternal }
    }

    // MARK: - 音频会话配置

    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("音频会话配置失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 音效播放

    func playStartSound() {
        playTone(frequency: 880, duration: 0.15)
    }

    func playCompleteSound() {
        // 第一个音使用独立引擎，不会因为第二个音启动而被覆盖
        playTone(frequency: 660, duration: 0.2)
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
        audioQueue.sync {
            if isWhiteNoisePlayingInternal {
                stopWhiteNoiseLocked()
            } else {
                startWhiteNoiseLocked()
            }
        }
    }

    private func startWhiteNoiseLocked() {
        guard !isWhiteNoisePlayingInternal else { return }

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float.random(in: -0.06...0.06)
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
            isWhiteNoisePlayingInternal = true
        } catch {
            print("白噪音引擎启动失败：\(error.localizedDescription)")
        }
    }

    private func stopWhiteNoiseLocked() {
        guard isWhiteNoisePlayingInternal else { return }

        if let node = whiteNoiseNode {
            audioEngine?.disconnectNodeOutput(node)
        }
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
        whiteNoiseNode = nil
        isWhiteNoisePlayingInternal = false
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
        audioQueue.sync {
            activeToneEngines.append(engine)
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let self = self else { return }
                self.audioQueue.sync {
                    engine.stop()
                    if let index = self.activeToneEngines.firstIndex(where: { $0 === engine }) {
                        self.activeToneEngines.remove(at: index)
                    }
                }
            }
        }
        playerNode.play()
    }
}
