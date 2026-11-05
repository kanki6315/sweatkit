import Foundation
import SweatKitModel
import Testing
@testable import SweatKitTimeline

private let british = Locale(identifier: "en_GB")
private let german = Locale(identifier: "de_DE")

@Suite struct DistanceFormatTests {
    /// 12,340 m is 12.34 km. 12,346 m is 12.346 km, which rounds to 12.35.
    @Test func metricIsKilometresToTwoPlaces() {
        #expect(StatFormatter.distance(12_340, units: .metric, locale: british)
            == FormattedStat(value: "12.34", unit: "km", spoken: "12.34 kilometres"))
        #expect(StatFormatter.distance(12_346, units: .metric, locale: british).value == "12.35")
        #expect(StatFormatter.distance(0, units: .metric, locale: british).value == "0.00")
    }

    /// A mile is 1,609.344 m, so 16,093.44 m is 10 miles, and 5,000 m is
    /// 5,000 / 1,609.344 = 3.1069 miles.
    @Test func imperialIsMilesToTwoPlaces() {
        #expect(StatFormatter.distance(16_093.44, units: .imperial, locale: british)
            == FormattedStat(value: "10.00", unit: "mi", spoken: "10.00 miles"))
        #expect(StatFormatter.distance(5000, units: .imperial, locale: british).value == "3.11")
    }

    @Test func missingIsADashWithItsUnit() {
        let dash = FormattedStat(value: "–", unit: "km", spoken: "No data")
        #expect(StatFormatter.distance(nil, units: .metric, locale: british) == dash)
        #expect(StatFormatter.distance(.nan, units: .metric, locale: british) == dash)
        #expect(StatFormatter.distance(nil, units: .imperial, locale: british).unit == "mi")
    }

    @Test func decimalSeparatorFollowsTheLocale() {
        #expect(StatFormatter.distance(12_340, units: .metric, locale: german).value == "12,34")
    }
}

@Suite struct TimeFormatTests {
    /// 3,725 s is 1 h, 2 min and 5 s. 754 s is 12 min 34 s.
    @Test func timeIsAClock() {
        #expect(StatFormatter.elapsedTime(3725)
            == FormattedStat(value: "1:02:05", unit: "", spoken: "1 hour 2 minutes 5 seconds"))
        #expect(StatFormatter.elapsedTime(754)
            == FormattedStat(value: "12:34", unit: "", spoken: "12 minutes 34 seconds"))
        #expect(StatFormatter.elapsedTime(0)
            == FormattedStat(value: "0:00", unit: "", spoken: "0 seconds"))
        #expect(StatFormatter.elapsedTime(3600)
            == FormattedStat(value: "1:00:00", unit: "", spoken: "1 hour"))
        #expect(StatFormatter.elapsedTime(61).spoken == "1 minute 1 second")
    }

    /// A clock shows the seconds completed, so 59.99 s is still 0:59.
    @Test func timeShowsCompletedSeconds() {
        #expect(StatFormatter.elapsedTime(59.99).value == "0:59")
        #expect(StatFormatter.elapsedTime(754.9).value == "12:34")
    }

    @Test func missingOrNegativeTimeIsADash() {
        #expect(StatFormatter.elapsedTime(nil) == FormattedStat(value: "–", unit: "", spoken: "No data"))
        #expect(StatFormatter.elapsedTime(-1).value == "–")
    }
}

