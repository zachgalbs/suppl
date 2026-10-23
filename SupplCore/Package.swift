// swift-tools-version:5.9
import PackageDescription

// Platform-agnostic logic for suppl.: domain types, the reminder engine, catalog search, rules, and copy.
// Foundation only, so it builds and tests on Linux as well as in Xcode.
let package = Package(
    name: "SupplCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SupplCore", targets: ["SupplCore"]),
    ],
    targets: [
        .target(name: "SupplCore"),
        .testTarget(name: "SupplCoreTests", dependencies: ["SupplCore"]),
    ]
)
