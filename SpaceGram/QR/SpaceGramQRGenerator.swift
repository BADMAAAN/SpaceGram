import CoreImage
import Foundation
import os.log
import UIKit

public enum SpaceGramQRGenerator {
    public static let maximumUTF8Bytes = 2000
    private static let maximumOutputDimension = 4096
    private static let renderContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: true
    ])
    private static let log = OSLog(subsystem: "org.telegram.SpaceGram", category: "QR")

    public static func image(text: String, scale: CGFloat = 8.0) -> UIImage? {
        let payload = Data(text.utf8)
        guard !payload.isEmpty, payload.count <= maximumUTF8Bytes else {
            logFailure(stage: "input-validation", payloadBytes: payload.count)
            return nil
        }
        guard scale.isFinite, scale >= 1.0, scale <= 16.0, scale.rounded(.down) == scale else {
            logFailure(stage: "scale-validation", payloadBytes: payload.count)
            return nil
        }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            logFailure(stage: "filter-creation", payloadBytes: payload.count)
            return nil
        }
        filter.setValue(payload as NSData, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            logFailure(stage: "filter-output", payloadBytes: payload.count)
            return nil
        }
        let extent = output.extent.integral
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty,
              extent.width <= 2048.0, extent.height <= 2048.0,
              extent.width.rounded(.down) == extent.width,
              extent.height.rounded(.down) == extent.height else {
            logFailure(stage: "extent-validation", payloadBytes: payload.count)
            return nil
        }

        let moduleWidth = Int(extent.width)
        let moduleHeight = Int(extent.height)
        let (moduleByteCount, moduleOverflow) = moduleWidth.multipliedReportingOverflow(by: moduleHeight)
        guard !moduleOverflow, moduleByteCount > 0 else {
            logFailure(stage: "module-bounds", payloadBytes: payload.count, width: moduleWidth, height: moduleHeight)
            return nil
        }
        var modulePixels = [UInt8](repeating: 255, count: moduleByteCount)
        modulePixels.withUnsafeMutableBytes { bytes in
            renderContext.render(
                output,
                toBitmap: bytes.baseAddress!,
                rowBytes: moduleWidth,
                bounds: extent,
                format: .L8,
                colorSpace: CGColorSpaceCreateDeviceGray()
            )
        }
        guard modulePixels.contains(where: { $0 < 128 }) else {
            logFailure(stage: "module-render", payloadBytes: payload.count, width: moduleWidth, height: moduleHeight)
            return nil
        }

        let quietZone = 4
        let integerScale = Int(scale)
        let paddedWidth = moduleWidth + quietZone * 2
        let paddedHeight = moduleHeight + quietZone * 2
        guard paddedWidth <= maximumOutputDimension / integerScale,
              paddedHeight <= maximumOutputDimension / integerScale else {
            logFailure(stage: "output-bounds", payloadBytes: payload.count, width: paddedWidth * integerScale, height: paddedHeight * integerScale)
            return nil
        }
        let width = paddedWidth * integerScale
        let height = paddedHeight * integerScale
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, outputByteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !outputByteOverflow else {
            logFailure(stage: "output-bounds", payloadBytes: payload.count, width: width, height: height)
            return nil
        }
        var pixels = [UInt8](repeating: 255, count: byteCount)
        for moduleY in 0 ..< moduleHeight {
            // Core Image's bitmap origin is lower-left; CGImage providers use a
            // top row first, so reverse rows while materializing the modules.
            let sourceY = moduleHeight - moduleY - 1
            for moduleX in 0 ..< moduleWidth {
                let moduleOffset = sourceY * moduleWidth + moduleX
                guard modulePixels[moduleOffset] < 128 else {
                    continue
                }
                let firstX = (moduleX + quietZone) * integerScale
                let firstY = (moduleY + quietZone) * integerScale
                for y in firstY ..< firstY + integerScale {
                    let rowOffset = y * width * 4
                    for x in firstX ..< firstX + integerScale {
                        let offset = rowOffset + x * 4
                        pixels[offset] = 0
                        pixels[offset + 1] = 0
                        pixels[offset + 2] = 0
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            logFailure(stage: "output-image", payloadBytes: payload.count, width: width, height: height)
            return nil
        }
        return UIImage(cgImage: image, scale: 1.0, orientation: .up)
    }

    private static func logFailure(stage: String, payloadBytes: Int, width: Int = 0, height: Int = 0) {
        os_log(
            "Generation failed stage=%{public}@ utf8Bytes=%{public}d dimensions=%{public}dx%{public}d",
            log: log,
            type: .error,
            stage,
            payloadBytes,
            width,
            height
        )
    }
}