@Suite struct SpeedAndPaceFormatTests {
    /// 10 m/s is 36 km/h, and 36,000 m / 1,609.344 = 22.37 mph.
    @Test func speedIsPerHourToOnePlace() {
        #expect(StatFormatter.speed(10, units: .metric, locale: british)
            == FormattedStat(value: "36.0", unit: "km/h", spoken: "36.0 kilometres per hour"))
        #expect(StatFormatter.speed(10, units: .imperial, locale: british)
            == FormattedStat(value: "22.4", unit: "mph", spoken: "22.4 miles per hour"))
        #expect(StatFormatter.speed(0, units: .metric, locale: british).value == "0.0")
    }

    @Test func missingSpeedIsADash() {
        #expect(StatFormatter.speed(nil, units: .metric, locale: british)
            == FormattedStat(value: "–", unit: "km/h", spoken: "No data"))
    }

    /// At 2.5 m/s a kilometre takes 400 s, 6:40, and a mile takes
    /// 1,609.344 / 2.5 = 643.7 s, which rounds to 644 s, 10:44.
    @Test func paceIsMinutesAndSecondsPerUnit() {
        #expect(StatFormatter.pace(2.5, units: .metric)
            == FormattedStat(value: "6:40", unit: "/km", spoken: "6 minutes 40 seconds per kilometre"))
        #expect(StatFormatter.pace(2.5, units: .imperial)
            == FormattedStat(value: "10:44", unit: "/mi", spoken: "10 minutes 44 seconds per mile"))
    }

    /// 1,000 / 3.34 = 299.4 s rounds to 4:59, and 1,000 / 3.335 = 299.85 s
    /// rounds up to 300 s, which is 5:00 and not 4:60.
    @Test func paceRoundsToTheNearestSecond() {
        #expect(StatFormatter.pace(3.34, units: .metric).value == "4:59")
        #expect(StatFormatter.pace(3.335, units: .metric).value == "5:00")
    }

    /// At 0.2 m/s a kilometre takes 5,000 s, 83 min 20 s: minutes run past
    /// 59. At 0.1 m/s it takes 10,000 s, slower than the 5,999 s limit.
    @Test func aStoppedAthleteHasNoPace() {
        #expect(StatFormatter.pace(0.2, units: .metric).value == "83:20")
        #expect(StatFormatter.pace(0.1, units: .metric) == FormattedStat(value: "–", unit: "/km", spoken: "No data"))
        #expect(StatFormatter.pace(0, units: .metric).value == "–")
        #expect(StatFormatter.pace(nil, units: .imperial) == FormattedStat(value: "–", unit: "/mi", spoken: "No data"))
    }
}

@Suite struct WholeNumberFormatTests {
    /// Halves round away from zero: 187.5 W shows as 188.
    @Test func powerIsWholeWatts() {
        #expect(StatFormatter.power(187.4, locale: british) == FormattedStat(value: "187", unit: "W", spoken: "187 watts"))
        #expect(StatFormatter.power(187.5, locale: british).value == "188")
    }

    /// Coasting at 0 W is a reading and shows as 0. No reading is a dash.
    @Test func zeroPowerIsNotMissing() {
        #expect(StatFormatter.power(0, locale: british).value == "0")
        #expect(StatFormatter.power(nil, locale: british) == FormattedStat(value: "–", unit: "W", spoken: "No data"))
    }

    @Test func heartRateIsWholeBeats() {
        #expect(StatFormatter.heartRate(142.4, locale: british)
            == FormattedStat(value: "142", unit: "bpm", spoken: "142 beats per minute"))
        #expect(StatFormatter.heartRate(nil, locale: british).value == "–")
    }

    @Test func cadenceUnitFollowsTheSport() {
        #expect(StatFormatter.cadence(86, sport: .cycling, locale: british)
            == FormattedStat(value: "86", unit: "rpm", spoken: "86 revolutions per minute"))
        #expect(StatFormatter.cadence(112, sport: .walking, locale: british)
            == FormattedStat(value: "112", unit: "spm", spoken: "112 steps per minute"))
        #expect(StatFormatter.cadence(nil, sport: .running, locale: british).unit == "spm")
    }

    /// 100 m is 100 / 0.3048 = 328.08 ft and 1,000 m is 3,280.84 ft, shown
    /// without a grouping separator.
    @Test func elevationIsWholeMetresOrFeet() {
        #expect(StatFormatter.elevation(123.4, units: .metric, locale: british)
            == FormattedStat(value: "123", unit: "m", spoken: "123 metres"))
        #expect(StatFormatter.elevation(100, units: .imperial, locale: british)
            == FormattedStat(value: "328", unit: "ft", spoken: "328 feet"))
        #expect(StatFormatter.elevation(1000, units: .imperial, locale: british).value == "3281")
        #expect(StatFormatter.elevation(nil, units: .imperial, locale: british).value == "–")
    }

    /// Below sea level takes a true minus sign. −0.4 m rounds to zero, which
    /// has no sign.
    @Test func negativeElevationHasAMinusSign() {
        #expect(StatFormatter.elevation(-12.4, units: .metric, locale: british).value == "−12")
        #expect(StatFormatter.elevation(-0.4, units: .metric, locale: british).value == "0")
    }
}

