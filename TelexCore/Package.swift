// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TelexCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TelexCore", targets: ["TelexCore"]),
        .executable(name: "gen-lessons", targets: ["GenLessons"]),
        .executable(name: "gen-english", targets: ["GenEnglish"]),
        .executable(name: "gen-golden", targets: ["GenGolden"]),
        .executable(name: "gen-freeze-prefixes", targets: ["GenFreezePrefixes"]),
        // Mô phỏng gõ câu trộn Việt–Anh (docs/REGRESSION.md "Mô phỏng gõ câu trộn").
        .executable(name: "mixed-eval", targets: ["MixedEval"])
    ],
    targets: [
        .target(
            name: "TelexCore",
            // Bàn phím iOS (Release) build -Osize như phần còn lại của extension (iOS/project.yml)
            // — Xcode KHÔNG truyền SWIFT_OPTIMIZATION_LEVEL của project xuống package (trước:
            // -O). Chỉ iOS: macOS/Linux giữ -O như cũ. Package local (path:) nên unsafeFlags hợp lệ.
            swiftSettings: [.unsafeFlags(["-Osize"], .when(platforms: [.iOS], configuration: .release))]
        ),
        .executableTarget(
            name: "GenLessons",
            dependencies: ["TelexCore"]
        ),
        .executableTarget(
            name: "GenEnglish",
            dependencies: ["TelexCore"]
        ),
        .executableTarget(
            name: "GenGolden",
            dependencies: ["TelexCore"]
        ),
        .executableTarget(
            name: "GenFreezePrefixes",
            dependencies: ["TelexCore"]
        ),
        // Người gõ mô phỏng + chấm điểm trên TelexCore/Corpus/mixed-typing.tsv. Không nằm
        // trong product TelexCore (app/bàn phím không link) — chỉ lệnh đo và test dùng.
        .target(
            name: "MixedTyping",
            dependencies: ["TelexCore"]
        ),
        .executableTarget(
            name: "MixedEval",
            dependencies: ["MixedTyping"]
        ),
        .testTarget(
            name: "MixedTypingTests",
            dependencies: ["MixedTyping"]
        ),
        .testTarget(
            name: "TelexCoreTests",
            dependencies: ["TelexCore"],
            resources: [.copy("Resources/telex_test_suite.csv"), .copy("Resources/spelling_error_cases.tsv")]
        )
    ]
)
