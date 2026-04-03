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

        var tokens: [Int] = []

        _ = try await container.perform { ctx in
            try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.1, topP: 0.9, repetitionPenalty: 1.1),
                context: ctx
            ) { newTokens in
                tokens.append(contentsOf: newTokens)
                return tokens.count >= maxTokens ? .stop : .more
            }
        }

        let text = try await container.perform { ctx in
            ctx.tokenizer.decode(tokens: tokens)
        }
        return text
    }
}