@Suite struct GradientFormatTests {
    /// 0.0523 is 5.23%, shown as 5.2. −0.031 is −3.1%.
    @Test func gradientIsPercentToOnePlace() {
        #expect(StatFormatter.gradient(0.0523, locale: british)
            == FormattedStat(value: "5.2", unit: "%", spoken: "5.2 percent"))
        #expect(StatFormatter.gradient(-0.031, locale: british).value == "−3.1")
        #expect(StatFormatter.gradient(0.2, locale: british).value == "20.0")
        #expect(StatFormatter.gradient(-0.031, locale: german).value == "−3,1")
    }

    /// −0.0004 is −0.04%, which rounds to 0.0 and loses its sign.
    @Test func aGradientThatRoundsToZeroHasNoSign() {
        #expect(StatFormatter.gradient(-0.0004, locale: british).value == "0.0")
    }

    @Test func missingGradientIsADash() {
        #expect(StatFormatter.gradient(nil, locale: british) == FormattedStat(value: "–", unit: "%", spoken: "No data"))
    }
}

@Suite struct StatSlotTests {
    private let everything = CursorStats(
        distance: 12_340, elapsedTime: 3725, speed: 10, power: 187.4,
        heartRate: 142.4, cadence: 86, elevation: 123.4, gradient: 0.0523
    )

    /// The spec's cycling row, in its order.
    @Test func cyclingShowsSpeedAndPower() {
        let slots = StatSlots.cursor(everything, sport: .cycling, units: .metric, locale: british)
        #expect(slots.map(\.label) == [
            "Distance", "Time", "Speed", "3 s power", "Heart rate", "Cadence", "Elevation", "Gradient",
        ])
        #expect(slots.map(\.stat.value) == ["12.34", "1:02:05", "36.0", "187", "142", "86", "123", "5.2"])
        #expect(slots.map(\.stat.unit) == ["km", "", "km/h", "W", "bpm", "rpm", "m", "%"])
        #expect(slots[3].spokenLabel == "3-second power")
    }

    /// The spec's row for walking, running and hiking: pace in place of
    /// speed, and no power. 10 m/s is 100 s per kilometre, 1:40.
    @Test(arguments: [Sport.walking, .running, .hiking])
    func onFootShowsPaceAndNoPower(sport: Sport) {
        let slots = StatSlots.cursor(everything, sport: sport, units: .metric, locale: british)
        #expect(slots.map(\.label) == ["Distance", "Time", "Pace", "Heart rate", "Cadence", "Elevation", "Gradient"])
        #expect(slots[2].stat == FormattedStat(value: "1:40", unit: "/km", spoken: "1 minute 40 seconds per kilometre"))
        #expect(slots[4].stat.unit == "spm")
    }

    @Test func otherSportsShowSpeedWithoutPowerOrCadence() {
        let slots = StatSlots.cursor(everything, sport: .other, units: .metric, locale: british)
        #expect(slots.map(\.label) == ["Distance", "Time", "Speed", "Heart rate", "Elevation", "Gradient"])
    }

    @Test func unitsFollowTheUnitSystem() {
        let slots = StatSlots.cursor(everything, sport: .cycling, units: .imperial, locale: british)
        #expect(slots.map(\.stat.unit) == ["mi", "", "mph", "W", "bpm", "rpm", "ft", "%"])
    }

    /// Nothing at the cursor: every slot is a dash, and none is a zero.
    @Test func missingValuesAreDashes() {
        let slots = StatSlots.cursor(CursorStats(), sport: .cycling, units: .metric, locale: british)
        #expect(slots.count == 8)
        #expect(slots.allSatisfy { $0.stat.value == "–" && $0.stat.spoken == "No data" })
    }

    /// 600 s, 5,000 m, 87.6 m of ascent, 201.5 W and 151.2 bpm.
    @Test func rangeShowsTheSpecsFiveStats() {
        let stats = RangeStats(time: 600, distance: 5000, ascent: 87.6, averagePower: 201.5, averageHeartRate: 151.2)
        let slots = StatSlots.range(stats, sport: .cycling, units: .metric, locale: british)
        #expect(slots.map(\.label) == ["Time", "Distance", "Ascent", "Avg power", "Avg HR"])
        #expect(slots.map(\.stat.value) == ["10:00", "5.00", "88", "202", "151"])
    }

    @Test func rangeOnFootHasNoPower() {
        let slots = StatSlots.range(RangeStats(time: 600), sport: .walking, units: .metric, locale: british)
        #expect(slots.map(\.label) == ["Time", "Distance", "Ascent", "Avg HR"])
        #expect(slots.map(\.stat.value) == ["10:00", "–", "–", "–"])
    }

    /// Until the caller supplies the range's stats, every slot is a dash.
    @Test func rangeWithoutStatsIsDashes() {
        let slots = StatSlots.range(nil, sport: .cycling, units: .metric, locale: british)
        #expect(slots.allSatisfy { $0.stat.value == "–" })
    }
}

