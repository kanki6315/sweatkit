import SweatKitFlyover
import SweatKitModel
@_spi(Diagnostics) import SweatKitTimeline
import SwiftUI

struct HarnessView: View {
    @State private var model = HarnessModel()

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 8) {
                if let activity = model.activity {
                    if model.showsPanels {
                        StatsPanel(stats: model.cursorStats, sport: activity.sport, units: model.units)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        readout(activity)
                        controls(activity)
                    }
                    // The harness's own chrome stays small, so the largest
                    // text sizes show the components and not the readout.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Spacer(minLength: 0)
                    if model.showsPanels {
                        ActivityTimeline(
                            data: activity.timeline,
                            overlay: model.overlay,
                            scrubSample: $model.scrub,
                            selection: $model.selection,
                            selectionStats: model.rangeStats,
                            axisMode: model.axisMode,
                            collapsesStops: model.collapsesStops,
                            sport: activity.sport,
                            units: model.units
                        )
                    }
                } else {
                    Spacer()
                    if let error = model.loadError {
                        Text(error).foregroundStyle(.red)
                    } else {
                        ProgressView("Decoding")
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .task(id: model.file) { await model.load() }
        .task(id: model.overlayChoice) { await model.buildOverlay() }
        .task(id: model.selection) { await model.updateRangeStats() }
    }

    @ViewBuilder
    private var background: some View {
        if model.backdrop == .map, let route = model.route {
            FlyoverMap(route: route.route, bandColors: route.colors, scrubSample: $model.scrub)
        } else {
            DrawnBackdrop(backdrop: model.backdrop)
        }
    }

    private func readout(_ activity: LoadedActivity) -> some View {
        let monitor = model.monitor
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(activity.stream.count) samples · \(activity.timeline.stops.count) stops · \(activity.lapCount) laps")
            Text(String(format: "now %.0f fps", monitor.currentFPS)
                + (monitor.worstFPS.map { String(format: " · worst %.0f", $0) } ?? "")
                + (monitor.longestFrame.map { String(format: " · longest %.1f ms", $0) } ?? "")
                + " · hitches \(monitor.hitches)"
                + (monitor.isMeasuring ? " · measuring" : ""))
            Text("chart redraws \(TimelineDiagnostics.chartDrawCount)")
        }
        .font(.caption2.monospacedDigit())
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.65), in: .rect(cornerRadius: 8))
        .foregroundStyle(.white)
        .accessibilityIdentifier("readout")
    }

    private func controls(_ activity: LoadedActivity) -> some View {
        VStack(spacing: 6) {
            Menu {
                Picker("File", selection: $model.file) {
                    ForEach(FileChoice.allCases) { Text($0.label).tag($0) }
                }
                Picker("Overlay", selection: $model.overlayChoice) {
                    ForEach(OverlayChoice.allCases) { Text($0.label(for: activity.sport)).tag($0) }
                }
                Picker("Axis", selection: $model.axisMode) {
                    Text("Distance axis").tag(TimelineAxisMode.distance)
                    Text("Time axis").tag(TimelineAxisMode.time)
                }
                Toggle("Collapse stops", isOn: $model.collapsesStops)
                Picker("Units", selection: $model.units) {
                    Text("Metric").tag(UnitSystem.metric)
                    Text("Imperial").tag(UnitSystem.imperial)
                }
                Picker("Background", selection: $model.backdrop) {
                    ForEach(Backdrop.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show panels", isOn: $model.showsPanels)
            } label: {
                chip("Options", systemImage: "slider.horizontal.3")
            }
            Button { model.toggleSweep() } label: {
                chip(model.isSweeping ? "Stop" : "Sweep", systemImage: model.isSweeping ? "stop.fill" : "play.fill")
            }
            Button { model.toggleMeasuring() } label: {
                chip(
                    model.monitor.isMeasuring && !model.isSweeping ? "Stop" : "Measure",
                    systemImage: "stopwatch"
                )
            }
            .disabled(model.isSweeping)
        }
        .accessibilityIdentifier("controls")
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.65), in: .rect(cornerRadius: 8))
            .foregroundStyle(.white)
    }
}
