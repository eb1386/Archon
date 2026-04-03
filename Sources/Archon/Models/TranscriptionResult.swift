import Foundation

struct TranscriptionResult {
    let text: String
    let duration: TimeInterval
    let isPartial: Bool

    init(text: String, duration: TimeInterval = 0, isPartial: Bool = false) {
        self.text = text
        self.duration = duration
        self.isPartial = isPartial
    }
}
