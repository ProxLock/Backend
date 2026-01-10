// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ProxLock",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        // 🐘 Fluent driver for Postgres.
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),
        .package(url: "https://github.com/mcrich23/vapordevicecheck.git", from: "1.1.3"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(url: "https://github.com/mcrich23/google-cloud-kit.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ProxLock",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "VaporDeviceCheck", package: "VaporDeviceCheck"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "GoogleCloudKit", package: "google-cloud-kit"),
            ],
            swiftSettings: swiftSettings
        )
        //        .testTarget(
        //            name: "ProxLockTests",
        //            dependencies: [
        //                .target(name: "ProxLock"),
        //                .product(name: "VaporTesting", package: "vapor"),
        //            ],
        //            swiftSettings: swiftSettings
        //        )
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny")
    ]
}
