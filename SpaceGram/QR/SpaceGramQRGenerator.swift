import CoreImage
import Foundation
import os.log
import UIKit

public enum SpaceGramQRGenerator {
    public static let maximumUTF8Bytes = 2000
    private static let maximumOutputDimension = 4096
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
        guard let modulesBitmap = CGContext(
            data: nil,
            width: moduleWidth,
            height: moduleHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            logFailure(stage: "module-context", payloadBytes: payload.count, width: moduleWidth, height: moduleHeight)
            return nil
        }
        modulesBitmap.setFillColor(UIColor.white.cgColor)
        modulesBitmap.fill(CGRect(x: 0, y: 0, width: CGFloat(moduleWidth), height: CGFloat(moduleHeight)))
        let renderContext = CIContext(cgContext: modulesBitmap, options: [.cacheIntermediates: false])
        renderContext.draw(output, in: CGRect(x: 0, y: 0, width: CGFloat(moduleWidth), height: CGFloat(moduleHeight)), from: extent)
        guard containsDarkPixel(modulesBitmap, width: moduleWidth, height: moduleHeight),
              let modules = modulesBitmap.makeImage() else {
            logFailure(stage: "module-render", payloadBytes: payload.count, width: moduleWidth, height: moduleHeight)
            return nil
        }
        let quietZone = 4
        let integerScale = Int(scale)
        let paddedWidth = modules.width + quietZone * 2
        let paddedHeight = modules.height + quietZone * 2
        guard paddedWidth <= maximumOutputDimension / integerScale,
              paddedHeight <= maximumOutputDimension / integerScale else {
            logFailure(stage: "output-bounds", payloadBytes: payload.count, width: paddedWidth * integerScale, height: paddedHeight * integerScale)
            return nil
        }
        let width = paddedWidth * integerScale
        let height = paddedHeight * integerScale
        guard let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            logFailure(stage: "output-context", payloadBytes: payload.count, width: width, height: height)
            return nil
        }
        bitmap.setFillColor(UIColor.white.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        bitmap.interpolationQuality = .none
        bitmap.draw(modules, in: CGRect(
            x: CGFloat(quietZone) * scale,
            y: CGFloat(quietZone) * scale,
            width: CGFloat(modules.width) * scale,
            height: CGFloat(modules.height) * scale
        ))
        guard let image = bitmap.makeImage() else {
            logFailure(stage: "output-image", payloadBytes: payload.count, width: width, height: height)
            return nil
        }
        guard image.width == width, image.height == height else {
            logFailure(stage: "output-dimensions", payloadBytes: payload.count, width: image.width, height: image.height)
            return nil
        }
        return UIImage(cgImage: image, scale: 1.0, orientation: .up)
    }

    private static func containsDarkPixel(_ context: CGContext, width: Int, height: Int) -> Bool {
        guard let data = context.data else { return false }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = y * bytesPerRow + x * 4
                if bytes[offset] < 128 || bytes[offset + 1] < 128 || bytes[offset + 2] < 128 {
                    return true
                }
            }
        }
        return false
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
