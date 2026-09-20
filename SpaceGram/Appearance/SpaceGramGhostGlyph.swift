import UIKit

/// Template artwork follows the native toolbar accent in light and dark themes.
public enum SpaceGramGhostGlyph {
    public static let inactive = make(active: false)
    public static let active = make(active: true)

    private static func make(active: Bool) -> UIImage {
        return UIGraphicsImageRenderer(size: CGSize(width: 58.0, height: 28.0)).image { renderer in
            let context = renderer.cgContext
            context.setStrokeColor(UIColor.black.cgColor)
            context.setFillColor(UIColor.black.cgColor)
            let capsule = UIBezierPath(roundedRect: CGRect(x: 0.8, y: 0.8, width: 56.4, height: 26.4), cornerRadius: 13.0)
            capsule.lineWidth = active ? 1.8 : 1.0
            capsule.stroke()
            ((active ? "ON" : "OFF") as NSString).draw(at: CGPoint(x: 29.0, y: 7.0), withAttributes: [
                .font: UIFont.systemFont(ofSize: 11.0, weight: .bold),
                .foregroundColor: UIColor.black
            ])
            context.setLineWidth(1.7)
            context.translateBy(x: 14.0, y: 14.0)
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
