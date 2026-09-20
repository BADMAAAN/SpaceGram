import UIKit

/// Template artwork follows the native toolbar accent in light and dark themes.
public enum SpaceGramGhostGlyph {
    public static let inactive = make(active: false)
    public static let active = make(active: true)

    private static func make(active: Bool) -> UIImage {
        return UIGraphicsImageRenderer(size: CGSize(width: 24.0, height: 24.0)).image { renderer in
            let context = renderer.cgContext
            context.setStrokeColor(UIColor.black.cgColor)
            context.setFillColor(UIColor.black.cgColor)
            context.setLineWidth(1.7)
            context.translateBy(x: 12.0, y: 12.0)
            let planet = CGRect(x: -5.0, y: -5.0, width: 10.0, height: 10.0)
            if active {
                context.fillEllipse(in: planet)
            } else {
                context.strokeEllipse(in: planet)
            }
            context.rotate(by: -.pi / 6.0)
            context.strokeEllipse(in: CGRect(x: -10.0, y: -4.0, width: 20.0, height: 8.0))
            if active {
                context.fillEllipse(in: CGRect(x: 7.8, y: -2.2, width: 3.8, height: 3.8))
            }
        }.withRenderingMode(.alwaysTemplate)
    }
}
