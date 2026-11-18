// swift-tools-version: 6.2
// the-great-gui: a native Mac manager for your terminal commands, drawn with the ds-next terminal design system.
// Builds with the command-line tools alone (`swift build`; no `@State`, DECISIONS local-006); Xcode opens this file too.
import PackageDescription

let package = Package(
    name: "the-great-gui",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TerminalDesign", targets: ["TerminalDesign"]),
        .library(name: "Registry", targets: ["Registry"]),
        .library(name: "Runner", targets: ["Runner"]),
        .library(name: "Secrets", targets: ["Secrets"]),
        .library(name: "Scheduler", targets: ["Scheduler"]),
        .executable(name: "GreatGUI", targets: ["GreatGUI"]),
    ],
    dependencies: [
        // Full TOML for commands.toml, so agents and skills may write any valid file (chosen 2026-11-09).
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        // The embedded terminal for interactive commands (chosen 2026-11-09).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.99.0"),
    ],
    targets: [
        // The design system: generated tokens, the line grid, the primitives. No dependencies.
        .target(name: "TerminalDesign"),
        // commands.toml: the model, loading, validation, parameter substitution. Knows nothing of views.
        .target(name: "Registry", dependencies: [.product(name: "TOMLKit", package: "TOMLKit")], resources: [.copy("Resources/commands.example.toml")]),
        // Running a resolved command without a terminal: lines out, an exit code, redaction.
        .target(name: "Runner", dependencies: ["Registry"]),
        // Secrets by name, as generic-password items this app owns in the login keychain. Security framework only.
        .target(name: "Secrets"),
        // Scheduled commands as LaunchAgents: one per command with a schedule, kept in step with the registry.
        .target(name: "Scheduler", dependencies: ["Registry"]),
        // The app: the windows over the design, the registry and the runner; SwiftTerm for interactive runs.
        .executableTarget(name: "GreatGUI", dependencies: [
            "TerminalDesign", "Registry", "Runner", "Secrets", "Scheduler", .product(name: "SwiftTerm", package: "SwiftTerm"),
        ]),
        .testTarget(name: "TerminalDesignTests", dependencies: ["TerminalDesign"]),
        .testTarget(name: "RegistryTests", dependencies: ["Registry"]),
        .testTarget(name: "RunnerTests", dependencies: ["Runner", "Registry"]),
        .testTarget(name: "SecretsTests", dependencies: ["Secrets"]),
        .testTarget(name: "SchedulerTests", dependencies: ["Scheduler", "Registry"]),
        // The app's model and command line (added 2026-11-13: until then this target had no tests).
        .testTarget(name: "GreatGUITests", dependencies: ["GreatGUI", "Registry", "Scheduler", "Secrets"]),
    ],
    // Language mode 5 for now: strict concurrency is a review item (DECISIONS local-005), not a scaffold blocker.
    swiftLanguageModes: [.v5]
)
