import Foundation
import CWhisper

class Transcriber {
    private var ctx: OpaquePointer?
    private let modelPath: String
    // keep this alive so we don't strdup every call
    private let langPtr: UnsafeMutablePointer<CChar>

    init(modelPath: String) {
        self.modelPath = Config.expandPath(modelPath)
        self.langPtr = strdup("en")!
    }

    deinit {
        free(langPtr)
        if let ctx = ctx { whisper_free(ctx) }
    }

    func load() throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        ctx = whisper_init_from_file_with_params(modelPath, cparams)
        if ctx == nil {
            throw ArchonError.whisperInitFailed
        }
    }

    func transcribe(samples: [Float]) -> TranscriptionResult? {
        guard let ctx = ctx else { return nil }

        let t0 = CFAbsoluteTimeGetCurrent()

        var p = whisper_full_default_params(0) // greedy strategy
        p.n_threads = 4
        p.single_segment = true
        p.no_timestamps = true
        p.print_special = false
        p.print_progress = false
        p.print_realtime = false
        p.print_timestamps = false
        p.language = UnsafePointer(langPtr)
        p.translate = false
        p.suppress_blank = true
        p.suppress_non_speech_tokens = true
        p.no_context = true
        p.temperature = 0.0
        p.max_initial_ts = 1.0

        let rc = samples.withUnsafeBufferPointer { buf -> Int32 in
            guard let ptr = buf.baseAddress else { return -1 }
            return whisper_full(ctx, p, ptr, Int32(samples.count))
        }
        guard rc == 0 else { return nil }

        var text = ""
        let nSeg = whisper_full_n_segments(ctx)
        for i in 0..<nSeg {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cStr)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: elapsed
        )
    }
}
