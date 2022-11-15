// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "fltrVault",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "fltrVault",
            targets: ["fltrVault"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", branch: "main"),
        .package(url: "https://github.com/fltrWallet/bech32", branch: "main"),
        .package(url: "https://github.com/fltrWallet/FileRepo", branch: "main"),
        .package(url: "https://github.com/fltrWallet/fltrECC", branch: "main"),
        .package(url: "https://github.com/fltrWallet/fltrTx", branch: "main"),
        .package(url: "https://github.com/fltrWallet/fltrWAPI", branch: "main"),
        .package(url: "https://github.com/fltrWallet/HaByLo", branch: "main"),
        .package(url: "https://github.com/fltrWallet/KeyChainClient", branch: "main"),
        .package(url: "https://github.com/fltrWallet/UserDefaultsClient", branch: "main"),
        .package(url: "https://github.com/fltrWallet/Stream64", branch: "main"),
    ],
    targets: [
        .target(
            name: "fltrVault",
            dependencies: [ "bech32",
                            "fltrECC",
                            "FileRepo",
                            "fltrTx",
                            "fltrWAPI",
                            "HaByLo",
                            "Stream64",
                            .product(name: "KeyChainClientLive",
                                     package: "KeyChainClient"),
                            .product(name: "NIO",
                                     package: "swift-nio"),
                            .product(name: "NIOTransportServices",
                                     package: "swift-nio-transport-services"),
                            .product(name: "UserDefaultsClientLive",
                                     package: "UserDefaultsClient"), ],
            resources: [ .process("Resources"), ]),
        .target(
            name: "VaultTestLibrary",
            dependencies: [ "fltrWAPI",
                            "fltrVault",
                            .product(name: "KeyChainClientTest",
                                     package: "KeyChainClient"),
                            .product(name: "UserDefaultsClientTest",
                                     package: "UserDefaultsClient"), ]),
        .testTarget(
            name: "fltrVaultTests",
            dependencies: [ "fltrVault",
                            "fltrWAPI",
                            .product(name: "fltrECCTesting", package: "fltrECC"),
                            "VaultTestLibrary", ],
            resources: [ .process("Resources"), ]),
    ]
)
