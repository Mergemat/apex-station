import CoreGraphics
import SwiftUI

enum ApexOutline {
    static let aspect: CGFloat = 0.7009

    static let points: [CGPoint] = [
        CGPoint(x: 0.3054, y: 0.0007), CGPoint(x: 0.2734, y: 0.0054), CGPoint(x: 0.2419, y: 0.0132),
        CGPoint(x: 0.2114, y: 0.0242), CGPoint(x: 0.1825, y: 0.0387), CGPoint(x: 0.1584, y: 0.0599),
        CGPoint(x: 0.1436, y: 0.0882), CGPoint(x: 0.1258, y: 0.1152), CGPoint(x: 0.1125, y: 0.1448),
        CGPoint(x: 0.1001, y: 0.1747), CGPoint(x: 0.0882, y: 0.2049), CGPoint(x: 0.0768, y: 0.2352),
        CGPoint(x: 0.0658, y: 0.2657), CGPoint(x: 0.0552, y: 0.2963), CGPoint(x: 0.0450, y: 0.3271),
        CGPoint(x: 0.0354, y: 0.3581), CGPoint(x: 0.0267, y: 0.3893), CGPoint(x: 0.0188, y: 0.4207),
        CGPoint(x: 0.0118, y: 0.4524), CGPoint(x: 0.0059, y: 0.4843), CGPoint(x: 0.0017, y: 0.5164),
        CGPoint(x: 0.0000, y: 0.5488), CGPoint(x: 0.0014, y: 0.5811), CGPoint(x: 0.0075, y: 0.6129),
        CGPoint(x: 0.0195, y: 0.6430), CGPoint(x: 0.0380, y: 0.6695), CGPoint(x: 0.0631, y: 0.6898),
        CGPoint(x: 0.0938, y: 0.6994), CGPoint(x: 0.1237, y: 0.6891), CGPoint(x: 0.1465, y: 0.6662),
        CGPoint(x: 0.1682, y: 0.6421), CGPoint(x: 0.1893, y: 0.6174), CGPoint(x: 0.2097, y: 0.5923),
        CGPoint(x: 0.2307, y: 0.5676), CGPoint(x: 0.2590, y: 0.5546), CGPoint(x: 0.2787, y: 0.5295),
        CGPoint(x: 0.3086, y: 0.5197), CGPoint(x: 0.3410, y: 0.5182), CGPoint(x: 0.3734, y: 0.5168),
        CGPoint(x: 0.4058, y: 0.5156), CGPoint(x: 0.4382, y: 0.5161), CGPoint(x: 0.4706, y: 0.5160),
        CGPoint(x: 0.5029, y: 0.5145), CGPoint(x: 0.5352, y: 0.5166), CGPoint(x: 0.5676, y: 0.5159),
        CGPoint(x: 0.6000, y: 0.5159), CGPoint(x: 0.6324, y: 0.5171), CGPoint(x: 0.6648, y: 0.5184),
        CGPoint(x: 0.6972, y: 0.5203), CGPoint(x: 0.7242, y: 0.5352), CGPoint(x: 0.7468, y: 0.5559),
        CGPoint(x: 0.7729, y: 0.5728), CGPoint(x: 0.7937, y: 0.5977), CGPoint(x: 0.8142, y: 0.6229),
        CGPoint(x: 0.8354, y: 0.6474), CGPoint(x: 0.8572, y: 0.6714), CGPoint(x: 0.8810, y: 0.6933),
        CGPoint(x: 0.9121, y: 0.6986), CGPoint(x: 0.9418, y: 0.6862), CGPoint(x: 0.9655, y: 0.6642),
        CGPoint(x: 0.9825, y: 0.6367), CGPoint(x: 0.9932, y: 0.6062), CGPoint(x: 0.9982, y: 0.5742),
        CGPoint(x: 0.9990, y: 0.5418), CGPoint(x: 0.9964, y: 0.5095), CGPoint(x: 0.9919, y: 0.4774),
        CGPoint(x: 0.9858, y: 0.4456), CGPoint(x: 0.9785, y: 0.4140), CGPoint(x: 0.9704, y: 0.3826),
        CGPoint(x: 0.9615, y: 0.3514), CGPoint(x: 0.9518, y: 0.3205), CGPoint(x: 0.9416, y: 0.2897),
        CGPoint(x: 0.9308, y: 0.2592), CGPoint(x: 0.9197, y: 0.2287), CGPoint(x: 0.9082, y: 0.1984),
        CGPoint(x: 0.8962, y: 0.1683), CGPoint(x: 0.8837, y: 0.1384), CGPoint(x: 0.8700, y: 0.1090),
        CGPoint(x: 0.8508, y: 0.0830), CGPoint(x: 0.8366, y: 0.0542), CGPoint(x: 0.8105, y: 0.0352),
        CGPoint(x: 0.7812, y: 0.0215), CGPoint(x: 0.7504, y: 0.0114), CGPoint(x: 0.7188, y: 0.0041),
        CGPoint(x: 0.6867, y: 0.0008), CGPoint(x: 0.6564, y: 0.0120), CGPoint(x: 0.6257, y: 0.0210),
        CGPoint(x: 0.5933, y: 0.0202), CGPoint(x: 0.5608, y: 0.0196), CGPoint(x: 0.5284, y: 0.0190),
        CGPoint(x: 0.4960, y: 0.0188), CGPoint(x: 0.4636, y: 0.0196), CGPoint(x: 0.4312, y: 0.0196),
        CGPoint(x: 0.3988, y: 0.0203), CGPoint(x: 0.3664, y: 0.0206), CGPoint(x: 0.3363, y: 0.0090),
    ]

    /// A smooth closed curve through the traced points, scaled to `width`.
    static func path(width: CGFloat, origin: CGPoint = .zero) -> Path {
        let p = points.map { CGPoint(x: origin.x + $0.x * width, y: origin.y + $0.y * width) }
        var path = Path()
        path.move(to: p[0])
        let n = p.count
        for i in 0..<n {
            // Catmull-Rom segment p1 → p2 as a cubic Bézier.
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}
