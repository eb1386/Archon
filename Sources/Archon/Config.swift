import Foundation

struct Config: Codable {
    var whisperModelPath: String
    var vadModelPath: String
    var llmModelPath: String
    var wakeWord: String?
    var alwaysListening: Bool
    var actionDelayMs: Int
    var ttsEnabled: Bool
    var vadThreshold: Float
    var silenceDurationMs: Int
    var maxActionsPerCommand: Int
    var logTranscriptions: Bool
    var logActions: Bool

    enum CodingKeys: String, CodingKey {
        case whisperModelPath = "whisper_model_path"
        case vadModelPath = "vad_model_path"
        case llmModelPath = "llm_model_path"
        case wakeWord = "wake_word"
        case alwaysListening = "always_listening"
        case actionDelayMs = "action_delay_ms"
        case ttsEnabled = "tts_enabled"
        case vadThreshold = "vad_threshold"
        case silenceDurationMs = "silence_duration_ms"
        case maxActionsPerCommand = "max_actions_per_command"
        case logTranscriptions = "log_transcriptions"
        case logActions = "log_actions"
    }

    static let configPath: String = {
        NSHomeDirectory() + "/.archon/config.json"
    }()

    static func expandPath(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + String(path.dropFirst(1))
        }
        return (path as NSString).expandingTildeInPath
    }

    static func defaults() -> Config {
        Config(
            whisperModelPath: "~/.archon/models/ggml-base.en.bin",
            vadModelPath: "~/.archon/models/silero_vad.onnx",
            llmModelPath: "~/.archon/models/qwen2.5-0.5b-instruct-4bit",
            wakeWord: nil,
            alwaysListening: true,
            actionDelayMs: 100,
            ttsEnabled: false,
            vadThreshold: 0.5,
            silenceDurationMs: 500,
            maxActionsPerCommand: 20,
            logTranscriptions: true,
            logActions: true
        )
    }

    static func load() -> Config {
        guard FileManager.default.fileExists(atPath: configPath),
              let data = FileManager.default.contents(atPath: configPath) else {
            return defaults()
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            print("[!] bad config, using defaults: \(error)")
            return defaults()
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        // make sure ~/.archon/ exists
        let dir = (Config.configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Config.configPath, contents: data)
    }

    var resolvedWhisperPath: String { Config.expandPath(whisperModelPath) }
    var resolvedVadPath: String { Config.expandPath(vadModelPath) }
    var resolvedLlmPath: String { Config.expandPath(llmModelPath) }
}
