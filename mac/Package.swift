// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SlapBattle",
  platforms: [.macOS(.v14)],
  targets: [.executableTarget(name: "SlapBattle", path: "Sources")]
)
