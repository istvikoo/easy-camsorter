// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EasyCamSorter",
    platforms: [.macOS(.v14)],
    targets: [
        // Логіка сортування без інтерфейсу — її покривають тести.
        .target(name: "SorterCore"),
        // Застосунок на SwiftUI.
        .executableTarget(name: "EasyCamSorter", dependencies: ["SorterCore"]),
        .testTarget(name: "SorterCoreTests", dependencies: ["SorterCore"]),
    ]
)
