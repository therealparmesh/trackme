import CoreLocation
import SwiftUI

struct RouteTrailLine: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let totalLines: Int

    var color: Color {
        let progress = totalLines <= 1 ? 0 : Double(id) / Double(totalLines - 1)
        let hue = (0.52 + progress * 0.58).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.72, brightness: 1)
    }
}

enum RouteTrailStyle {
    private static let maximumLines = 160

    static func lines(from route: [RoutePoint]) -> [RouteTrailLine] {
        let chunks = coordinateChunks(from: route)
        return chunks.enumerated().map { index, coordinates in
            RouteTrailLine(id: index, coordinates: coordinates, totalLines: chunks.count)
        }
    }

    private static func coordinateChunks(from route: [RoutePoint]) -> [[CLLocationCoordinate2D]] {
        let segments = route.routeSegments.filter { $0.count > 1 }
        let segmentCount = segments.reduce(0) { count, segment in
            count + segment.count - 1
        }
        guard segmentCount > 0 else { return [] }

        let stride = max(1, Int(ceil(Double(segmentCount) / Double(maximumLines))))
        var chunks: [[CLLocationCoordinate2D]] = []

        for segment in segments {
            var startIndex = segment.startIndex
            while startIndex < segment.index(before: segment.endIndex) {
                let endIndex = min(
                    segment.index(before: segment.endIndex),
                    segment.index(startIndex, offsetBy: stride, limitedBy: segment.index(before: segment.endIndex))
                        ?? segment.index(before: segment.endIndex)
                )
                chunks.append(segment[startIndex...endIndex].map(\.coordinate))
                startIndex = endIndex
            }
        }

        return chunks
    }
}
