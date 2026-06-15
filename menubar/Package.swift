// swift-tools-version:5.9
import PackageDescription

// Built with Swift 5 language mode (relaxed concurrency) for a simple, reliable menu bar utility.
let package = Package(
    name: "cdt-menubar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "cdt-menubar",
            path: "Sources/cdt-menubar"
        )
    ]
)
