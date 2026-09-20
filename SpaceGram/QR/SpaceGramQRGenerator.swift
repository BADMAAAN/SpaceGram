import CoreImage
import Foundation
import UIKit

public enum SpaceGramQRGenerator {
    public static let maximumUTF8Bytes = 2000
    // This small, bounded raster must also work without a Metal device (for
    // example in headless simulator runs). CPU rendering avoids that dependency.
    private static let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])

    public static func image(text: String, scale: CGFloat = 8.0) -> UIImage? {
        guard scale.isFinite, scale >= 1.0, scale <= 16.0, scale.rounded(.down) == scale,
              let data = text.data(using: .utf8), !data.isEmpty, data.count <= maximumUTF8Bytes,
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            return nil
        }
        let extent = output.extent.integral
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty,
              extent.width <= 2048.0, extent.height <= 2048.0 else {
            return nil
        }
        // Four whole modules of opaque quiet zone on every side. Render at an
        // integer scale, with a bounded allocation even for a dense QR code.
        let paddedExtent = extent.insetBy(dx: -4.0, dy: -4.0)
        let opaque = output.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1))).cropped(to: paddedExtent)
        let scaled = opaque.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent.integral) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
