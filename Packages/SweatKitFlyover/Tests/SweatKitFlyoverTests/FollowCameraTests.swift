#if canImport(UIKit)
import MapKit
import SweatKitModel
import Testing
@testable import SweatKitFlyover

@MainActor @Suite struct FollowCameraTests {
    @Test func cameraAndMarkerStayTogetherAcrossPlaybackAndSeeks() throws {
        let route = try FlyoverRoute(
            vertices: [Coordinate(latitude: 35, longitude: -80),
                       Coordinate(latitude: 35.02, longitude: -80),
                       Coordinate(latitude: 35.02, longitude: -80.02)],
            bands: [0, 0, 0], sampleIndices: [0, 100, 200])
        let geometry = RouteGeometry(route: route)
        let map = LayoutReportingMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let coordinator = FlyoverMapCoordinator()
        coordinator.mapView = map
        defer { coordinator.stop() }
        let options = FlyoverOptions(mapStyle: .standard, realisticElevation: false, cameraMode: .follow)
        for sample in [0.0, 1, 2, 75, 150, 200, 20, 0] {
            coordinator.update(route: route, bandColors: [], scrubSample: sample,
                               options: options, cameraMode: .follow)
            coordinator.updateFollowCamera(seconds: 1.0 / 30)
            let expected = geometry.coordinate(at: geometry.position(atSample: sample))
            let marker = try #require(map.annotations.first)
            #expect(abs(marker.coordinate.latitude - expected.latitude) < 0.000001)
            #expect(abs(marker.coordinate.longitude - expected.longitude) < 0.000001)
            #expect(abs(map.camera.centerCoordinate.latitude - expected.latitude) < 0.000001)
            #expect(abs(map.camera.centerCoordinate.longitude - expected.longitude) < 0.000001)
        }
    }
}
#endif
