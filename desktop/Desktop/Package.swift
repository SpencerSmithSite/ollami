// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Omi Computer",
  platforms: [
    .macOS("14.0")
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    .package(
      url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", from: "1.20.0"),
  ],
  targets: [
    .target(
      name: "ObjCExceptionCatcher",
      path: "ObjCExceptionCatcher",
      publicHeadersPath: "include"
    ),
    .executableTarget(
      name: "Omi Computer",
      dependencies: [
        "ObjCExceptionCatcher",
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "Sparkle", package: "Sparkle"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
      ],
      path: "Sources",
      resources: [
        .process("Resources"),
      ]
    ),
    .testTarget(
      name: "Omi ComputerTests",
      dependencies: [
        .target(name: "Omi Computer")
      ],
      path: "Tests"
    ),
  ]
)
