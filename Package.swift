// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Archon",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.29.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.29.1"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.16.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CWhisper",
            path: "Libraries/whisper"
        ),
        .executableTarget(
            name: "Archon",
            dependencies: [
                "CWhisper",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: "Sources/Archon",
            linkerSettings: [
                .unsafeFlags(["-L", "Libraries/whisper/lib"]),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-base"),
                .linkedLibrary("ggml-cpu"),
                .linkedLibrary("ggml-metal"),
                .linkedLibrary("ggml-blas"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .unsafeFlags(["-lstdc++"]),
            ]
        ),
    ]
)
