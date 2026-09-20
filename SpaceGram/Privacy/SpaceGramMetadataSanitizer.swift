import Foundation
import ImageIO

public enum SpaceGramMetadataSanitizer {
    // Re-encodes one still image into the same supported container. Pixel data
    // and orientation are retained; EXIF, GPS and other source metadata are not.
    public static func sanitizeStillImage(_ data: Data) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue)
              ] as CFDictionary) else {
            return nil
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, type, 1, nil) else {
            return nil
        }
        // The thumbnail transform normalizes orientation into pixels, so no
        // source properties need to be copied into the new image.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
              let outputSource = CGImageSourceCreateWithData(result as CFData, nil),
              let outputProperties = CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [CFString: Any],
              outputProperties[kCGImagePropertyGPSDictionary] == nil,
              outputProperties[kCGImagePropertyExifDictionary] == nil,
              outputProperties[kCGImagePropertyIPTCDictionary] == nil,
              outputProperties[kCGImagePropertyTIFFDictionary] == nil else {
            return nil
        }
        return result as Data
    }
}
