import Foundation
import SweatKitModel
import SweatKitDetail
import SweatKitPalette
import SweatKitRouteMatching
import SweatKitTrackCleanup

struct RouteColoredRun: Sendable, Identifiable {
    let id: Int
    var points: [Coordinate]
    let hex: UInt32?
    let startDistance: Double
}

/// Reuse Detail's smoothing/zone rules and the shared palette. No derived geometry is persisted.
enum ComparisonRouteDrawing {
    nonisolated static func prepare(stream: AnalysisStream, sport: Sport, profile: AthleteProfile, alignment: Alignment) -> (runs: [RouteColoredRun], legend: String) {
        let input = DetailInput(stream: stream, sport: sport, profile: profile, activityDate: stream.start)
        let choices = RouteOverlay.defaultCandidates(sport: sport, hasPowerMeter: DetailPreparation.hasPowerMeter(input))
        let overlay = choices.first { ColourBanding.bands(for: $0, input: input).value != nil } ?? .plain
        guard let bands = ColourBanding.bands(for: overlay, input: input).value else { return ([], "Route · data unavailable") }
        let palette: [UInt32]
        let legend: String
        switch overlay {
        case .power:
            palette = EffortPalette.power.map(\.hex)
            legend = profile.thresholdPower(on: stream.start) == nil && profile.powerZoneBounds == nil ? "Power · starter zones" : "Power zones"
        case .heartRate: palette = EffortPalette.heartRate.map(\.hex); legend = "Heart-rate zones"
        case .paceOrSpeed: palette = EffortPalette.pace.map(\.hex); legend = sport.family == .onFoot ? "Relative pace" : "Relative speed"
        case .gradient: palette = EffortPalette.gradient.map(\.hex); legend = "Gradient"
        case .plain: return ([], "Route · effort data unavailable")
        }
        let line = TrackCleanup.simplify(TrackCleanup.clean(stream, sport: sport))
        guard line.vertices.count > 1 else { return ([], "Route · positions unavailable") }
        let distances = Dictionary(uniqueKeysWithValues: alignment.points.map { (Int($0.elapsedTime), $0.routeDistance) })
        var runs: [RouteColoredRun] = []
        for index in 0..<(line.vertices.count - 1) {
            let first = line.vertices[index], next = line.vertices[index + 1]
            let band = bands.bands[first.sampleIndex]
            let hex = band.flatMap { palette.indices.contains($0) ? palette[$0] : nil }
            if let last = runs.last, last.hex == hex {
                runs[runs.count - 1].points.append(next.coordinate)
            } else {
                runs.append(RouteColoredRun(id: runs.count, points: [first.coordinate, next.coordinate], hex: hex, startDistance: distances[first.sampleIndex] ?? 0))
            }
        }
        return (runs, legend)
    }
}
