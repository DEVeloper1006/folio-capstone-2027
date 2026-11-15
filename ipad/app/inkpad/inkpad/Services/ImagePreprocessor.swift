import Foundation
import CoreGraphics

nonisolated enum ImagePreparationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

nonisolated struct ImagePreparationInfo: Codable, Sendable {
    let inputWidth: Int
    let inputHeight: Int
    let cropX: Int
    let cropY: Int
    let cropWidth: Int
    let cropHeight: Int
    let resizedWidth: Int
    let resizedHeight: Int
}

nonisolated struct PreparedImage: Sendable {
    let values: [Float]
    let info: ImagePreparationInfo
}

/// PIL-compatible crop, antialiased bicubic resize, and normalized-space padding.
/// This file also compiles on macOS for differential checks against the worker.
nonisolated enum ImagePreprocessor {
    static let edge = 448

    static func grayscale(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 8192, height <= 8192 else {
            throw ImagePreparationError.invalid("Image dimensions are unsupported")
        }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw ImagePreparationError.invalid("Could not read image pixels") }
        return (0..<(width * height)).map { i in
            let k = i * 4
            let red = Int(rgba[k]) * 19595
            let green = Int(rgba[k + 1]) * 38470
            let blue = Int(rgba[k + 2]) * 7471
            return UInt8((red + green + blue + 32768) >> 16)
        }
    }

    static func prepare(_ image: CGImage) throws -> PreparedImage {
        try prepare(gray: grayscale(image), width: image.width, height: image.height)
    }

    static func prepare(gray: [UInt8], width: Int, height: Int) throws -> PreparedImage {
        guard width > 0, height > 0, gray.count == width * height else {
            throw ImagePreparationError.invalid("Invalid grayscale image")
        }
        var left = width, top = height, right = -1, bottom = -1
        for y in 0..<height {
            for x in 0..<width where gray[y * width + x] < 240 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else {
            throw ImagePreparationError.invalid("No handwriting found. Write an expression first.")
        }
        let cropWidth = right - left + 1, cropHeight = bottom - top + 1
        var cropped = [UInt8](); cropped.reserveCapacity(cropWidth * cropHeight)
        for y in top...bottom { cropped.append(contentsOf: gray[(y * width + left)...(y * width + right)]) }
        let ratio = Double(edge) / Double(max(cropWidth, cropHeight))
        let resizedWidth = max(1, Int(Double(cropWidth) * ratio))
        let resizedHeight = max(1, Int(Double(cropHeight) * ratio))
        let resized = resize(cropped, width: cropWidth, height: cropHeight,
                             outputWidth: resizedWidth, outputHeight: resizedHeight)
        var values = [Float](repeating: 0, count: edge * edge)
        for y in 0..<resizedHeight {
            for x in 0..<resizedWidth {
                values[y * edge + x] = (Float(resized[y * resizedWidth + x]) / 255 - Float(0.9545467)) / Float(0.15394445)
            }
        }
        return PreparedImage(values: values, info: ImagePreparationInfo(inputWidth: width, inputHeight: height,
            cropX: left, cropY: top, cropWidth: cropWidth, cropHeight: cropHeight,
            resizedWidth: resizedWidth, resizedHeight: resizedHeight))
    }

    private static func cubic(_ value: Double) -> Double {
        let x = abs(value)
        if x < 1 { return ((1.5 * x - 2.5) * x) * x + 1 }
        if x < 2 { return (((x - 5) * x + 8) * x - 4) * -0.5 }
        return 0
    }

    private static func coefficients(input: Int, output: Int) -> [(Int, [Int])] {
        let scale = Double(input) / Double(output), filterScale = max(scale, 1)
        let support = 2 * filterScale, precision = Double(1 << 22)
        return (0..<output).map { position in
            let center = (Double(position) + 0.5) * scale
            let first = max(0, Int(center - support + 0.5))
            let end = min(input, Int(center + support + 0.5))
            let weights = (first..<end).map { cubic((Double($0) - center + 0.5) / filterScale) }
            let sum = weights.reduce(0, +)
            return (first, weights.map { weight in
                let scaled = weight / sum * precision
                return Int(scaled + (scaled < 0 ? -0.5 : 0.5))
            })
        }
    }

    private static func resize(_ input: [UInt8], width: Int, height: Int, outputWidth: Int, outputHeight: Int) -> [UInt8] {
        var horizontal = input
        if width != outputWidth {
            horizontal = [UInt8](repeating: 0, count: outputWidth * height)
            let table = coefficients(input: width, output: outputWidth)
            for y in 0..<height {
                for x in 0..<outputWidth {
                    let (first, weights) = table[x]
                    var value = 1 << 21
                    for (offset, weight) in weights.enumerated() { value += Int(input[y * width + first + offset]) * weight }
                    horizontal[y * outputWidth + x] = UInt8(clamping: value >> 22)
                }
            }
        }
        guard height != outputHeight else { return horizontal }
        var result = [UInt8](repeating: 0, count: outputWidth * outputHeight)
        let table = coefficients(input: height, output: outputHeight)
        for y in 0..<outputHeight {
            let (first, weights) = table[y]
            for x in 0..<outputWidth {
                var value = 1 << 21
                for (offset, weight) in weights.enumerated() { value += Int(horizontal[(first + offset) * outputWidth + x]) * weight }
                result[y * outputWidth + x] = UInt8(clamping: value >> 22)
            }
        }
        return result
    }
}
