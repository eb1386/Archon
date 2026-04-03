import AVFoundation
import Foundation

class AudioListener {
    private let audioEngine = AVAudioEngine()
    private let vad: VAD
    private let transcriber: Transcriber

    private var speechBuf: [Float] = []
    private var speaking = false
    private var silentChunks = 0
    private let silentChunksNeeded: Int
    // grab a bit of audio before the vad triggers so we don't clip the start
    private var ringBuf: [Float] = []
    private let ringBufMax: Int = 4800 // ~300ms @16k
    private let minSpeechLen: Int = 4000 // ~250ms

    var onTranscription: ((String) -> Void)?

    init(vad: VAD, transcriber: Transcriber, silenceDurationMs: Int = 500) {
        self.vad = vad
        self.transcriber = transcriber
        self.silentChunksNeeded = (silenceDurationMs * 16) / 512
    }

    func start() {
        let node = audioEngine.inputNode
        let hwFmt = node.outputFormat(forBus: 0)

        guard let outFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000,
            channels: 1, interleaved: false
        ) else {
            print("[!] couldn't create 16k format")
            return
        }

        guard let conv = AVAudioConverter(from: hwFmt, to: outFmt) else {
            print("[!] couldn't create audio converter (hw: \(hwFmt))")
            return
        }

        node.installTap(onBus: 0, bufferSize: 1024, format: hwFmt) { [weak self] buf, _ in
            self?.handleAudio(buf, converter: conv, fmt: outFmt)
        }

        do {
            try audioEngine.start()
        } catch {
            print("[!] audio engine: \(error)")
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func handleAudio(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, fmt: AVAudioFormat) {
        let ratio = 16000.0 / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outFrames > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: outFrames)
        else { return }

        var err: NSError?
        var fed = false
        converter.convert(to: converted, error: &err) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if err != nil || converted.frameLength == 0 { return }
        guard let ch = converted.floatChannelData else { return }

        let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(converted.frameLength)))
        let prob = vad.detect(samples: samples)

        if prob > vad.threshold {
            if !speaking {
                speaking = true
                silentChunks = 0
                speechBuf = ringBuf // prepend the ring buffer
            }
            speechBuf.append(contentsOf: samples)
            silentChunks = 0
        } else {
            // keep a rolling window for pre-speech audio
            ringBuf.append(contentsOf: samples)
            if ringBuf.count > ringBufMax {
                ringBuf.removeFirst(ringBuf.count - ringBufMax)
            }
            if speaking {
                speechBuf.append(contentsOf: samples)
                silentChunks += 1
                if silentChunks >= silentChunksNeeded {
                    speaking = false
                    let captured = speechBuf
                    speechBuf = []
                    silentChunks = 0
                    if captured.count >= minSpeechLen {
                        runTranscription(captured)
                    }
                }
            }
        }
    }

    private func runTranscription(_ samples: [Float]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if let r = self.transcriber.transcribe(samples: samples), !r.text.isEmpty {
                self.onTranscription?(r.text)
            }
        }
    }
}
