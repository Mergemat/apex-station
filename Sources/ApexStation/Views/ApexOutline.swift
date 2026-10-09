import CoreGraphics
import SwiftUI

enum ApexOutline {
    static let aspect: CGFloat = 0.6891

    static let points: [CGPoint] = [
        CGPoint(x: 0.5000, y: 0.0082), CGPoint(x: 0.4745, y: 0.0082), CGPoint(x: 0.4489, y: 0.0082),
        CGPoint(x: 0.4234, y: 0.0082), CGPoint(x: 0.3979, y: 0.0082), CGPoint(x: 0.3723, y: 0.0082),
        CGPoint(x: 0.3469, y: 0.0067), CGPoint(x: 0.3217, y: 0.0024), CGPoint(x: 0.2963, y: 0.0000),
        CGPoint(x: 0.2709, y: 0.0021), CGPoint(x: 0.2459, y: 0.0072), CGPoint(x: 0.2214, y: 0.0142),
        CGPoint(x: 0.1974, y: 0.0229), CGPoint(x: 0.1744, y: 0.0341), CGPoint(x: 0.1541, y: 0.0494),
        CGPoint(x: 0.1386, y: 0.0696), CGPoint(x: 0.1253, y: 0.0915), CGPoint(x: 0.1122, y: 0.1133),
        CGPoint(x: 0.1004, y: 0.1360), CGPoint(x: 0.0900, y: 0.1593), CGPoint(x: 0.0804, y: 0.1829),
        CGPoint(x: 0.0712, y: 0.2068), CGPoint(x: 0.0625, y: 0.2308), CGPoint(x: 0.0541, y: 0.2549),
        CGPoint(x: 0.0463, y: 0.2792), CGPoint(x: 0.0389, y: 0.3036), CGPoint(x: 0.0319, y: 0.3282),
        CGPoint(x: 0.0256, y: 0.3529), CGPoint(x: 0.0199, y: 0.3778), CGPoint(x: 0.0147, y: 0.4028),
        CGPoint(x: 0.0101, y: 0.4279), CGPoint(x: 0.0062, y: 0.4532), CGPoint(x: 0.0029, y: 0.4785),
        CGPoint(x: 0.0007, y: 0.5039), CGPoint(x: 0.0000, y: 0.5294), CGPoint(x: 0.0009, y: 0.5549),
        CGPoint(x: 0.0039, y: 0.5803), CGPoint(x: 0.0097, y: 0.6051), CGPoint(x: 0.0190, y: 0.6289),
        CGPoint(x: 0.0325, y: 0.6505), CGPoint(x: 0.0503, y: 0.6687), CGPoint(x: 0.0720, y: 0.6821),
        CGPoint(x: 0.0965, y: 0.6891), CGPoint(x: 0.1216, y: 0.6866), CGPoint(x: 0.1429, y: 0.6728),
        CGPoint(x: 0.1592, y: 0.6532), CGPoint(x: 0.1762, y: 0.6341), CGPoint(x: 0.1939, y: 0.6157),
        CGPoint(x: 0.2120, y: 0.5977), CGPoint(x: 0.2311, y: 0.5808), CGPoint(x: 0.2517, y: 0.5657),
        CGPoint(x: 0.2739, y: 0.5531), CGPoint(x: 0.2976, y: 0.5437), CGPoint(x: 0.3216, y: 0.5351),
        CGPoint(x: 0.3468, y: 0.5315), CGPoint(x: 0.3723, y: 0.5315), CGPoint(x: 0.3979, y: 0.5315),
        CGPoint(x: 0.4234, y: 0.5315), CGPoint(x: 0.4489, y: 0.5315), CGPoint(x: 0.4745, y: 0.5315),
        CGPoint(x: 0.5000, y: 0.5315), CGPoint(x: 0.5255, y: 0.5315), CGPoint(x: 0.5511, y: 0.5315),
        CGPoint(x: 0.5766, y: 0.5315), CGPoint(x: 0.6021, y: 0.5315), CGPoint(x: 0.6277, y: 0.5315),
        CGPoint(x: 0.6532, y: 0.5315), CGPoint(x: 0.6784, y: 0.5351), CGPoint(x: 0.7024, y: 0.5437),
        CGPoint(x: 0.7261, y: 0.5531), CGPoint(x: 0.7483, y: 0.5657), CGPoint(x: 0.7689, y: 0.5808),
        CGPoint(x: 0.7880, y: 0.5977), CGPoint(x: 0.8061, y: 0.6157), CGPoint(x: 0.8238, y: 0.6341),
        CGPoint(x: 0.8408, y: 0.6532), CGPoint(x: 0.8571, y: 0.6728), CGPoint(x: 0.8784, y: 0.6866),
        CGPoint(x: 0.9035, y: 0.6891), CGPoint(x: 0.9280, y: 0.6821), CGPoint(x: 0.9497, y: 0.6687),
        CGPoint(x: 0.9675, y: 0.6505), CGPoint(x: 0.9810, y: 0.6289), CGPoint(x: 0.9903, y: 0.6051),
        CGPoint(x: 0.9961, y: 0.5803), CGPoint(x: 0.9991, y: 0.5549), CGPoint(x: 1.0000, y: 0.5294),
        CGPoint(x: 0.9993, y: 0.5039), CGPoint(x: 0.9971, y: 0.4785), CGPoint(x: 0.9938, y: 0.4532),
        CGPoint(x: 0.9899, y: 0.4279), CGPoint(x: 0.9853, y: 0.4028), CGPoint(x: 0.9801, y: 0.3778),
        CGPoint(x: 0.9744, y: 0.3529), CGPoint(x: 0.9681, y: 0.3282), CGPoint(x: 0.9611, y: 0.3036),
        CGPoint(x: 0.9537, y: 0.2792), CGPoint(x: 0.9459, y: 0.2549), CGPoint(x: 0.9375, y: 0.2308),
        CGPoint(x: 0.9288, y: 0.2068), CGPoint(x: 0.9196, y: 0.1829), CGPoint(x: 0.9100, y: 0.1593),
        CGPoint(x: 0.8996, y: 0.1360), CGPoint(x: 0.8878, y: 0.1133), CGPoint(x: 0.8747, y: 0.0915),
        CGPoint(x: 0.8614, y: 0.0696), CGPoint(x: 0.8459, y: 0.0494), CGPoint(x: 0.8256, y: 0.0341),
        CGPoint(x: 0.8026, y: 0.0229), CGPoint(x: 0.7786, y: 0.0142), CGPoint(x: 0.7541, y: 0.0072),
        CGPoint(x: 0.7291, y: 0.0021), CGPoint(x: 0.7037, y: 0.0000), CGPoint(x: 0.6783, y: 0.0024),
        CGPoint(x: 0.6531, y: 0.0067), CGPoint(x: 0.6277, y: 0.0082), CGPoint(x: 0.6021, y: 0.0082),
        CGPoint(x: 0.5766, y: 0.0082), CGPoint(x: 0.5511, y: 0.0082), CGPoint(x: 0.5255, y: 0.0082),
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
