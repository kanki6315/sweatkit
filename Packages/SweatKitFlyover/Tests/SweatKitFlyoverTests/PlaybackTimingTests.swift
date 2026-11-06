import Testing
@testable import SweatKitFlyover

@Suite struct PlaybackTimingTests {
    @Test(arguments: [2, 11, 3601, 18001, 86401])
    func fullOverviewTakesThirtySeconds(count: Int) {
        let halfway = PlaybackTiming.overview.advance(sample: 0, sampleCount: count, wallSeconds: 15)
        #expect(halfway == Double(count - 1) / 2)
        #expect(PlaybackTiming.overview.advance(sample: halfway, sampleCount: count, wallSeconds: 15) == Double(count - 1))
    }

    @Test func inspectionAndRecordedTime() {
        #expect(PlaybackTiming.halfSpeed.advance(sample: 0, sampleCount: 3601, wallSeconds: 30) == 1800)
        #expect(PlaybackTiming.quarterSpeed.advance(sample: 0, sampleCount: 3601, wallSeconds: 30) == 900)
        #expect(PlaybackTiming.recorded.advance(sample: 50, sampleCount: 3601, wallSeconds: 10) == 60)
    }

    @Test func resumeAfterScrubAndDroppedFrames() {
        // Resume halfway through a one-hour timeline. A delayed two-second
        // frame still advances 240 elapsed samples at the 30-second setting.
        #expect(PlaybackTiming.overview.advance(sample: 1800, sampleCount: 3601, wallSeconds: 2) == 2040)
        #expect(PlaybackTiming.overview.advance(sample: 3500, sampleCount: 3601, wallSeconds: 2) == 3600)
        #expect(PlaybackTiming.overview.advance(sample: 1800, sampleCount: 3601, wallSeconds: 0) == 1800)
    }

    @Test func emptySingleSampleAndInvalidInputs() {
        for count in [0, 1] {
            #expect(PlaybackTiming.overview.advance(sample: 0, sampleCount: count, wallSeconds: 30) == 0)
        }
        #expect(PlaybackTiming.overview.advance(sample: 50, sampleCount: 101, wallSeconds: .nan) == 50)
        #expect(PlaybackTiming.overview.advance(sample: 50, sampleCount: 101, wallSeconds: -1) == 50)
    }

    @Test func manualCameraSurvivesReduceMotion() {
        var options = FlyoverOptions(cameraMode: .manual)
        #expect(options.effectiveCameraMode(reduceMotion: true) == .manual)
        options.cameraMode = .follow
        #expect(options.effectiveCameraMode(reduceMotion: true) == .overview)
    }
}
