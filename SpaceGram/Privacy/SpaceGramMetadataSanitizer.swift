import Foundation
import ImageIO
import os.log

public enum SpaceGramMetadataSanitizer {
    private static let log = OSLog(subsystem: "org.telegram.SpaceGram", category: "MetadataSanitizer")
    private static let allowedEncoderExifKeys: Set<String> = [
        kCGImagePropertyExifColorSpace as String,
        kCGImagePropertyExifPixelXDimension as String,
        kCGImagePropertyExifPixelYDimension as String
    ]

    // Re-encodes one still image into the same supported container. Pixel data
    // and orientation are retained; EXIF, GPS and other source metadata are not.
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
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            logFailure(stage: "source-properties", inputBytes: data.count)
            return nil
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue)
        ] as CFDictionary) else {
            logFailure(stage: "pixel-transform", inputBytes: data.count, width: width.intValue, height: height.intValue)
            return nil
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, type, 1, nil) else {
            logFailure(stage: "destination-creation", inputBytes: data.count, width: image.width, height: image.height)
            return nil
        }
        // The thumbnail transform normalizes orientation into pixels, so no
        // source properties are copied. Explicit nulls also prevent ImageIO from
        // synthesizing optional TIFF/IPTC dictionaries for the new container.
        let strippedProperties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: NSNull(),
            kCGImagePropertyGPSDictionary: NSNull(),
            kCGImagePropertyIPTCDictionary: NSNull(),
            kCGImagePropertyTIFFDictionary: NSNull()
        ]
        CGImageDestinationAddImage(destination, image, strippedProperties as CFDictionary)
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
              let outputProperties = CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [CFString: Any] else {
            logFailure(stage: "output-decode", inputBytes: data.count, width: image.width, height: image.height)
            return nil
        }
        let exifKeys = Set((outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]).keys.map { $0 as String })
        guard outputProperties[kCGImagePropertyGPSDictionary] == nil,
              outputProperties[kCGImagePropertyIPTCDictionary] == nil,
              outputProperties[kCGImagePropertyTIFFDictionary] == nil,
              outputProperties[kCGImagePropertyOrientation] == nil,
              exifKeys.isSubset(of: allowedEncoderExifKeys) else {
            let dictionaries = metadataDictionaryNames(in: outputProperties)
            logFailure(stage: "output-metadata", inputBytes: data.count, width: outputImage.width, height: outputImage.height, dictionaries: dictionaries)
            return nil
        }
        return result as Data
    }

    private static func metadataDictionaryNames(in properties: [CFString: Any]) -> String {
        return [
            ("GPS", kCGImagePropertyGPSDictionary),
            ("EXIF", kCGImagePropertyExifDictionary),
            ("IPTC", kCGImagePropertyIPTCDictionary),
            ("TIFF", kCGImagePropertyTIFFDictionary)
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
