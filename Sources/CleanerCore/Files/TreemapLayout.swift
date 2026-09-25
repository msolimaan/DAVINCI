import Foundation

/// Squarified treemap layout (Bruls, Huizing & van Wijk) used by Space Lens.
///
/// Produces rectangles whose areas are proportional to the values and whose shapes stay close to squares,
/// which keeps small items clickable and labels readable.
public enum TreemapLayout {
    /// - Parameter values: positive values, ideally sorted largest first.
    /// - Returns: one rectangle per value, in the same order.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { max(0, $0) * scale }
        var remaining = rect
        var start = 0

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else { break }

            // Grow the row while it makes the worst aspect ratio better.
            var end = start + 1
            var rowSum = areas[start]
            while end < areas.count {
                let current = worstRatio(areas[start..<end], sum: rowSum, side: side)
                let next = worstRatio(areas[start...end], sum: rowSum + areas[end], side: side)
                guard next <= current else { break }
                rowSum += areas[end]
                end += 1
            }

            let thickness = rowSum > 0 ? rowSum / side : 0
            if remaining.width >= remaining.height {
                // Lay the row out as a column on the left.
                var y = Double(remaining.minY)
                for index in start..<end {
                    let height = thickness > 0 ? areas[index] / thickness : 0
                    result[index] = CGRect(x: Double(remaining.minX), y: y, width: thickness, height: height)
                    y += height
                }
                remaining = CGRect(
                    x: Double(remaining.minX) + thickness,
                    y: Double(remaining.minY),
                    width: max(0, Double(remaining.width) - thickness),
                    height: Double(remaining.height)
                )
            } else {
                // Lay the row out along the top.
                var x = Double(remaining.minX)
                for index in start..<end {
                    let width = thickness > 0 ? areas[index] / thickness : 0
                    result[index] = CGRect(x: x, y: Double(remaining.minY), width: width, height: thickness)
                    x += width
                }
                remaining = CGRect(
                    x: Double(remaining.minX),
                    y: Double(remaining.minY) + thickness,
                    width: Double(remaining.width),
                    height: max(0, Double(remaining.height) - thickness)
                )
            }
            start = end
        }
        return result
    }

    static func worstRatio(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0 else {
            return .infinity
        }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }
}
