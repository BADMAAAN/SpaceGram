import Foundation
import ImageIO

public enum QwengramMetadataSanitizer {
    // Re-encodes one still image into the same supported container. Pixel data
    // and orientation are retained; EXIF, GPS and other source metadata are not.
    public static func sanitizeStillImage(_ data: Data) -> Data? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, type, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientation = sourceProperties[kCGImagePropertyOrientation] {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }
}
