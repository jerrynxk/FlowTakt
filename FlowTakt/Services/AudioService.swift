import Foundation
import AVFoundation

// MARK: - AudioService 协议

protocol AudioServiceProtocol {
    func playStartSound()
    func playCompleteSound()
    func playAlarmSound()
    func toggleWhiteNoise()
    var isWhiteNoisePlaying: Bool { get }
}

// MARK: - 音频服务实现

final class AudioService: AudioServiceProtocol {
    private var audioPlayer: AVAudioPlayer?
    private var whiteNoisePlayer: AVAudioPlayer?
    private(set) var isWhiteNoisePlaying = false

    func playStartSound() {
        playSound(named: "bell_start")
    }

    func playCompleteSound() {
        playSound(named: "bell_complete")
    }

    func playAlarmSound() {
        playSound(named: "alarm")
    }

    func toggleWhiteNoise() {
        if isWhiteNoisePlaying {
            whiteNoisePlayer?.stop()
            isWhiteNoisePlaying = false
        } else {
            guard let url = Bundle.main.url(forResource: "white_noise_rain",
                                           withExtension: "mp3") else { return }
            do {
                whiteNoisePlayer = try AVAudioPlayer(contentsOf: url)
                whiteNoisePlayer?.numberOfLoops = -1
                whiteNoisePlayer?.play()
                isWhiteNoisePlaying = true
            } catch {
                print("白噪音播放失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 私有方法

    private func playSound(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("音效文件未找到：\(name)")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("音效播放失败：\(error.localizedDescription)")
        }
    }
}
