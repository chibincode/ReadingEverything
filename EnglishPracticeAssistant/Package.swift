// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EnglishPracticeAssistant",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EnglishPracticeAssistant", targets: ["EnglishPracticeAssistant"])
    ],
    targets: [
        .executableTarget(
            name: "EnglishPracticeAssistant",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
