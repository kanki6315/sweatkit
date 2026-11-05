import SweatKitPalette
import Testing

/// The values here are the ones recorded in `DESIGN.md`. A change to either
/// has to be made in both, after the palette has been measured again.
@Suite struct EffortPaletteTests {
    @Test func powerHasSevenZonesInOrder() {
        #expect(EffortPalette.power.map(\.hex) == [0x184998, 0x0E89D6, 0x65CBE3, 0xF8E94C, 0xFE9823, 0xEA5202, 0xBA0329])
    }

    @Test func heartRateAndPaceReuseFiveOfThePowerColours() {
        // Zones 1 to 4 and zone 6 of power: the amber of zone 5 is skipped.
        let expected: [UInt32] = [0x184998, 0x0E89D6, 0x65CBE3, 0xF8E94C, 0xEA5202]
        #expect(EffortPalette.heartRate.map(\.hex) == expected)
        #expect(EffortPalette.pace.map(\.hex) == expected)
    }

    @Test func gradientHasFiveBandsOfItsOwn() {
        #expect(EffortPalette.gradient.map(\.hex) == [0x1B8FA5, 0xE0DED7, 0xE6B14E, 0xC3610D, 0x6D2A1A])
        // Terrain is not effort: no gradient colour is an effort colour.
        #expect(Set(EffortPalette.gradient).isDisjoint(with: Set(EffortPalette.power)))
    }

    @Test func noRampRepeatsAColour() {
        for ramp in [EffortPalette.power, EffortPalette.heartRate, EffortPalette.gradient] {
            #expect(Set(ramp).count == ramp.count)
        }
    }

    @Test func aHexSplitsIntoItsThreeChannels() {
        // 0xF8E94C: F8 = 248, E9 = 233, 4C = 76, each over 255.
        let yellow = RampColor(hex: 0xF8E94C).components
        #expect(yellow.red == 248.0 / 255)
        #expect(yellow.green == 233.0 / 255)
        #expect(yellow.blue == 76.0 / 255)
    }
}
