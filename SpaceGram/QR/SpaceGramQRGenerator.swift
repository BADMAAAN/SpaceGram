import CoreImage
import Foundation
import UIKit

public enum SpaceGramQRGenerator {
    public static let maximumUTF8Bytes = 2000
    private static let context = CIContext(options: [.cacheIntermediates: false])

    public static func image(text: String, scale: CGFloat = 8.0) -> UIImage? {
        let payload = Data(text.utf8)
        guard scale.isFinite, scale >= 1.0, scale <= 16.0, scale.rounded(.down) == scale,
              !payload.isEmpty, payload.count <= maximumUTF8Bytes,
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(payload, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            return nil
        }
        let extent = output.extent.integral
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty,
              extent.width <= 2048.0, extent.height <= 2048.0 else {
            return nil
        }
        guard let modules = context.createCGImage(output, from: extent) else {
            return nil
        }
        let quietZone = 4
        let width = (modules.width + quietZone * 2) * Int(scale)
        let height = (modules.height + quietZone * 2) * Int(scale)
        guard let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
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
            return nil
        }
        return UIImage(cgImage: image, scale: 1.0, orientation: .up)
    }
}
