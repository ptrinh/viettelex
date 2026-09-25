// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TelexCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TelexCore", targets: ["TelexCore"]),
        .executable(name: "gen-lessons", targets: ["GenLessons"]),
        .executable(name: "gen-english", targets: ["GenEnglish"]),
        .executable(name: "gen-golden", targets: ["GenGolden"])
    ],
    targets: [
        .target(
            name: "TelexCore"
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
        .testTarget(
            name: "TelexCoreTests",
            dependencies: ["TelexCore"],
            resources: [.copy("Resources/telex_test_suite.csv")]
        )
    ]
)
