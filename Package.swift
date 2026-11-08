// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Harbor",
            path: "Sources/Harbor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Accelerate"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
