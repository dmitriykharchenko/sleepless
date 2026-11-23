import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-app-icon.swift OUTPUT_ICONSET_DIR\n", stderr)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let representations: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1),
        CGColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
let dotColor = CGColor(srgbRed: 0.90, green: 0.22, blue: 0.21, alpha: 1)

for (name, pixels) in representations {
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        fatalError("Could not create \(pixels)px icon representation")
    }
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: pixels),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    let radius = CGFloat(pixels) * 0.20
    context.setFillColor(dotColor)
    context.fillEllipse(in: CGRect(
        x: CGFloat(pixels) / 2 - radius, y: CGFloat(pixels) / 2 - radius,
        width: radius * 2, height: radius * 2
    ))
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(pixels)px icon representation")
    }
    try png.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}