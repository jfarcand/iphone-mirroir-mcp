// ABOUTME: Tests for GridOverlay coordinate grid rendering on screenshot PNG data.
// ABOUTME: Validates output dimensions, grid line pixel presence, and invalid input handling.

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HelperLib

@Suite("GridOverlay")
struct GridOverlayTests {

    /// Create a solid-color PNG of the given pixel dimensions for testing.
    private func makePNG(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1.0]
            )!
        )
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, "public.png" as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// Helper to decode PNG data into a CGImage.
    private func decodePNG(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Read a specific pixel's RGBA values from a CGImage.
    private func pixelAt(x: Int, y: Int, in image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    @Test("output PNG has same pixel dimensions as input")
    func outputDimensions() {
        let png = makePNG(width: 820, height: 1796, r: 0, g: 0, b: 0)
        let windowSize = CGSize(width: 410, height: 898)

        let result = GridOverlay.addOverlay(to: png, windowSize: windowSize)
        #expect(result != nil)
        let resultImage = decodePNG(result!)!
        #expect(resultImage.width == 820)
        #expect(resultImage.height == 1796)
    }

    @Test("returns nil for invalid PNG data")
    func invalidInput() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        let result = GridOverlay.addOverlay(to: garbage, windowSize: CGSize(width: 100, height: 100))
        #expect(result == nil)
    }

    @Test("grid line pixels differ from solid background at expected positions")
    func gridLinePresence() {
        // 200x200 pixel image, 100x100pt window → scale factor 2.0
        // Grid line at x=50pt → pixel x=100
        let png = makePNG(width: 200, height: 200, r: 0, g: 0, b: 0)
        let windowSize = CGSize(width: 100, height: 100)

        let result = GridOverlay.addOverlay(to: png, windowSize: windowSize)!
        let image = decodePNG(result)!

        // Pixel at (100, 100) should be on a grid line intersection — not pure black anymore
        let gridPixel = pixelAt(x: 100, y: 100, in: image)
        let isModified = gridPixel.r > 0 || gridPixel.g > 0 || gridPixel.b > 0
        #expect(isModified, "Pixel at grid line intersection should be modified from pure black")

        // Pixel at (50, 50) is between grid lines and far from labels — should remain black
        let cleanPixel = pixelAt(x: 50, y: 50, in: image)
        #expect(cleanPixel.r == 0 && cleanPixel.g == 0 && cleanPixel.b == 0,
                "Pixel between grid lines should remain unchanged")
    }

    @Test("grid spacing constant is 50 points")
    func gridSpacingValue() {
        #expect(GridOverlay.gridSpacing == 50.0)
    }

    @Test("label background pixels are non-transparent near grid line origin")
    func labelBackgroundPresence() {
        // 400x400 pixel image, 200x200pt window → scale factor 2.0
        // Horizontal grid at y=50pt → CG pixel y=300 (from bottom).
        // Label pill drawn at CG (4, 302) → top-down ≈ y=97.
        // Scan a region around the expected label position.
        let png = makePNG(width: 400, height: 400, r: 255, g: 255, b: 255)
        let windowSize = CGSize(width: 200, height: 200)

        let result = GridOverlay.addOverlay(to: png, windowSize: windowSize)!
        let image = decodePNG(result)!

        // Scan a 20x20 region near the expected label position for any modified pixel.
        var foundDarker = false
        for dy in 85...105 {
            for dx in 2...20 {
                let p = pixelAt(x: dx, y: dy, in: image)
                if p.r < 255 || p.g < 255 || p.b < 255 {
                    foundDarker = true
                    break
                }
            }
            if foundDarker { break }
        }
        #expect(foundDarker, "Label region near horizontal grid line should contain non-white pixels")
    }
}
