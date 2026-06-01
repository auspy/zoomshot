// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZoomShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZoomShot",
            path: "Sources/ZoomShot",
            exclude: ["Resources/Info.plist", "Resources/ZoomShot.entitlements", "Resources/AppIcon.icns"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ZoomShot/Resources/Info.plist",
                ])
            ]
        )
    ]
)
