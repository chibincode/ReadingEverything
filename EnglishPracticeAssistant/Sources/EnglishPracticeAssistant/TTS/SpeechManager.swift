import AVFoundation

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    var onPlaybackStarted: (() -> Void)?
    var onPlaybackEnded: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var isPlaying = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakSystem(text: String) throws {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        stop()
        synthesizer.speak(utterance)
    }

    func play(audioData: Data) throws {
        guard !audioData.isEmpty else {
            throw SpeechError.emptyAudioData
        }
        stop()
        audioPlayer = try AVAudioPlayer(data: audioData)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        if audioPlayer?.play() == true {
            notifyStarted()
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
            notifyEnded()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyStarted()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyEnded()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyEnded()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyEnded()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.notifyEnded()
        }
    }

    private func notifyStarted() {
        guard !isPlaying else { return }
        isPlaying = true
        onPlaybackStarted?()
    }

    private func notifyEnded() {
        guard isPlaying else { return }
        isPlaying = false
        onPlaybackEnded?()
    }
}

private enum SpeechError: Error {
    case emptyAudioData
}