@Suite struct StatGridTests {
    /// Eight slots, laid out row by row.
    private let widths: [Double] = [87, 74, 70, 66, 60, 62, 62, 66]

    /// In four columns the rows are 87 74 70 66 and 60 62 62 66, so the
    /// columns are 87, 74, 70 and 66 wide. In three the rows are 87 74 70,
    /// 66 60 62 and 62 66, so the columns are 87, 74 and 70.
    @Test func aColumnIsAsWideAsItsWidestSlot() {
        #expect(StatGrid.columnWidths(slotWidths: widths, columns: 4) == [87, 74, 70, 66])
        #expect(StatGrid.columnWidths(slotWidths: widths, columns: 3) == [87, 74, 70])
        #expect(StatGrid.columnWidths(slotWidths: widths, columns: 2) == [87, 74])
        #expect(StatGrid.columnWidths(slotWidths: widths, columns: 1) == [87])
    }

    /// With 12 between columns, four columns need 297 + 36 = 333, three need
    /// 231 + 24 = 255 and two need 161 + 12 = 173.
    @Test func asManyColumnsAsFit() {
        #expect(StatGrid.columns(available: 376, slotWidths: widths, spacing: 12, maximum: 4) == 4)
        #expect(StatGrid.columns(available: 333, slotWidths: widths, spacing: 12, maximum: 4) == 4)
        #expect(StatGrid.columns(available: 330, slotWidths: widths, spacing: 12, maximum: 4) == 3)
        #expect(StatGrid.columns(available: 200, slotWidths: widths, spacing: 12, maximum: 4) == 2)
    }

    /// At the largest text sizes a slot is wider than half the panel, so the
    /// slots stack in one column. There is always at least one, even when a
    /// slot is wider than the panel.
    @Test func largeSlotsReflowToOneColumn() {
        #expect(StatGrid.columns(available: 376, slotWidths: [250, 240, 230], spacing: 12, maximum: 4) == 1)
        #expect(StatGrid.columns(available: 100, slotWidths: widths, spacing: 12, maximum: 4) == 1)
        #expect(StatGrid.columns(available: 376, slotWidths: [500], spacing: 12, maximum: 4) == 1)
    }

    /// Two columns of 87 and 74 in 376: each step is 188, which holds either
    /// column and the 12 of spacing, so the second column starts halfway.
    @Test func columnsStartAtEqualStepsWhenTheyFit() {
        #expect(StatGrid.columnOrigins(columnWidths: [87, 74], available: 376, spacing: 12) == [0, 188])
        #expect(StatGrid.columnOrigins(columnWidths: [87], available: 376, spacing: 12) == [0])
    }

    /// Four columns of 87, 74, 70 and 66 in 376: a step of 94 cannot hold
    /// the first column's 87 + 12, so the columns are packed. The 376 − 297
    /// = 79 left over is shared as three gaps of 26⅓, so the columns start
    /// at 0, 113⅓, 213⅔ and 310, and the last ends at 376.
    @Test func columnsArePackedWhenEqualStepsAreTooNarrow() {
        let origins = StatGrid.columnOrigins(columnWidths: [87, 74, 70, 66], available: 376, spacing: 12)
        let expected = [0, 113 + 1.0 / 3, 213 + 2.0 / 3, 310]
        #expect(origins.count == 4)
        for (origin, value) in zip(origins, expected) { #expect(abs(origin - value) < 1e-9) }
    }

    /// The last column needs no spacing after it: three columns of 100 fit
    /// steps of exactly 112 and of 100 plus 12.
    @Test func theLastColumnNeedsNoSpacing() {
        #expect(StatGrid.columnOrigins(columnWidths: [100, 100, 112], available: 336, spacing: 12) == [0, 112, 224])
    }

    /// Never more columns than slots or than the maximum.
    @Test func columnsAreCapped() {
        #expect(StatGrid.columns(available: 1000, slotWidths: widths, spacing: 12, maximum: 4) == 4)
        #expect(StatGrid.columns(available: 1000, slotWidths: [60, 60], spacing: 12, maximum: 4) == 2)
    }
}
