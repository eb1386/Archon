import ApplicationServices
import Dispatch
import Foundation

func boot() async {
    print("""

     archon v0.1
     voice -> actions, all local

    """)

    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
        print("[!] need accessibility permission — add Archon in System Settings > Privacy & Security")
        exit(1)
    }

    let config = Config.load()

    print("[*] loading llm...")
    let llm = MLXInference(modelPath: config.resolvedLlmPath)
    do {
        try await llm.load()
        print("[+] llm ready")
    } catch {
        print("[!] llm failed: \(error)")
        exit(1)
    }

    print("[*] loading whisper...")
    let transcriber = Transcriber(modelPath: config.resolvedWhisperPath)
    do {
        try transcriber.load()
        print("[+] whisper ready")
    } catch {
        print("[!] whisper failed: \(error)")
        exit(1)
    }

    let vad = VAD(modelPath: config.resolvedVadPath, threshold: config.vadThreshold)
    let executor = Executor()
    let planner = ActionPlanner(llm: llm)
    let listener = AudioListener(
        vad: vad,
        transcriber: transcriber,
        silenceDurationMs: config.silenceDurationMs
    )

    // whisper loves to hallucinate these on silence/noise
    let junkPhrases: Set<String> = [
        "thank you", "thanks for watching", "subscribe",
        "you", "bye", "", "the", "a", "i", "it", "is",
        "thank you for watching", "thanks",
        "please subscribe", "like and subscribe",
    ]

    print("[+] listening\n")

    listener.onTranscription = { text in
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 { return }
        if junkPhrases.contains(trimmed.lowercased()) { return }

        if let wake = config.wakeWord {
            guard trimmed.lowercased().hasPrefix(wake.lowercased()) else { return }
        }

        if config.logTranscriptions {
            print("heard: \"\(trimmed)\"")
        }

        Task {
            do {
                let actions = try await planner.plan(command: trimmed)
                let capped = Array(actions.prefix(config.maxActionsPerCommand))

                if config.logActions {
                    print("  \(capped.count) action(s)")
                }

                for (i, action) in capped.enumerated() {
                    if config.logActions {
                        print("  [\(i + 1)] \(action)")
                    }
                    try await executor.execute(action)
                    if config.actionDelayMs > 0 {
                        try await Task.sleep(nanoseconds: UInt64(config.actionDelayMs) * 1_000_000)
                    }
                }

                if config.ttsEnabled {
                    TTSFeedback.speak("Done")
                }
                print("  done\n")
            } catch {
                print("  err: \(error)\n")
            }
        }
    }

    listener.start()

    signal(SIGINT) { _ in
        print("\nbye")
        exit(0)
    }
}

Task { await boot() }
RunLoop.main.run()
