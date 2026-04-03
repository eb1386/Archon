import Foundation
import MLX
import MLXLLM
import MLXLMCommon

class MLXInference: @unchecked Sendable {
    private var container: ModelContainer?
    private let modelPath: String

    init(modelPath: String) {
        self.modelPath = Config.expandPath(modelPath)
    }

    func load() async throws {
        let url = URL(fileURLWithPath: modelPath)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDir), isDir.boolValue else {
            print("[!] model dir not found: \(modelPath)")
            throw ArchonError.modelNotLoaded
        }

        let config = ModelConfiguration(directory: url)
        container = try await LLMModelFactory.shared.loadContainer(configuration: config) { _ in }
    }

    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int = 512) async throws -> String {
        guard let container = container else {
            throw ArchonError.modelNotLoaded
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let limit = maxTokens
        let result = try await container.perform { ctx in
            let input = try await ctx.processor.prepare(input: .init(messages: messages))
            var count = 0
            return try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.1, topP: 0.9, repetitionPenalty: 1.1),
                context: ctx
            ) { newTokens in
                count += newTokens.count
                return count >= limit ? .stop : .more
            }
        }

        return result.output
    }
}
