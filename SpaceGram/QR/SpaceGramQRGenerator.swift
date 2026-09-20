import CoreImage
import Foundation
import UIKit

public enum SpaceGramQRGenerator {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    public static func image(text: String, scale: CGFloat = 8.0) -> UIImage? {
        guard scale.isFinite, scale > 0.0,
              let data = text.data(using: .utf8), !data.isEmpty,
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
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent.integral) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
