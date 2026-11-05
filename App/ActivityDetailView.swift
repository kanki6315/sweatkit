import SwiftUI
import SweatKitModel
import SweatKitDetail
import SweatKitFlyover
import SweatKitLibrary
import SweatKitPalette
import SweatKitStore
import SweatKitTimeline

struct ActivityDetailView: View {
    let activity: ActivityRecord
    let library: ActivityLibrary?
    @State private var current: ActivityRecord?
    private var record: ActivityRecord { current ?? activity }
    @State private var summaryOnly = false
    @State private var prepared: PreparedDetail?
    @State private var error: String?
    @State private var scrub = 0.0
    @State private var selection: ClosedRange<Int>?
    @State private var selectionStats: RangeStats?
    @State private var overlay = RouteOverlay.plain
    @State private var timelineOverlay: TimelineOverlay?
    @State private var units = SweatKitModel.UnitSystem.metric
    @State private var axis = TimelineAxisMode.distance
    @State private var collapsesStops = false
    @State private var options = FlyoverOptions()

    var body: some View {
        Group {
            if summaryOnly {
                List {
                    Section {
                        LabeledContent("Elapsed time", value: Duration.seconds(record.elapsedTime).formatted(.time(pattern: .hourMinuteSecond)))
                        if let timer = record.timerTime {
                            LabeledContent("Timer time", value: Duration.seconds(timer).formatted(.time(pattern: .hourMinuteSecond)))
                        }
                        if let distance = record.distance {
                            LabeledContent("Recorded distance", value: String(format: "%.2f %@", distance / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi"))
                        }
                    } header: { Text("Recorded summary") } footer: {
                        Text("This recording has no visible per-second samples. Charts, zones and a route cannot be shown. If you expected samples from Apple Health, review read access in Health settings and refresh.")
                    }
                    if let library {
                        NavigationLink("Activity info and sources") { ActivityManagementView(activity: record, library: library) }
                    }
                }.monospacedDigit()
            } else if let prepared {
                ZStack {
                    if let route = prepared.route(for: overlay).value {
                        FlyoverMap(route: route, bandColors: colors, scrubSample: $scrub, options: options)
                            .ignoresSafeArea(edges: .bottom)
                    } else {
                        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    }
                    VStack(spacing: 12) {
                        StatsPanel(stats: prepared.cursorStats(at: Int(scrub)), sport: record.sport, units: units)
                        if prepared.line.value == nil {
                            Text(record.isVirtual ? "Virtual activity · no outdoor route" : "No outdoor route recorded")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let timeline = prepared.timeline {
                            ActivityTimeline(data: timeline, overlay: timelineOverlay,
                                             scrubSample: $scrub, selection: $selection, selectionStats: selectionStats,
                                             axisMode: axis, collapsesStops: collapsesStops, sport: record.sport, units: units)
                        }
                    }.padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let library {
                                NavigationLink("Activity info and sources") {
                                    ActivityManagementView(activity: record, library: library)
                                }
                            }
                            Picker("Overlay", selection: $overlay) {
                                ForEach(RouteOverlay.allCases, id: \.self) { item in
                                    Text(item.label).tag(item).disabled(prepared.bands[item]?.value == nil)
                                }
                            }
                            Picker("Timeline axis", selection: $axis) {
                                Text("Distance").tag(TimelineAxisMode.distance)
                                Text("Time").tag(TimelineAxisMode.time)
                            }
                            Toggle("Collapse stops", isOn: $collapsesStops)
                            Picker("Map", selection: $options.mapStyle) {
                                Text("Satellite").tag(FlyoverOptions.MapStyle.satellite)
                                Text("Standard").tag(FlyoverOptions.MapStyle.standard)
                            }
                            Picker("Camera", selection: $options.cameraMode) {
                                Text("Overview").tag(FlyoverOptions.CameraMode.overview)
                                Text("Follow").tag(FlyoverOptions.CameraMode.follow)
                            }
                        } label: { Label(overlay.label, systemImage: "slider.horizontal.3") }
                    }
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open activity", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else { ProgressView("Preparing activity") }
        }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: overlay) { updateTimelineOverlay() }
        .task(id: selection) {
            guard let selection, let prepared else { selectionStats = nil; return }
            let result = await Task.detached(priority: .userInitiated) { prepared.rangeStats(selection) }.value
            guard !Task.isCancelled else { return }
            selectionStats = result
        }
    }

    private func updateTimelineOverlay() {
        guard let series = prepared?.timelineOverlay(for: overlay) else { timelineOverlay = nil; return }
        timelineOverlay = TimelineOverlay(kind: series.kind, values: series.values,
                                          bands: series.bands, bandColors: colors)
    }

    private var colors: [Color] {
        switch overlay {
        case .power: EffortPalette.power.map(\.color)
        case .heartRate: EffortPalette.heartRate.map(\.color)
        case .paceOrSpeed: EffortPalette.pace.map(\.color)
        case .gradient: EffortPalette.gradient.map(\.color)
        case .plain: [.secondary]
        }
    }

    private func load() async {
        guard let library, let id = activity.id else { error = "Open the library and try again."; return }
        error = nil
        prepared = nil
        summaryOnly = false
        do {
            current = try await library.activity(id)
            async let stream = library.analysisStream(for: id)
            async let recorded = library.recordedActivity(for: id)
            async let profile = library.profile()
            let native = try await recorded
            let athlete = try await profile
            units = athlete.units
            summaryOnly = native.stream.samples.isEmpty
            if summaryOnly { return }
            let input = try await DetailInput(stream: stream, sport: record.sport,
                isIndoor: record.isIndoor, isVirtual: record.isVirtual,
                lapStarts: DetailInput.lapStarts(of: native.laps, streamStart: stream.start),
                profile: athlete, activityDate: record.start)
            let result = await Task.detached(priority: .userInitiated) { DetailPreparation.prepare(input) }.value
            guard !Task.isCancelled else { return }
            prepared = result
            overlay = result.defaultOverlay
            units = input.profile.units
            updateTimelineOverlay()
            if result.timeline?.distance == nil { axis = .time }
        } catch { self.error = error.localizedDescription }
    }
}

private extension RouteOverlay {
    var label: String {
        switch self {
        case .power: "Power"
        case .heartRate: "Heart rate"
        case .paceOrSpeed: "Pace / speed"
        case .gradient: "Gradient"
        case .plain: "No overlay"
        }
    }
}
