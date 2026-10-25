// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StatusBoardCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "StatusBoardCore", targets: ["StatusBoardCore"]),
               .library(name: "StatusBoardDesktop", targets: ["StatusBoardDesktop"])],
    targets: [
        .target(name: "StatusBoardCore"),
        .target(name: "StatusBoardSQLite", exclude: ["vendor/upstream.json", "vendor/README.md"],
                sources: ["SQLite.c"], publicHeadersPath: "include",
                cSettings: [.define("SQLITE_THREADSAFE", to: "1"), .define("SQLITE_OMIT_LOAD_EXTENSION"), .define("SQLITE_DQS", to: "0")]),
        .target(name: "StatusBoardDesktop", dependencies: ["StatusBoardCore", "StatusBoardSQLite"], resources: [.process("Resources")]),
        .testTarget(name: "StatusBoardCoreTests", dependencies: ["StatusBoardCore", "StatusBoardDesktop"])
    ],
    swiftLanguageModes: [.v6]
)
