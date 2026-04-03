import AVFoundation

class TTSFeedback {
    private static let synth = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.2
        u.volume = 0.6
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(u)
    }
}
