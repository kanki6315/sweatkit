import SwiftUI
import SweatKitIdentity
import SweatKitAnalysis
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var alternatives: [AlternativeOffer] = []
    @State private var presentation: DetailAnalysisPresentation?
    @State private var metrics: ActivityMetrics?
    @State private var showsAnalysis = false
    @State private var playing = false
    @State private var playbackSpeed = 1.0
    @State private var timelineKind: TimelineOverlay.Kind?
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
                        Text(record.sport.hasFullSupport ? "This recording has no visible per-second samples. Charts, zones and a route cannot be shown. If you expected samples from Apple Health, review read access in Health settings and refresh." : "This sport is shown as a summary. Full detail is available for cycling, walking, running and hiking.")
                    }
                    if let library {
                        NavigationLink("Activity info and sources") { ActivityManagementView(activity: record, library: library) }
                    }
                }.monospacedDigit()
            } else if let prepared {
                detailSurface(prepared)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if prepared.line.value != nil {
                                Button("Charts, laps and zones") { showsAnalysis = true }
                            }
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
                            Picker("Timeline series", selection: $timelineKind) {
                                Text("None").tag(nil as TimelineOverlay.Kind?)
                                ForEach(TimelineOverlay.Kind.allCases, id: \.self) { kind in
                                    if prepared.timelineOverlays[kind] != nil {
                                        Text(kind.rawValue.capitalized).tag(Optional(kind))
                                    }
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
        .onChange(of: overlay) {
            timelineKind = prepared?.timelineKind(for: overlay)
            updateTimelineOverlay()
        }
        .onChange(of: timelineKind) { updateTimelineOverlay() }
        .onChange(of: playing) { options.dimsAhead = playing }
        .onChange(of: scenePhase) { if scenePhase != .active { playing = false } }
        .onDisappear { playing = false }
        .task(id: playing) { await play() }
        .sheet(isPresented: $showsAnalysis) {
            if let presentation, let prepared {
                NavigationStack {
                    analysis(presentation, prepared)
                        .safeAreaInset(edge: .bottom) { timeline(prepared) }
                        .navigationTitle("Analysis")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { showsAnalysis = false } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task(id: selection) {
            guard let selection, let prepared else { selectionStats = nil; return }
            let result = await Task.detached(priority: .userInitiated) { prepared.rangeStats(selection) }.value
            guard !Task.isCancelled else { return }
            selectionStats = result
        }
    }

    private func updateTimelineOverlay() {
        guard let timelineKind, let series = prepared?.timelineOverlays[timelineKind] else { timelineOverlay = nil; return }
        timelineOverlay = TimelineOverlay(kind: series.kind, values: series.values,
                                          bands: series.bands, bandColors: timelineColors)
    }

    private var manualScrub: Binding<Double> {
        Binding(get: { scrub }, set: { playing = false; scrub = $0 })
    }

    @ViewBuilder private func detailSurface(_ detail: PreparedDetail) -> some View {
        Group {
            if let route = detail.route(for: overlay).value {
                FlyoverMap(route: route, bandColors: colors, scrubSample: manualScrub, options: options)
                    .ignoresSafeArea(edges: .bottom)
            } else if let presentation {
                analysis(presentation, detail)
            }
        }
        .safeAreaInset(edge: .top) {
            if !showsAnalysis {
                VStack(spacing: 8) {
                    if !alternatives.isEmpty, let library {
                        NavigationLink {
                            ActivityManagementView(activity: record, library: library)
                        } label: {
                            Label("Another recording has additional data. Review sources", systemImage: "square.stack")
                                .font(.subheadline)
                        }.buttonStyle(.bordered).padding(.horizontal)
                    }
                    if detail.line.value != nil {
                        StatsPanel(stats: detail.cursorStats(at: Int(scrub)), sport: record.sport, units: units).padding(.horizontal)
                    }
                }.padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !showsAnalysis { timeline(detail) }
        }
    }

    private func analysis(_ presentation: DetailAnalysisPresentation, _ detail: PreparedDetail) -> some View {
        ActivityAnalysisView(presentation: presentation, detail: detail, metrics: metrics, units: units,
                             scrub: manualScrub, selection: $selection)
    }

    @ViewBuilder private func timeline(_ detail: PreparedDetail) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
                    if scrub >= Double(detail.input.stream.count - 1) { scrub = 0 }
                    playing.toggle()
                }
                Picker("Playback speed", selection: $playbackSpeed) {
                    ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { speed in Text("\(speed, specifier: "%g")×").tag(speed) }
                }.pickerStyle(.menu)
                Spacer()
                Text(overlay.label).font(.caption).accessibilityLabel("Route overlay: \(overlay.label)")
                if detail.line.value != nil {
                    Button("Analysis", systemImage: "chart.xyaxis.line") { showsAnalysis = true }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: Capsule())
            if let data = detail.timeline {
                ActivityTimeline(data: data, overlay: timelineOverlay, scrubSample: manualScrub,
                    selection: $selection, selectionStats: selectionStats, axisMode: axis,
                    collapsesStops: collapsesStops, sport: record.sport, units: units)
            }
        }.padding()
    }

    private var timelineColors: [Color] {
        switch timelineKind {
        case .power: EffortPalette.power.map(\.color)
        case .heartRate: EffortPalette.heartRate.map(\.color)
        case .pace, .speed: EffortPalette.pace.map(\.color)
        default: []
        }
    }

    private func play() async {
        guard playing, let prepared, prepared.input.stream.count > 1 else { return }
        var last = ContinuousClock.now
        while playing && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            let now = ContinuousClock.now
            let elapsed = last.duration(to: now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            last = now
            let end = Double(prepared.input.stream.count - 1)
            scrub = min(end, scrub + seconds * end / 60 * playbackSpeed)
            if scrub >= end { playing = false }
        }
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
        presentation = nil
        playing = false
        summaryOnly = false
        do {
            current = try await library.activity(id)
            async let stream = library.analysisStream(for: id)
            async let recorded = library.recordedActivity(for: id)
            async let profile = library.profile()
            async let storedMetrics = library.metrics(for: id)
            async let sourceOffers = library.alternativeSources(for: id)
            let native = try await recorded
            let athlete = try await profile
            units = athlete.units
            metrics = try await storedMetrics
            alternatives = try await sourceOffers
            summaryOnly = native.stream.samples.isEmpty || !record.sport.hasFullSupport
            if summaryOnly { return }
            let input = try await DetailInput(stream: stream, sport: record.sport,
                isIndoor: record.isIndoor, isVirtual: record.isVirtual,
                lapStarts: DetailInput.lapStarts(of: native.laps, streamStart: stream.start),
                recordedLaps: native.laps,
                profile: athlete, activityDate: record.start)
            let result = await Task.detached(priority: .userInitiated) {
                let detail = DetailPreparation.prepare(input)
                return (detail, DetailAnalysisPresentation.prepare(detail))
            }.value
            guard !Task.isCancelled else { return }
            prepared = result.0
            presentation = result.1
            overlay = result.0.defaultOverlay
            timelineKind = result.0.timelineKind(for: overlay)
                ?? (result.0.timelineOverlays[.power] != nil ? .power : nil)
            units = input.profile.units
            updateTimelineOverlay()
            if result.0.timeline?.distance == nil { axis = .time }
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
