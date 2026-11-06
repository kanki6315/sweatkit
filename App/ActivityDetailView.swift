import SwiftUI
import OSLog
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
    var deleteActivity: (@MainActor (SourceIdentity) async throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var matchedRoute: LibraryRoute?
    @State private var alternatives: [AlternativeOffer] = []
    @State private var presentation: DetailAnalysisPresentation?
    @State private var metrics: ActivityMetrics?
    @State private var historicalCurve: [PowerCurvePoint] = []
    @State private var historicalCurveError: String?
    @State private var historyWindow = 90
    @State private var historicalCurveLoading = false
    @State private var historicalSources: [SourceKind] = []
    @State private var expandsAnalysisTimeline = false
    @State private var showsAnalysis = false
    @State private var playing = false
    @State private var playbackSpeed = 1.0
    @State private var timelineKind: TimelineOverlay.Kind?
    @State private var current: ActivityRecord?
    private func routeContext(_ route: LibraryRoute, effort: RouteEffort) -> String {
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        func position(_ number: Int) -> String { ordinal.string(from: NSNumber(value: number)) ?? "\(number)" }
        var parts = [route.name]
        if let occurrence = route.occurrence(of: effort.id) { parts.append("\(position(occurrence)) time on this route") }
        if let rank = route.rank(of: effort.id) {
            parts.append("\(position(rank)) fastest")
            if let gap = route.secondsBehindBest(of: effort.id), gap >= 0.5 {
                parts.append("\(Duration.seconds(gap).formatted(.time(pattern: .minuteSecond))) behind best")
            }
        } else { parts.append("Moving time unavailable") }
        return parts.joined(separator: " · ") + " · Compare"
    }

    private var record: ActivityRecord { current ?? activity }
    @State private var summaryOnly = false
    @State private var golfRecording: GolfHealthRecording?
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

    private static let performanceLog = Logger(subsystem: "com.arjunakankipati.sweatkit", category: "MapPerformance")

    var body: some View {
        Group {
            if summaryOnly {
                List {
                    if let golfRecording {
                        GolfHealthSections(recording: golfRecording, units: units)
                    } else {
                        Section {
                            SourceAttributionView(sources: record.members.map(\.source))
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
                    }
                    if let library {
                        NavigationLink("Activity details") { ActivityManagementView(activity: record, library: library, deleteActivity: deleteActivity) }
                    }
                }.monospacedDigit()
            } else if let prepared {
                detailSurface(prepared)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open activity", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else { ProgressView("Preparing activity") }
        }
        .background { if prepared != nil { DetailBackGesture() } }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(prepared == nil ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await DetailPreparationCache.shared.removeAll() }
        }
        .task(id: record.id) {
            guard let library, let id = record.id else { return }
            do {
                let catalog = try await library.routes()
                try Task.checkCancellation()
                matchedRoute = catalog.membership(of: id)
            } catch { matchedRoute = nil }
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
                        .safeAreaInset(edge: .bottom) {
                            if expandsAnalysisTimeline {
                                VStack(spacing: 0) {
                                    Button("Compact timeline", systemImage: "chevron.down") { expandsAnalysisTimeline = false }.font(.caption).frame(minHeight: 44)
                                    timeline(prepared)
                                }.background(Color(uiColor: .systemBackground))
                            } else { compactPlayback(prepared) }
                        }
                        .navigationTitle(record.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { showsAnalysis = false } }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else { ProgressView("Preparing analysis") }
        }
        .task(id: "\(showsAnalysis)-\(historyWindow)") {
            guard showsAnalysis, record.sport.family == .cycling, let library else { return }
            historicalCurve = []
            historicalSources = []
            historicalCurveError = nil
            historicalCurveLoading = true
            do {
                let history = try await library.trendsHistory()
                try Task.checkCancellation()
                let start = historyWindow == 0 ? Date.distantPast : historyWindow == 365
                    ? (Calendar.current.dateInterval(of: .year, for: record.start)?.start ?? record.start)
                    : record.start.addingTimeInterval(-90 * 86400)
                let end = record.start
                let points = await Task.detached(priority: .utility) {
                    let eligible = history.activities.filter {
                        !$0.isStale && $0.activity.start >= start && $0.activity.start < end
                            && $0.activity.sport.family == .cycling
                    }
                    let entries = eligible.flatMap { row in row.curve.map { (point: $0, source: row.activity.primary.source) } }
                    let groups = Dictionary(grouping: entries, by: { $0.point.duration })
                    let winners = groups.keys.sorted().compactMap { duration in
                        groups[duration]?.filter { $0.point.power.value != nil }.max { ($0.point.power.value ?? -.infinity) < ($1.point.power.value ?? -.infinity) }
                    }
                    return (winners.map(\.point), Array(Set(winners.map(\.source))))
                }.value
                try Task.checkCancellation()
                historicalCurve = points.0
                historicalSources = points.1
                historicalCurveLoading = false
                historicalCurveError = nil
            } catch is CancellationError { }
            catch { historicalCurve = []; historicalCurveLoading = false; historicalCurveError = "Historical comparison couldn’t load." }
        }
        .task(id: selection) {
            guard let selection, let prepared else { selectionStats = nil; return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            let worker = Task.detached(priority: .userInitiated) { prepared.rangeStats(selection) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            selectionStats = result
        }
    }

    private func compactPlayback(_ detail: PreparedDetail) -> some View {
        HStack(spacing: 12) {
            Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") { playing.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .frame(minWidth: 44, minHeight: 44)
            Button("Expand timeline", systemImage: "waveform.path") { expandsAnalysisTimeline = true }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            Slider(value: manualScrub, in: 0...Double(max(1, detail.input.stream.count - 1)))
                .tint(.primary).accessibilityLabel("Analysis playback position")
            Text(Duration.seconds(scrub.rounded(.down)).formatted(.time(pattern: .hourMinuteSecond)))
                .font(.caption.monospacedDigit()).frame(minWidth: 64, alignment: .trailing)
        }.padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
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
                    .ignoresSafeArea()
            } else if let presentation {
                ActivityAnalysisView(presentation: presentation, detail: detail, metrics: metrics, units: units, scrub: manualScrub, selection: $selection, chartsOnly: true)
            } else { ProgressView("Preparing analysis") }
        }
        .safeAreaInset(edge: .top) {
            if !showsAnalysis {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").foregroundStyle(.primary).frame(width: 36, height: 36)
                                .background(Color(uiColor: .quaternarySystemFill), in: Circle()).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Back")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(.headline).lineLimit(2)
                            Text("\(record.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(SourceAttributionView.names(record.members.map(\.source)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Menu {
                            if let library {
                                NavigationLink("Activity details") {
                                    ActivityManagementView(activity: record, library: library, deleteActivity: deleteActivity)
                                }
                            }
                            if detail.line.value != nil {
                                Toggle("Satellite map", isOn: Binding(
                                    get: { options.mapStyle == .satellite },
                                    set: { options.mapStyle = $0 ? .satellite : .standard }
                                ))
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("Activity options")
                    }.padding(.horizontal, 8).padding(.top, 8)
                    StatsPanel(stats: detail.cursorStats(at: Int(scrub)), sport: record.sport, units: units, floating: false)
                        .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 160 : nil)
                    if !alternatives.isEmpty, let library {
                        NavigationLink("Review additional source data") {
                            ActivityManagementView(activity: record, library: library, deleteActivity: deleteActivity)
                        }.font(.footnote).padding(.bottom, 12)
                    }
                }
                .modifier(FloatingPanel())
                .padding(.horizontal, 12).padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !showsAnalysis { timeline(detail) }
        }
    }

    @ViewBuilder private var routeComparisonLink: some View {
                    if let route = matchedRoute,
                       let effort = route.efforts.first(where: { $0.activity.members.contains(record.id ?? record.primary) }) {
                        NavigationLink {
                            RouteComparisonView(route: route, subject: effort, library: library, units: units)
                        } label: {
                            Label(routeContext(route, effort: effort),
                                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.padding(.horizontal, 12)
                    }
    }

    private func analysis(_ presentation: DetailAnalysisPresentation, _ detail: PreparedDetail) -> some View {
        ActivityAnalysisView(presentation: presentation, detail: detail, metrics: metrics, units: units,
                             scrub: manualScrub, selection: $selection, historicalCurve: historicalCurve, historicalCurveError: historicalCurveError, routeHeader: AnyView(VStack(alignment: .leading, spacing: 8) {
                                 Text(record.start, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                 SourceAttributionView(sources: record.members.map(\.source))
                                 routeComparisonLink
                             }), historicalSources: historicalSources, historicalCurveLoading: historicalCurveLoading, historyWindow: $historyWindow)
    }

    @ViewBuilder private func timeline(_ detail: PreparedDetail) -> some View {
        VStack(spacing: 4) {
            if !showsAnalysis {
                Button { showsAnalysis = true } label: {
                    Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Analysis")
                .accessibilityHint("Opens activity analysis. You can also swipe up here.")
                .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height < -20 { showsAnalysis = true }
                })
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    timelineSelector(detail)
                    Spacer(minLength: 0)
                    timelineAxisPicker(detail)
                }
                VStack(alignment: .leading, spacing: 8) {
                    timelineSelector(detail)
                    timelineAxisPicker(detail)
                }
            }.padding(.horizontal, 14)
            if let data = detail.timeline {
                ActivityTimeline(data: data, overlay: timelineOverlay, scrubSample: manualScrub,
                    selection: $selection, selectionStats: selectionStats, axisMode: axis,
                    collapsesStops: collapsesStops, sport: record.sport, units: units, floating: false)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    playbackButton(detail)
                    playbackSpeedPicker
                    playbackClock(detail).frame(maxWidth: .infinity)
                    cameraButton(detail)
                }
                VStack(spacing: 8) {
                    playbackClock(detail)
                    HStack {
                        playbackButton(detail)
                        playbackSpeedPicker
                        Spacer()
                        cameraButton(detail)
                    }
                }
            }.padding(.horizontal, 14).padding(.bottom, 8)
            if !showsAnalysis, matchedRoute != nil {
                Divider().padding(.horizontal, 14).padding(.top, 8)
                routeComparisonLink
            }
            if detail.line.value == nil && !showsAnalysis {
                Text(record.isVirtual ? "Virtual activity · no map" : record.isIndoor ? "Indoor activity · no map" : "No usable route · recorded charts")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
        }
        .padding(.vertical, 8)
        .modifier(FloatingPanel(enabled: !showsAnalysis))
        .background(showsAnalysis ? Color(uiColor: .systemBackground) : .clear)
        .padding(.horizontal, showsAnalysis ? 0 : 12)
        .padding(.bottom, showsAnalysis ? 0 : 8)
    }

    private var timelineMetricLabel: String {
        guard let timelineKind else { return "Elevation" }
        return timelineKind == .heartRate ? "Heart rate" : timelineKind.rawValue.capitalized
    }

    private func timelineSelector(_ detail: PreparedDetail) -> some View {
        Menu {
            Section("Chart metric") {
                Picker("Chart metric", selection: $timelineKind) {
                    if detail.timeline?.elevation.contains(where: { $0 != nil }) == true {
                        Text("Elevation").tag(nil as TimelineOverlay.Kind?)
                    }
                    ForEach(TimelineOverlay.Kind.allCases, id: \.self) { kind in
                        if detail.timelineOverlays[kind] != nil {
                            Text(kind == .heartRate ? "Heart rate" : kind.rawValue.capitalized).tag(Optional(kind))
                        }
                    }
                }
            }
            if detail.line.value != nil {
                Section("Route colour") {
                    Picker("Route colour", selection: $overlay) {
                        ForEach(RouteOverlay.allCases, id: \.self) { item in
                            if item == .plain || detail.bands[item]?.value != nil {
                                Text(item.label).tag(item)
                            }
                        }
                    }
                }
            }
            if let timeline = detail.timeline, !timeline.stops.isEmpty {
                Section("Chart options") {
                    Toggle("Hide stopped time", isOn: $collapsesStops)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timelineMetricLabel)
                        .font(.subheadline.weight(.semibold))
                    legendRamp(timelineColors)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                if detail.line.value != nil, detail.timelineKind(for: overlay) != timelineKind {
                    HStack(spacing: 6) {
                        Text("Route: \(overlay.label)").font(.caption2)
                        legendRamp(colors)
                    }.foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Color(uiColor: .quaternarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chart metric and route colour")
        .accessibilityValue(timelineMetricLabel)
    }

    private func legendRamp(_ palette: [Color]) -> some View {
        HStack(spacing: 2) {
            ForEach(palette.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(palette[index])
                    .frame(width: 7, height: 10)
                    .overlay { RoundedRectangle(cornerRadius: 2).stroke(.primary.opacity(0.3), lineWidth: 0.5) }
            }
        }.accessibilityHidden(true)
    }

    private func timelineAxisPicker(_ detail: PreparedDetail) -> some View {
        Picker("Timeline axis", selection: $axis) {
            Text(units == .metric ? "km" : "mi").tag(TimelineAxisMode.distance)
            Text("Time").tag(TimelineAxisMode.time)
        }.pickerStyle(.segmented).frame(width: 100)
            .disabled(detail.timeline?.distance == nil)
    }

    private func playbackButton(_ detail: PreparedDetail) -> some View {
        Button {
            if scrub >= Double(detail.input.stream.count - 1) { scrub = 0 }
            playing.toggle()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.title3).frame(width: 44, height: 44)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(.tint, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(playing ? "Pause" : "Play")
    }

    private var playbackSpeedPicker: some View {
        Menu {
            Picker("Playback speed", selection: $playbackSpeed) {
                ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { speed in
                    Text("\(speed, specifier: "%g")×").tag(speed)
                }
            }
        } label: {
            Text("\(playbackSpeed, specifier: "%g")×")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 48, minHeight: 44)
                .background(Color(uiColor: .quaternarySystemFill), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel("Playback speed")
    }

    private func playbackClock(_ detail: PreparedDetail) -> some View {
        let total = Double(max(0, detail.input.stream.count - 1))
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(clockTime(scrub)).fontWeight(.semibold)
            Text("/ \(clockTime(total))").foregroundStyle(.secondary)
        }
        .font(.subheadline.monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback time")
        .accessibilityValue("\(clockTime(scrub)) of \(clockTime(total))")
    }

    private func clockTime(_ seconds: Double) -> String {
        let duration = Duration.seconds(seconds.rounded(.down))
        return seconds >= 3600 ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }

    @ViewBuilder private func cameraButton(_ detail: PreparedDetail) -> some View {
        if !showsAnalysis, detail.line.value != nil {
            Button {
                options.cameraMode = options.cameraMode == .follow ? .overview : .follow
            } label: {
                Image(systemName: options.cameraMode == .follow ? "location.fill" : "location")
                    .frame(minWidth: 48, minHeight: 44)
                    .background(Color(uiColor: .quaternarySystemFill), in: Capsule())
            }.buttonStyle(.plain)
                .accessibilityLabel(options.cameraMode == .follow ? "Show whole route" : "Follow current position")
        }
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
            // The analysis stream is 1 Hz: 1× means recorded time, regardless
            // of activity length. Do not jump ahead after a main-thread stall.
            scrub = min(end, scrub + min(seconds, 0.1) * playbackSpeed)
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
        let started = ContinuousClock.now
        Self.performanceLog.info("detail_open started")
        error = nil
        prepared = nil
        presentation = nil
        playing = false
        summaryOnly = false
        golfRecording = nil
        do {
            guard let latest = try await library.activity(id), !latest.isHidden else {
                current = nil
                dismiss()
                return
            }
            current = latest
            if latest.primary.source == .healthKit, latest.sourceSportName == "Golf",
               let golf = try await library.golfHealthRecording(for: latest.primary) {
                let athlete = try await library.profile()
                try Task.checkCancellation()
                units = athlete.units
                golfRecording = golf
                summaryOnly = true
                return
            }
            async let stream = library.analysisStream(for: id)
            async let recorded = library.recordedActivity(for: id)
            async let profile = library.profile()
            async let storedMetrics = library.metrics(for: id)
            async let sourceOffers = library.alternativeSources(for: id)
            let native = try await recorded
            let athlete = try await profile
            units = athlete.units
            summaryOnly = native.stream.samples.isEmpty || !record.sport.hasFullSupport
            if summaryOnly {
                metrics = try await storedMetrics
                alternatives = try await sourceOffers
                return
            }
            let input = try await DetailInput(stream: stream, sport: record.sport,
                isIndoor: record.isIndoor, isVirtual: record.isVirtual,
                lapStarts: DetailInput.lapStarts(of: native.laps, streamStart: stream.start),
                recordedLaps: native.laps,
                profile: athlete, activityDate: record.start)
            Self.performanceLog.info("detail_data_ready elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
            let prepareStarted = ContinuousClock.now
            let result = try await DetailPreparationCache.shared.prepare(input)
            try Task.checkCancellation()
            prepared = result.detail
            overlay = result.detail.defaultOverlay
            timelineKind = result.detail.timelineKind(for: overlay)
                ?? (result.detail.timelineOverlays[.power] != nil ? .power : nil)
            units = input.profile.units
            updateTimelineOverlay()
            if result.detail.timeline?.distance == nil { axis = .time }
            Self.performanceLog.info("detail_map_ready elapsed=\(String(describing: started.duration(to: .now)), privacy: .public) preparation=\(String(describing: prepareStarted.duration(to: .now)), privacy: .public) cache_hit=\(result.cacheHit)")

            // Publish the map before preparing the analysis sheet or awaiting
            // ancillary data. The detached worker never occupies the UI actor.
            let analysisStarted = ContinuousClock.now
            let worker = Task.detached(priority: .utility) {
                DetailAnalysisPresentation.prepare(result.detail)
            }
            let analysis = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            presentation = analysis
            Self.performanceLog.info("detail_analysis_ready duration=\(String(describing: analysisStarted.duration(to: .now)), privacy: .public)")
            metrics = try await storedMetrics
            alternatives = try await sourceOffers
        } catch is CancellationError {
            return
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
        case .plain: "Single colour"
        }
    }
}

/// A hidden system bar must not remove the navigation stack's native edge pop.
/// Borrow its recognizer only while this detail is visible, then restore it.
private struct DetailBackGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var recognizer: UIGestureRecognizer?
        private weak var popNavigation: UINavigationController?
        private weak var previousDelegate: (any UIGestureRecognizerDelegate)?
        private var previousEnabled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // SwiftUI may finish hiding the bar after the child appears.
            DispatchQueue.main.async { [weak self] in self?.enableNativePop() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            enableNativePop()
        }

        private func enableNativePop() {
            guard view.window != nil else { return }
            func enclosingNavigation(_ controller: UIViewController) -> UINavigationController? {
                if let navigation = controller as? UINavigationController,
                   let top = navigation.topViewController, view.isDescendant(of: top.view) { return navigation }
                for child in controller.children {
                    if let navigation = enclosingNavigation(child) { return navigation }
                }
                return nil
            }
            guard let root = view.window?.rootViewController,
                  let navigation = navigationController ?? enclosingNavigation(root),
                  navigation.viewControllers.count > 1,
                  let gesture = navigation.interactivePopGestureRecognizer else { return }
            popNavigation = navigation
            if recognizer == nil {
                recognizer = gesture
                previousDelegate = gesture.delegate
                previousEnabled = gesture.isEnabled
            }
            gesture.delegate = self
            if !gesture.isEnabled { gesture.isEnabled = true }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController = popNavigation else { return false }
            return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // MapKit's pan must yield at the screen edge. Away from the edge
            // the native recognizer fails immediately and the map stays free.
            true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }

        func restore() {
            if let recognizer, recognizer.delegate === self {
                recognizer.delegate = previousDelegate
                recognizer.isEnabled = previousEnabled
            }
            recognizer = nil
            popNavigation = nil
            previousDelegate = nil
        }
    }
}
