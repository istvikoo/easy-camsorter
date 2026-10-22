// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EasyCamSorter",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Автооновлення з GitHub Releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Логіка сортування без інтерфейсу — її покривають тести.
        .target(name: "SorterCore"),
        // Застосунок на SwiftUI.
        .executableTarget(
            name: "EasyCamSorter",
            dependencies: ["SorterCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Sparkle.framework лежить у Contents/Frameworks всередині .app.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "SorterCoreTests", dependencies: ["SorterCore"]),
    ]
)
