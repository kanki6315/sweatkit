import Foundation
import SweatKitModel
import SweatKitTestSupport
import Testing
@testable import SweatKitRouteMatching

@Test func packageSeesTheModelAndTheFixtures() throws {
    let stream = AnalysisStream(rulesVersion: 1, start: .now, count: 1)
    #expect(stream.isConsistent)
    #expect(try !Fixtures.FIT.outdoorRide.data().isEmpty)
}
