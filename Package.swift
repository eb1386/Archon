// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Archon",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),
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
                .linkedLibrary("whisper"),
                .unsafeFlags(["-L", "Libraries/whisper/lib"]),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
