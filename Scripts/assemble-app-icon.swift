import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: assemble-app-icon.swift INPUT_ICONSET_DIR OUTPUT_ICNS\n", stderr)
    exit(64)
}

let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let representations: [(String, String, String?)] = [
    ("icon_16x16.png", "is32", "s8mk"), ("icon_16x16@2x.png", "ic11", nil),
    ("icon_32x32.png", "il32", "l8mk"), ("icon_32x32@2x.png", "ic12", nil),
    ("icon_128x128.png", "ic07", nil), ("icon_128x128@2x.png", "ic13", nil),
    ("icon_256x256.png", "ic08", nil), ("icon_256x256@2x.png", "ic14", nil),
    ("icon_512x512.png", "ic09", nil), ("icon_512x512@2x.png", "ic10", nil)
]

func chunk(_ type: String, _ payload: Data) -> Data {
    var length = UInt32(payload.count + 8).bigEndian
    var data = Data(type.utf8)
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}

var payload = Data()
for (name, type, maskType) in representations {
    let png = try Data(contentsOf: inputDirectory.appendingPathComponent(name))
    if let maskType {
        guard let bitmap = NSBitmapImageRep(data: png), bitmap.bitsPerSample == 8,
              bitmap.samplesPerPixel == 3 || bitmap.samplesPerPixel == 4 else {
            fatalError("Could not decode 8-bit RGB icon representation: \(name)")
        }
        var rgb = Data()
        var alpha = Data()
        var pixel = [Int](repeating: 0, count: 4)
        let alphaFirst = bitmap.hasAlpha && bitmap.bitmapFormat.contains(.alphaFirst)
        let rgbOffset = alphaFirst ? 1 : 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                bitmap.getPixel(&pixel, atX: x, y: y)
                rgb.append(contentsOf: [
                    0, UInt8(pixel[rgbOffset]), UInt8(pixel[rgbOffset + 1]), UInt8(pixel[rgbOffset + 2])
                ])
                alpha.append(bitmap.hasAlpha ? UInt8(pixel[alphaFirst ? 0 : 3]) : 255)
            }
        }
        payload.append(chunk(type, rgb))
        payload.append(chunk(maskType, alpha))
    } else {
        payload.append(chunk(type, png))
    }
}
try chunk("icns", payload).write(to: outputURL, options: .atomic)
