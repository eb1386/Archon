import Foundation
import MLX
import MLXLLM
import MLXLMCommon

class MLXInference {
    private var container: ModelContainer?
    private let modelPath: String

    init(modelPath: String) {
        self.modelPath = Config.expandPath(modelPath)
    }

    func load() async throws {
        let url = URL(fileURLWithPath: modelPath)
        let config = ModelConfiguration(directory: url)
        container = try await LLMModelFactory.shared.loadContainer(configuration: config)
    }

    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int = 512) async throws -> String {
        guard let container = container else {
            throw ArchonError.modelNotLoaded
        }

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let input = try await container.perform { ctx in
            try await ctx.processor.prepare(input: .init(messages: messages))
        }

        var tokenCount = 0
        let result = try await container.perform { ctx in
            try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.1, topP: 0.9, repetitionPenalty: 1.1),
                context: ctx
            ) { newTokens in
                tokenCount += newTokens.count
                return tokenCount >= maxTokens ? .stop : .more
            }
        }

        return result.output
    }
}
