import AppKit
import Testing

@MainActor
struct AppIconRenderingTests {
    @Test func generatedAppIconHasAnOpaqueGradientAndCenteredRedCircle() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepless-icon-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let renderer = repositoryRoot.appendingPathComponent("Scripts/render-app-icon.swift")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [renderer.path, outputDirectory.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        try assertRedDotIcon(
            at: outputDirectory.appendingPathComponent("icon_16x16.png"), side: 16
        )
        try assertRedDotIcon(
            at: outputDirectory.appendingPathComponent("icon_512x512@2x.png"), side: 1024
        )
    }

    private struct IconPixel {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func assertRedDotIcon(at url: URL, side: Int) throws {
        let data = try Data(contentsOf: url)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide == side && bitmap.pixelsHigh == side)

        var pixels: [IconPixel] = []
        pixels.reserveCapacity(side * side)
        for y in 0..<side {
            for x in 0..<side {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                pixels.append(IconPixel(
                    red: color.redComponent, green: color.greenComponent,
                    blue: color.blueComponent, alpha: color.alphaComponent
                ))
            }
        }

        let center = CGFloat(side - 1) / 2
        let radius = CGFloat(side) * 0.20
        var transparentPixels = 0
        var nonRedChromaticPixels = 0
        var escapedDotPixels = 0
        var incompleteInteriorPixels = 0
        var horizontalGradientViolations = 0
        var dotPixels = 0
        var dotWeight: CGFloat = 0
        var dotCenterX: CGFloat = 0
        var dotCenterY: CGFloat = 0
        var minDotX = side
        var maxDotX = -1
        var minDotY = side
        var maxDotY = -1
        var minimumGray = CGFloat.greatestFiniteMagnitude
        var maximumGray: CGFloat = 0

        for y in 0..<side {
            let rowStart = y * side
            let rowReference = pixels[rowStart]
            for x in 0..<side {
                let pixel = pixels[rowStart + x]
                if pixel.alpha < 0.999 { transparentPixels += 1 }
                let redness = pixel.red - max(pixel.green, pixel.blue)
                let chroma = max(pixel.red, max(pixel.green, pixel.blue))
                    - min(pixel.red, min(pixel.green, pixel.blue))
                if redness > 0.01 {
                    dotPixels += 1
                    let weight = redness
                    let dx = CGFloat(x) - center
                    let dy = CGFloat(y) - center
                    let distance = (dx * dx + dy * dy).squareRoot()
                    dotWeight += weight
                    dotCenterX += CGFloat(x) * weight
                    dotCenterY += CGFloat(y) * weight
                    minDotX = min(minDotX, x)
                    maxDotX = max(maxDotX, x)
                    minDotY = min(minDotY, y)
                    maxDotY = max(maxDotY, y)
                    if distance > radius + 0.75 { escapedDotPixels += 1 }
                    if distance < radius * 0.55
                            && (pixel.red < 0.75 || pixel.green > 0.35 || pixel.blue > 0.35) {
                        incompleteInteriorPixels += 1
                    }
                } else {
                    if chroma > 0.025 { nonRedChromaticPixels += 1 }
                    let gray = (pixel.red + pixel.green + pixel.blue) / 3
                    minimumGray = min(minimumGray, gray)
                    maximumGray = max(maximumGray, gray)
                    if abs(pixel.red - rowReference.red) > 0.025
                            || abs(pixel.green - rowReference.green) > 0.025
                            || abs(pixel.blue - rowReference.blue) > 0.025 {
                        horizontalGradientViolations += 1
                    }
                }
            }
        }

        let top = pixels[0]
        let bottom = pixels[(side - 1) * side]
        let gradientSamples = [0, side / 4, side / 2, side * 3 / 4, side - 1]
            .map { pixels[$0 * side] }
        let topToBottomViolations = zip(gradientSamples, gradientSamples.dropFirst())
            .filter { previous, next in next.red > previous.red - 0.002 }
            .count
        let centerPixel = pixels[(side / 2) * side + side / 2]
        #expect(transparentPixels == 0)
        #expect(top.red > bottom.red + 0.08)
        #expect(top.red > 0.24 && top.red < 0.28)
        #expect(bottom.red > 0.11 && bottom.red < 0.16)
        #expect(abs(top.red - top.green) < 0.01 && abs(top.green - top.blue) < 0.01)
        #expect(abs(bottom.red - bottom.green) < 0.01 && abs(bottom.green - bottom.blue) < 0.01)
        #expect(topToBottomViolations == 0)
        #expect(horizontalGradientViolations == 0)
        #expect(minimumGray > 0.11 && maximumGray < 0.28)
        #expect(nonRedChromaticPixels == 0)
        #expect(dotPixels > side * side / 10 && dotPixels < side * side / 5)
        #expect(escapedDotPixels == 0)
        #expect(incompleteInteriorPixels == 0)
        #expect(maxDotX - minDotX + 1 >= side * 32 / 100)
        #expect(maxDotX - minDotX + 1 <= side / 2)
        #expect(maxDotY - minDotY + 1 >= side * 32 / 100)
        #expect(maxDotY - minDotY + 1 <= side / 2)
        #expect(dotWeight > 0)
        #expect(abs(dotCenterX / dotWeight - center) < 0.25)
        #expect(abs(dotCenterY / dotWeight - center) < 0.25)
        #expect(centerPixel.red > 0.85 && centerPixel.green < 0.35 && centerPixel.blue < 0.30)
        #expect(centerPixel.alpha > 0.999)
    }
}
