// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(
            name: "MacResourceMonitor",
            targets: ["MacResourceMonitor"]
        )
    ],
    dependencies: [
        // 依赖项（如果需要添加更多依赖）
    ],
    targets: [
        .executableTarget(
            name: "MacResourceMonitor",
            dependencies: [],
            path: "."
        )
    ]
) 