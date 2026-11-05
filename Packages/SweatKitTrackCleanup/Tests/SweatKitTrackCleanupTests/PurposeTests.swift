import SweatKitModel
import SweatKitTrackCleanup
import Testing

/// Why cleanup comes before route matching: jitter inflates length, and the
/// matcher's length rule allows only 3%.
@Suite struct PurposeTests {
    @Test func jitterOnAStraightRoadIsRemovedFromItsLength() {
        // A 1,000 m road due east, ridden at 5 m/s: 201 fixes, second i at
        // i * 5 m. The ends are on the road; every fix between them is 1.9 m
        // to the north on odd seconds and 1.9 m to the south on even ones.
        let seconds = (0...200).map { index -> Second in
            let offset = (index == 0 || index == 200) ? 0 : (index.isMultiple(of: 2) ? -1.9 : 1.9)
            return Second(east: Double(index) * 5, north: offset, speed: 5)
        }
        let stream = makeStream(seconds)
        let trueLength = 1_000.0

        // Raw: the first and last steps move 5 m east and 1.9 m sideways,
        // sqrt(25 + 3.61) = 5.349 m. The 198 between move 5 m east and 3.8 m
        // sideways, sqrt(25 + 14.44) = 6.280 m. 2 * 5.349 + 198 * 6.280
        // = 1,254.2 m, about 25% too long.
        let raw = TrackGeodesy.length(of: TrackCleanup.positions(in: stream).map(\.coordinate))
        #expect(close(raw, 2 * 28.61.squareRoot() + 198 * 39.44.squareRoot(), within: 0.01))
        #expect(raw > trueLength * 1.03)

        // Steps 1 and 2 leave a moving track alone: every step is about 6 m
        // in a second, possible on a bike, and nobody stopped.
        let cleaned = TrackCleanup.clean(stream, sport: .cycling)
        #expect(cleaned.points.count == 201)

        // Step 3: every fix is 1.9 m from the line from first to last, within
        // 2 m, so the drawn line is the road itself, 1,000 m.
        let line = TrackCleanup.simplify(cleaned)
        #expect(line.vertices.map(\.sampleIndex) == [0, 200])
        #expect(abs(line.length - trueLength) <= trueLength * 0.03)
        #expect(close(line.length, trueLength))
    }
}
