import Foundation
import SweatKitSync
import Testing

@Suite struct KeyLifetimeTests {
    @Test func warningStartsSevenDaysBeforeEnteredExpiry() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        for period in GarminKeyLifetime.Period.allCases {
            let lifetime = GarminKeyLifetime(created: created, period: period)
            let expiry = created.addingTimeInterval(Double(period.rawValue) * 86400)
            #expect(lifetime.estimatedExpiry == expiry)
            #expect(lifetime.warning(at: expiry.addingTimeInterval(-7 * 86400 - 1)) == .none)
            #expect(lifetime.warning(at: expiry.addingTimeInterval(-7 * 86400)) == .dueSoon)
            #expect(lifetime.warning(at: expiry.addingTimeInterval(-1)) == .dueSoon)
            #expect(lifetime.warning(at: expiry) == .expired)
            #expect(try JSONDecoder().decode(GarminKeyLifetime.self, from: JSONEncoder().encode(lifetime)) == lifetime)
        }
    }
}
