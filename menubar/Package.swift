// swift-tools-version:5.9
import PackageDescription
import Foundation

// Built with Swift 5 language mode (relaxed concurrency) for a simple, reliable menu bar utility.
//
// The test target is declared ONLY when its sources exist. Staged / release builds copy Sources/ but not
// Tests/, and SwiftPM rejects a target whose `path` is missing — so a `swift build` of a Tests-less staged
// copy (e.g. the menu-bar auto-update on a fresh install) would otherwise fail. #filePath makes the check
// independent of the manifest's working directory.
let pkgDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

var targets: [Target] = [
    .executableTarget(
        name: "cdt-menubar",
        path: "Sources/cdt-menubar"
    )
]
if FileManager.default.fileExists(atPath: pkgDir + "/Tests/cdt-menubarTests") {
    targets.append(
        .testTarget(
            name: "cdt-menubarTests",
            dependencies: ["cdt-menubar"],
            path: "Tests/cdt-menubarTests"
        )
    )
}

let package = Package(
    name: "cdt-menubar",
    platforms: [.macOS(.v13)],
    targets: targets
)
