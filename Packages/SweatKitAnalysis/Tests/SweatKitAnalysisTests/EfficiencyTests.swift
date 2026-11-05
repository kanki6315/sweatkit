import Foundation
import SweatKitModel
import Testing
@testable import SweatKitAnalysis

/// The two efficiencies in the spec's "Other" table.
@Suite struct EfficiencyTests {
    // MARK: Cycling

    @Test func cyclingEfficiencyIsWeightedPowerOverAverageHeartRate() {
        // 300 s at 200 W is a weighted power of 200 W. 200 / 100 = 2.
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(100, 300))
        expectClose(analyse(stream).cyclingEfficiency, 2, tolerance: 1e-6)
    }

    @Test func cyclingEfficiencyUsesWeightedPowerNotAveragePower() {
        // The ride from WeightedPowerTests: weighted (41 x 10^8)^(1/4),
        // about 253.04 W, average 200 W. Heart rate 125 throughout.
        // Efficiency = weighted / 125, about 2.024, not 200 / 125 = 1.6.
        let stream = makeStream(
            count: 307,
            power: run(100, 150) + run(nil, 7) + run(300, 150),
            heartRate: run(125, 307)
        )
        expectClose(analyse(stream).cyclingEfficiency, pow(41e8, 0.25) / 125, tolerance: 1e-6)
    }

    @Test func cyclingEfficiencyCarriesTheReasonWeightedPowerIsUnavailable() {
        // 100 s is under 5 minutes of power.
        let stream = makeStream(count: 100, power: run(200, 100), heartRate: run(100, 100))
        #expect(analyse(stream).cyclingEfficiency == .unavailable(.tooLittlePower))
    }

    @Test func cyclingEfficiencyIsUnavailableWithoutHeartRate() {
        let stream = makeStream(count: 300, power: run(200, 300))
        #expect(analyse(stream).cyclingEfficiency == .unavailable(.noHeartRate))
    }

    @Test(arguments: [Sport.walking, .running, .hiking, .other])
    func cyclingEfficiencyIsNotDefinedOffABike(sport: Sport) {
        let stream = makeStream(count: 300, power: run(200, 300), heartRate: run(100, 300))
        #expect(analyse(stream, sport: sport).cyclingEfficiency == .unavailable(.notDefinedForSport))
    }

    // MARK: On foot

    @Test func onFootEfficiencyIsOverTheSecondsThatHaveBothSpeedAndHeartRate() {
        // Seconds 0 and 1 have both. Speed (2 + 4) / 2 = 3 m/s, heart rate
        // (100 + 200) / 2 = 150. 3 / 150 = 0.02.
        // Each channel over its own seconds would give 4 / 140 = 0.0286.
        let stream = makeStream(
            count: 4,
            heartRate: [100, 200, 120, nil],
            speed: [2, 4, nil, 6]
        )
        expectClose(analyse(stream, sport: .running).onFootEfficiency, 0.02)
    }

    @Test(arguments: [Sport.walking, .running, .hiking])
    func onFootEfficiencyIsForWalkingRunningAndHiking(sport: Sport) {
        // 3 m/s over 150: 0.02.
        let stream = makeStream(count: 10, heartRate: run(150, 10), speed: run(3, 10))
        expectClose(analyse(stream, sport: sport).onFootEfficiency, 0.02)
    }

    @Test func onFootEfficiencyIsSpeedPerBeatSoFasterIsHigher() {
        // "Always speed, never pace": 4 m/s over 150 = 0.02667 is above
        // 3 m/s over 150 = 0.02.
        let stream = makeStream(count: 10, heartRate: run(150, 10), speed: run(4, 10))
        expectClose(analyse(stream, sport: .running).onFootEfficiency, 4.0 / 150.0)
    }

    @Test(arguments: [Sport.cycling, .other])
    func onFootEfficiencyIsNotDefinedOffFoot(sport: Sport) {
        let stream = makeStream(count: 10, heartRate: run(150, 10), speed: run(3, 10))
        #expect(analyse(stream, sport: sport).onFootEfficiency == .unavailable(.notDefinedForSport))
    }

    @Test func onFootEfficiencyIsUnavailableWithoutSpeed() {
        let stream = makeStream(count: 10, heartRate: run(150, 10))
        #expect(analyse(stream, sport: .walking).onFootEfficiency == .unavailable(.noSpeed))
    }

    @Test func onFootEfficiencyIsUnavailableWithoutHeartRate() {
        let stream = makeStream(count: 10, speed: run(3, 10))
        #expect(analyse(stream, sport: .walking).onFootEfficiency == .unavailable(.noHeartRate))
    }
}
