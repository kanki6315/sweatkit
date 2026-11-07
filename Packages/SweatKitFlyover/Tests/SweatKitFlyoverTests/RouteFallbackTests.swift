#if canImport(UIKit)
import MapKit
import SwiftUI
import SweatKitModel
import Testing
@testable import SweatKitFlyover

@MainActor @Suite struct RouteFallbackTests {
    private func route() throws -> FlyoverRoute {
        try FlyoverRoute(vertices: [Coordinate(latitude: 35, longitude: -80),
                                   Coordinate(latitude: 35.02, longitude: -80),
                                   Coordinate(latitude: 35.02, longitude: -80.02)],
                         bands: [0, 1, 1], sampleIndices: [0, 100, 200])
    }

    @Test func fallbackSurvivesPartialRenderAndRecoversAfterFailure() throws {
        let map = LayoutReportingMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let coordinator = FlyoverMapCoordinator()
        coordinator.mapView = map
        coordinator.beginPresentation(reused: false)
        defer { coordinator.stop() }
        coordinator.update(route: try route(), bandColors: [.red, .blue], scrubSample: 0,
                           options: FlyoverOptions(), cameraMode: .overview)
        #expect(!map.routeFallback.isHidden)
        #expect(!map.isScrollEnabled)
        coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: false)
        #expect(!map.routeFallback.isHidden)
        coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
        #expect(map.routeFallback.isHidden)
        #expect(map.isScrollEnabled)
        coordinator.mapViewDidFailLoadingMap(map, withError: URLError(.notConnectedToInternet))
        #expect(!map.routeFallback.isHidden)
        coordinator.mapViewDidFinishLoadingMap(map)
        #expect(!map.routeFallback.isHidden) // Loading finished isn't proof of rendered imagery.
        coordinator.mapViewDidFinishRenderingMap(map, fullyRendered: true)
        #expect(map.routeFallback.isHidden)
        let original = try route()
        let recolored = try FlyoverRoute(vertices: original.vertices, bands: [1, 0, 0], sampleIndices: original.sampleIndices)
        coordinator.update(route: recolored, bandColors: [.blue, .red], scrubSample: 150,
                           options: FlyoverOptions(), cameraMode: .overview)
        #expect(map.routeFallback.isHidden) // Recoloring must not wait for another map render.
        coordinator.stop()
        coordinator.mapViewDidFailLoadingMap(map, withError: URLError(.cancelled))
        #expect(map.routeFallback.isHidden) // Detached callbacks must not alter reused state.
    }

    @Test func scrubMarkerRedrawsWithoutAnyMapRendering() throws {
        let view = RouteFallbackView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let route = try route()
        let geometry = RouteGeometry(route: route)
        func image(at sample: Double) -> Data? {
            view.update(route: route, colors: [.red, .blue], position: geometry.position(atSample: sample),
                        options: FlyoverOptions(dimsAhead: true))
            return UIGraphicsImageRenderer(size: view.bounds.size).image { context in
                view.layer.render(in: context.cgContext)
            }.pngData()
        }
        let start = try #require(image(at: 0))
        let middle = try #require(image(at: 150))
        let end = try #require(image(at: 200))
        #expect(start != middle)
        #expect(middle != end)
    }
}
#endif
