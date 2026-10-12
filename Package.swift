// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "cordova-plugin-google-login",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "cordova-plugin-google-login",
            targets: ["cordova-plugin-google-login"]
        )
    ],
    dependencies: [
        // cordova-ios rewrites this line to a local path when the plugin is installed.
        .package(url: "https://github.com/apache/cordova-ios.git", branch: "master"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "10.0.0")
    ],
    targets: [
        .target(
            name: "cordova-plugin-google-login",
            dependencies: [
                .product(name: "Cordova", package: "cordova-ios"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn")
            ],
            path: "src/ios",
            resources: [],
            publicHeadersPath: "."
        )
    ]
)
