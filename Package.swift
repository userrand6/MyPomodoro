// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyPomodoro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PomodoroCore",
            targets: ["PomodoroCore"]
        ),
        .executable(
            name: "mypomodoro",
            targets: ["MyPomodoro"]
        )
    ],
    targets: [
        .target(
            name: "PomodoroCore"
        ),
        .executableTarget(
            name: "MyPomodoro",
            dependencies: ["PomodoroCore"]
        ),
        .testTarget(
            name: "PomodoroCoreTests",
            dependencies: ["PomodoroCore"]
        )
    ]
)
