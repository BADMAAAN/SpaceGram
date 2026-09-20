import CoreGraphics
import Foundation
import ImageIO
import os.log

public enum SpaceGramMetadataSanitizer {
    private static let log = OSLog(subsystem: "org.telegram.SpaceGram", category: "MetadataSanitizer")
    private static let maximumPixelCount = 64 * 1024 * 1024
    private static let allowedEncoderExifKeys: Set<String> = [
        kCGImagePropertyExifColorSpace as String,
        kCGImagePropertyExifPixelXDimension as String,
        kCGImagePropertyExifPixelYDimension as String
    ]

    // Re-encodes one still image into the same supported container. Orientation
    // is baked into a fresh pixel buffer; no source metadata is copied.
    public static func sanitizeStillImage(_ data: Data) -> Data? {
        guard !data.isEmpty else {
            logFailure(stage: "input-validation", inputBytes: data.count)
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            logFailure(stage: "source-creation", inputBytes: data.count)
            return nil
        }
        guard CGImageSourceGetCount(source) == 1 else {
            logFailure(stage: "frame-count", inputBytes: data.count)
            return nil
        }
        guard let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              isSafeImageSize(width: width.intValue, height: height.intValue) else {
            logFailure(stage: "source-properties", inputBytes: data.count)
            return nil
        }
        guard let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            logFailure(stage: "source-decode", inputBytes: data.count, width: width.intValue, height: height.intValue)
            return nil
        }
        let rawOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation),
              let image = normalizedImage(sourceImage, orientation: orientation) else {
            logFailure(stage: "pixel-transform", inputBytes: data.count, width: sourceImage.width, height: sourceImage.height)
            return nil
        }
        let sourceHasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue == true

        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, type, 1, nil) else {
            logFailure(stage: "destination-creation", inputBytes: data.count, width: image.width, height: image.height)
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            logFailure(stage: "destination-finalize", inputBytes: data.count, width: image.width, height: image.height)
            return nil
        }
        guard let outputSource = CGImageSourceCreateWithData(result as CFData, nil),
              CGImageSourceGetCount(outputSource) == 1,
              CGImageSourceGetType(outputSource) == type,
              let outputImage = CGImageSourceCreateImageAtIndex(outputSource, 0, nil),
              outputImage.width == image.width,
              outputImage.height == image.height,
              !sourceHasAlpha || hasAlpha(outputImage),
              let outputProperties = CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [CFString: Any] else {
            logFailure(stage: "output-decode", inputBytes: data.count, width: image.width, height: image.height)
            return nil
        }
        let exifKeys = Set((outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]).keys.map { $0 as String })
        guard outputProperties[kCGImagePropertyGPSDictionary] == nil,
              outputProperties[kCGImagePropertyIPTCDictionary] == nil,
              outputProperties[kCGImagePropertyTIFFDictionary] == nil,
              outputProperties[kCGImagePropertyXMPDictionary] == nil,
              outputProperties[kCGImagePropertyOrientation] == nil,
              exifKeys.isSubset(of: allowedEncoderExifKeys) else {
            let dictionaries = metadataDictionaryNames(in: outputProperties)
            logFailure(stage: "output-metadata", inputBytes: data.count, width: outputImage.width, height: outputImage.height, dictionaries: dictionaries)
            return nil
        }
        return result as Data
    }

    private static func normalizedImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard isSafeImageSize(width: sourceWidth, height: sourceHeight) else { return nil }

        let swapsDimensions: Bool
        switch orientation {
        case .leftMirrored, .right, .rightMirrored, .left:
            swapsDimensions = true
        default:
            swapsDimensions = false
        }
        let outputWidth = swapsDimensions ? sourceHeight : sourceWidth
        let outputHeight = swapsDimensions ? sourceWidth : sourceHeight
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        let width = CGFloat(sourceWidth)
        let height = CGFloat(sourceHeight)
        var transform = CGAffineTransform.identity
        switch orientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: width, y: height).rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: width, y: 0.0).rotated(by: .pi / 2.0)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0.0, y: height).rotated(by: -.pi / 2.0)
        default:
            break
        }
        switch orientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: width, y: 0.0).scaledBy(x: -1.0, y: 1.0)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: height, y: 0.0).scaledBy(x: -1.0, y: 1.0)
        default:
            break
        }
        context.concatenate(transform)
        context.interpolationQuality = .none
        let drawRect = swapsDimensions
            ? CGRect(x: 0.0, y: 0.0, width: height, height: width)
            : CGRect(x: 0.0, y: 0.0, width: width, height: height)
        context.draw(image, in: drawRect)
        return context.makeImage()
    }

    private static func isSafeImageSize(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixelCount <= maximumPixelCount
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }

    private static func metadataDictionaryNames(in properties: [CFString: Any]) -> String {
        return [
            ("GPS", kCGImagePropertyGPSDictionary),
            ("EXIF", kCGImagePropertyExifDictionary),
            ("IPTC", kCGImagePropertyIPTCDictionary),
            ("TIFF", kCGImagePropertyTIFFDictionary),
            ("XMP", kCGImagePropertyXMPDictionary)
        ].compactMap { name, key in properties[key] == nil ? nil : name }.joined(separator: ",")
    }

    private static func logFailure(stage: String, inputBytes: Int, width: Int = 0, height: Int = 0, dictionaries: String = "") {
        os_log(
            "Sanitization failed stage=%{public}@ inputBytes=%{public}d dimensions=%{public}dx%{public}d metadata=%{public}@",
            log: log,
            type: .error,
            stage,
            inputBytes,
            width,
            height,
            dictionaries
        )
    }
}
