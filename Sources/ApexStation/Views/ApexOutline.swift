import CoreGraphics
import SwiftUI

enum ApexOutline {
    static let aspect: CGFloat = 0.6951

    static let points: [CGPoint] = [
        CGPoint(x: 0.5000, y: 0.0174), CGPoint(x: 0.4743, y: 0.0174), CGPoint(x: 0.4485, y: 0.0174),
        CGPoint(x: 0.4228, y: 0.0174), CGPoint(x: 0.3971, y: 0.0174), CGPoint(x: 0.3714, y: 0.0174),
        CGPoint(x: 0.3466, y: 0.0114), CGPoint(x: 0.3225, y: 0.0027), CGPoint(x: 0.2970, y: 0.0000),
        CGPoint(x: 0.2716, y: 0.0039), CGPoint(x: 0.2466, y: 0.0101), CGPoint(x: 0.2222, y: 0.0181),
        CGPoint(x: 0.1986, y: 0.0283), CGPoint(x: 0.1766, y: 0.0416), CGPoint(x: 0.1588, y: 0.0600),
        CGPoint(x: 0.1457, y: 0.0821), CGPoint(x: 0.1320, y: 0.1039), CGPoint(x: 0.1197, y: 0.1265),
        CGPoint(x: 0.1094, y: 0.1501), CGPoint(x: 0.0997, y: 0.1738), CGPoint(x: 0.0902, y: 0.1978),
        CGPoint(x: 0.0811, y: 0.2218), CGPoint(x: 0.0722, y: 0.2460), CGPoint(x: 0.0635, y: 0.2702),
        CGPoint(x: 0.0551, y: 0.2945), CGPoint(x: 0.0470, y: 0.3189), CGPoint(x: 0.0393, y: 0.3434),
        CGPoint(x: 0.0320, y: 0.3681), CGPoint(x: 0.0252, y: 0.3929), CGPoint(x: 0.0190, y: 0.4179),
        CGPoint(x: 0.0133, y: 0.4430), CGPoint(x: 0.0083, y: 0.4682), CGPoint(x: 0.0043, y: 0.4936),
        CGPoint(x: 0.0013, y: 0.5192), CGPoint(x: 0.0000, y: 0.5449), CGPoint(x: 0.0007, y: 0.5706),
        CGPoint(x: 0.0041, y: 0.5961), CGPoint(x: 0.0109, y: 0.6209), CGPoint(x: 0.0215, y: 0.6443),
        CGPoint(x: 0.0362, y: 0.6653), CGPoint(x: 0.0552, y: 0.6826), CGPoint(x: 0.0781, y: 0.6939),
        CGPoint(x: 0.1036, y: 0.6951), CGPoint(x: 0.1266, y: 0.6842), CGPoint(x: 0.1451, y: 0.6663),
        CGPoint(x: 0.1619, y: 0.6468), CGPoint(x: 0.1789, y: 0.6275), CGPoint(x: 0.1962, y: 0.6085),
        CGPoint(x: 0.2140, y: 0.5899), CGPoint(x: 0.2326, y: 0.5722), CGPoint(x: 0.2525, y: 0.5559),
        CGPoint(x: 0.2740, y: 0.5417), CGPoint(x: 0.2971, y: 0.5305), CGPoint(x: 0.3206, y: 0.5200),
        CGPoint(x: 0.3456, y: 0.5148), CGPoint(x: 0.3714, y: 0.5147), CGPoint(x: 0.3971, y: 0.5147),
        CGPoint(x: 0.4228, y: 0.5147), CGPoint(x: 0.4485, y: 0.5147), CGPoint(x: 0.4743, y: 0.5147),
        CGPoint(x: 0.5000, y: 0.5147), CGPoint(x: 0.5257, y: 0.5147), CGPoint(x: 0.5515, y: 0.5147),
        CGPoint(x: 0.5772, y: 0.5147), CGPoint(x: 0.6029, y: 0.5147), CGPoint(x: 0.6286, y: 0.5147),
        CGPoint(x: 0.6544, y: 0.5148), CGPoint(x: 0.6794, y: 0.5200), CGPoint(x: 0.7029, y: 0.5305),
        CGPoint(x: 0.7260, y: 0.5417), CGPoint(x: 0.7475, y: 0.5559), CGPoint(x: 0.7674, y: 0.5722),
        CGPoint(x: 0.7860, y: 0.5899), CGPoint(x: 0.8038, y: 0.6085), CGPoint(x: 0.8211, y: 0.6275),
        CGPoint(x: 0.8381, y: 0.6468), CGPoint(x: 0.8549, y: 0.6663), CGPoint(x: 0.8734, y: 0.6842),
        CGPoint(x: 0.8964, y: 0.6951), CGPoint(x: 0.9219, y: 0.6939), CGPoint(x: 0.9448, y: 0.6826),
        CGPoint(x: 0.9638, y: 0.6653), CGPoint(x: 0.9785, y: 0.6443), CGPoint(x: 0.9891, y: 0.6209),
        CGPoint(x: 0.9959, y: 0.5961), CGPoint(x: 0.9993, y: 0.5706), CGPoint(x: 1.0000, y: 0.5449),
        CGPoint(x: 0.9987, y: 0.5192), CGPoint(x: 0.9957, y: 0.4936), CGPoint(x: 0.9917, y: 0.4682),
        CGPoint(x: 0.9867, y: 0.4430), CGPoint(x: 0.9810, y: 0.4179), CGPoint(x: 0.9748, y: 0.3929),
        CGPoint(x: 0.9680, y: 0.3681), CGPoint(x: 0.9607, y: 0.3434), CGPoint(x: 0.9530, y: 0.3189),
        CGPoint(x: 0.9449, y: 0.2945), CGPoint(x: 0.9365, y: 0.2702), CGPoint(x: 0.9278, y: 0.2460),
        CGPoint(x: 0.9189, y: 0.2218), CGPoint(x: 0.9098, y: 0.1978), CGPoint(x: 0.9003, y: 0.1738),
        CGPoint(x: 0.8906, y: 0.1501), CGPoint(x: 0.8803, y: 0.1265), CGPoint(x: 0.8680, y: 0.1039),
        CGPoint(x: 0.8543, y: 0.0821), CGPoint(x: 0.8412, y: 0.0600), CGPoint(x: 0.8234, y: 0.0416),
        CGPoint(x: 0.8014, y: 0.0283), CGPoint(x: 0.7778, y: 0.0181), CGPoint(x: 0.7534, y: 0.0101),
        CGPoint(x: 0.7284, y: 0.0039), CGPoint(x: 0.7030, y: 0.0000), CGPoint(x: 0.6775, y: 0.0027),
        CGPoint(x: 0.6534, y: 0.0114), CGPoint(x: 0.6286, y: 0.0174), CGPoint(x: 0.6029, y: 0.0174),
        CGPoint(x: 0.5772, y: 0.0174), CGPoint(x: 0.5515, y: 0.0174), CGPoint(x: 0.5257, y: 0.0174),
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
