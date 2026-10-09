import SwiftUI

extension Path {
    init(svg d: String) {
        self.init()
        var numbers: [CGFloat] = []
        var command: Character?
        var token = ""

        func flushNumber() {
            if let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        func run() {
            guard let command else { return }
            let n = numbers
            func p(_ i: Int) -> CGPoint { CGPoint(x: n[i], y: n[i + 1]) }
            switch command {
            case "M":
                guard n.count >= 2 else { break }
                move(to: p(0))
                // Extra pairs after a move are lines.
                for i in stride(from: 2, to: n.count - 1, by: 2) { addLine(to: p(i)) }
            case "L":
                for i in stride(from: 0, to: n.count - 1, by: 2) { addLine(to: p(i)) }
            case "C":
                for i in stride(from: 0, to: n.count - 5, by: 6) { addCurve(to: p(i + 4), control1: p(i), control2: p(i + 2)) }
            case "Q":
                for i in stride(from: 0, to: n.count - 3, by: 4) { addQuadCurve(to: p(i + 2), control: p(i)) }
            case "Z", "z":
                closeSubpath()
            default:
                break
            }
            numbers = []
        }

        for ch in d {
            if ch.isLetter && ch != "e" {
                flushNumber()
                run()
                command = ch
            } else if ch == " " || ch == "," {
                flushNumber()
            } else if ch == "-" && !token.isEmpty && token.last != "e" {
                flushNumber()
                token.append(ch)
            } else {
                token.append(ch)
            }
        }
        flushNumber()
        run()
    }

    /// A closed polygon through `points`.
    init(polygon points: [CGPoint]) {
        self.init()
        guard let first = points.first else { return }
        move(to: first)
        addLines(points)
        closeSubpath()
    }
}
