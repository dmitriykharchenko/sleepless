import AppKit
import Testing

@MainActor struct AppIconPackagingTests {
    @Test func assembledAppIconPreservesAllTenRepresentations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepless-icns-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("Source.iconset")
        let extracted = temporary.appendingPathComponent("Extracted.iconset")
        let icns = temporary.appendingPathComponent("AppIcon.icns")
        try runIconTool("/usr/bin/swift", [root.appendingPathComponent("Scripts/render-app-icon.swift").path, source.path])
        try runIconTool("/usr/bin/swift", [
            root.appendingPathComponent("Scripts/assemble-app-icon.swift").path, source.path, icns.path
        ])
        try runIconTool("/usr/bin/iconutil", ["-c", "iconset", "-o", extracted.path, icns.path])

        let representations: [(String, Int, Int, String, String?)] = [
            ("icon_16x16.png", 16, 16, "is32", "s8mk"),
            ("icon_16x16@2x.png", 32, 16, "ic11", nil),
            ("icon_32x32.png", 32, 32, "il32", "l8mk"),
            ("icon_32x32@2x.png", 64, 32, "ic12", nil),
            ("icon_128x128.png", 128, 128, "ic07", nil),
            ("icon_128x128@2x.png", 256, 128, "ic13", nil),
            ("icon_256x256.png", 256, 256, "ic08", nil),
            ("icon_256x256@2x.png", 512, 256, "ic14", nil),
            ("icon_512x512.png", 512, 512, "ic09", nil),
            ("icon_512x512@2x.png", 1024, 512, "ic10", nil)
        ]
        let image = try #require(NSImage(contentsOf: icns))
        let native = image.representations.compactMap { $0 as? NSBitmapImageRep }
        #expect(native.count == representations.count)
        let stored = try icnsPayloads(Data(contentsOf: icns))
        for (name, side, points, type, maskType) in representations {
            let png = try Data(contentsOf: source.appendingPathComponent(name))
            let original = try #require(NSBitmapImageRep(data: png))
            let expected = try rgbaPixels(original)
            let unpacked = try #require(NSBitmapImageRep(data: Data(contentsOf: extracted.appendingPathComponent(name))))
            #expect(unpacked.pixelsWide == side && unpacked.pixelsHigh == side)
            let extractedPixels = try rgbaPixels(unpacked)
            let changedBytes = zip(expected, extractedPixels).filter { $0 != $1 }.count
            #expect(expected.count == extractedPixels.count && changedBytes == 0, "Extracted pixels: \(name)")
            let direct = try #require(native.first {
                $0.pixelsWide == side && $0.pixelsHigh == side && $0.size.width == CGFloat(points)
            })
            let directPixels = try rgbaPixels(direct)
            let nativeChanges = zip(expected, directPixels).filter { $0 != $1 }.count
            #expect(expected.count == directPixels.count && nativeChanges == 0, "Native ICNS pixels: \(name)")
            var nonNeutralBackground = 0
            for y in 0..<side {
                for x in 0..<side {
                    let offset = (y * side + x) * 4
                    if expected[offset] == expected[offset + 1] && expected[offset + 1] == expected[offset + 2] {
                        if extractedPixels[offset] != extractedPixels[offset + 1]
                                || extractedPixels[offset + 1] != extractedPixels[offset + 2] {
                            nonNeutralBackground += 1
                        }
                    }
                }
            }
            #expect(nonNeutralBackground == 0, "Neutral packaged background: \(name)")
            if let maskType {
                var rgb = Data()
                var alpha = Data()
                for offset in stride(from: 0, to: expected.count, by: 4) {
                    rgb.append(contentsOf: [0, expected[offset], expected[offset + 1], expected[offset + 2]])
                    alpha.append(expected[offset + 3])
                }
                #expect(stored[type] == rgb)
                #expect(stored[maskType] == alpha)
            } else {
                #expect(stored[type] == png)
            }
        }
    }

    private func runIconTool(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }

    private func rgbaPixels(_ bitmap: NSBitmapImageRep) throws -> Data {
        try #require(bitmap.bitsPerSample == 8 && (bitmap.samplesPerPixel == 3 || bitmap.samplesPerPixel == 4))
        let alphaFirst = bitmap.hasAlpha && bitmap.bitmapFormat.contains(.alphaFirst)
        let rgbOffset = alphaFirst ? 1 : 0
        var result = Data()
        var pixel = [Int](repeating: 0, count: 4)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                bitmap.getPixel(&pixel, atX: x, y: y)
                result.append(contentsOf: [
                    UInt8(pixel[rgbOffset]), UInt8(pixel[rgbOffset + 1]), UInt8(pixel[rgbOffset + 2]),
                    bitmap.hasAlpha ? UInt8(pixel[alphaFirst ? 0 : 3]) : 255
                ])
            }
        }
        return result
    }

    private func icnsPayloads(_ data: Data) throws -> [String: Data] {
        try #require(data.prefix(4) == Data("icns".utf8))
        try #require(data[4..<8].reduce(0) { $0 * 256 + Int($1) } == data.count)
        var result: [String: Data] = [:]
        var offset = 8
        while offset < data.count {
            try #require(offset + 8 <= data.count)
            let length = data[(offset + 4)..<(offset + 8)].reduce(0) { $0 * 256 + Int($1) }
            try #require(length >= 8 && offset + length <= data.count)
            let type = try #require(String(data: data[offset..<(offset + 4)], encoding: .ascii))
            result[type] = data[(offset + 8)..<(offset + length)]
            offset += length
        }
        return result
    }
}
