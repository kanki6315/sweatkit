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
                        NavigationLink("Activity info and sources") { ActivityManagementView(activity: record, library: library, deleteActivity: deleteActivity) }
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
        .task(id: record.id) {
            guard let library, let id = record.id else { return }
            do {
                let catalog = try await library.routes()
                try Task.checkCancellation()
                matchedRoute = catalog.membership(of: id)
            } catch { matchedRoute = nil }
        }
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
                        .safeAreaInset(edge: .bottom) {
                            if expandsAnalysisTimeline {
                                VStack(spacing: 0) {
                                    Button("Compact timeline", systemImage: "chevron.down") { expandsAnalysisTimeline = false }.font(.caption)
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
            }
        }
        .task(id: "\(showsAnalysis)-\(historyWindow)") {
            guard showsAnalysis, record.sport.family == .cycling, let library else { return }
            historicalCurve = []
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
                    }.flatMap(\.curve)
                    let groups = Dictionary(grouping: eligible, by: \.duration)
                    return groups.keys.sorted().compactMap { duration in
                        groups[duration]?.filter { $0.power.value != nil }.max { ($0.power.value ?? -.infinity) < ($1.power.value ?? -.infinity) }
                    }
                }.value
                try Task.checkCancellation()
                historicalCurve = points
                historicalCurveLoading = false
                historicalCurveError = nil
            } catch is CancellationError { }
            catch { historicalCurve = []; historicalCurveLoading = false; historicalCurveError = "Historical comparison couldn’t load." }
        }
        .task(id: selection) {
            guard let selection, let prepared else { selectionStats = nil; return }
            let result = await Task.detached(priority: .userInitiated) { prepared.rangeStats(selection) }.value
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
            }
        }
        .safeAreaInset(edge: .top) {
            if !showsAnalysis {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }.accessibilityLabel("Back")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(.headline).lineLimit(2)
                            Text("\(record.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(SourceAttributionView.names(record.members.map(\.source)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Menu {
                            Button("Analysis") { showsAnalysis = true }
                            if let library {
                                NavigationLink("Activity info and sources") {
                                    ActivityManagementView(activity: record, library: library, deleteActivity: deleteActivity)
                                }
                            }
                            Picker("Overlay", selection: $overlay) {
                                ForEach(RouteOverlay.allCases, id: \.self) { item in
                                    Text(item.label).tag(item).disabled(detail.bands[item]?.value == nil)
                                }
                            }
                            Picker("Timeline series", selection: $timelineKind) {
                                Text("None").tag(nil as TimelineOverlay.Kind?)
                                ForEach(TimelineOverlay.Kind.allCases, id: \.self) { kind in
                                    if detail.timelineOverlays[kind] != nil {
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
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("Activity options")
                    }.padding(.horizontal, 8).padding(.top, 8)
                    StatsPanel(stats: detail.cursorStats(at: Int(scrub)), sport: record.sport, units: units, floating: false)
                        .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 240 : nil)
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

    private func analysis(_ presentation: DetailAnalysisPresentation, _ detail: PreparedDetail) -> some View {
        ActivityAnalysisView(presentation: presentation, detail: detail, metrics: metrics, units: units,
                             scrub: manualScrub, selection: $selection, historicalCurve: historicalCurve, historicalCurveError: historicalCurveError, historicalCurveLoading: historicalCurveLoading, historyWindow: $historyWindow)
    }

    @ViewBuilder private func timeline(_ detail: PreparedDetail) -> some View {
        VStack(spacing: 4) {
            if !showsAnalysis {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                        if value.translation.height < -20 { showsAnalysis = true }
                    })
                    .accessibilityHidden(true)
            }
            HStack {
                Picker("Timeline series", selection: $timelineKind) {
                    Text("Elevation").tag(nil as TimelineOverlay.Kind?)
                    ForEach(TimelineOverlay.Kind.allCases, id: \.self) { kind in
                        if detail.timelineOverlays[kind] != nil {
                            Text(kind.rawValue.capitalized).tag(Optional(kind))
                        }
                    }
                }.pickerStyle(.menu)
                Spacer()
                Picker("Timeline axis", selection: $axis) {
                    Text(units == .metric ? "km" : "mi").tag(TimelineAxisMode.distance)
                    Text("Time").tag(TimelineAxisMode.time)
                }.pickerStyle(.segmented).frame(width: 130)
                    .disabled(detail.timeline?.distance == nil)
            }.padding(.horizontal, 14)
            if detail.line.value != nil {
                HStack(spacing: 4) {
                    Text("Route: \(overlay.label)")
                    ForEach(colors.indices, id: \.self) { index in
                        Capsule().fill(colors[index]).frame(width: 12, height: 6)
                            .overlay { Capsule().stroke(.primary.opacity(0.5), lineWidth: 0.5) }
                    }
                    Spacer()
                }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
            }
            if let data = detail.timeline {
                ActivityTimeline(data: data, overlay: timelineOverlay, scrubSample: manualScrub,
                    selection: $selection, selectionStats: selectionStats, axisMode: axis,
                    collapsesStops: collapsesStops, sport: record.sport, units: units, floating: false)
            }
            HStack {
                Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
                    if scrub >= Double(detail.input.stream.count - 1) { scrub = 0 }
                    playing.toggle()
                }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                Picker("Playback speed", selection: $playbackSpeed) {
                    ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { speed in Text("\(speed, specifier: "%g")×").tag(speed) }
                }.pickerStyle(.menu)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Duration.seconds(scrub.rounded(.down)).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.subheadline.monospacedDigit())
                    Text("of \(Duration.seconds(Double(max(0, detail.input.stream.count - 1))).formatted(.time(pattern: .hourMinuteSecond)))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }.frame(minWidth: 88, alignment: .trailing)
                if !showsAnalysis {
                    Button { showsAnalysis = true } label: {
                        if dynamicTypeSize.isAccessibilitySize { Image(systemName: "chart.xyaxis.line") }
                        else { Label("Analysis", systemImage: "chevron.up") }
                    }.accessibilityLabel("Analysis")
                        .font(.subheadline).frame(minWidth: 44, minHeight: 44)
                }
            }.padding(.horizontal, 14)
            if detail.line.value == nil && !showsAnalysis {
                Text(record.isVirtual ? "Virtual activity · no map" : record.isIndoor ? "Indoor activity · no map" : "No usable route · recorded charts")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
        .modifier(FloatingPanel(enabled: !showsAnalysis))
        .background(showsAnalysis ? Color(uiColor: .systemBackground) : .clear)
        .padding(.horizontal, showsAnalysis ? 0 : 12)
        .padding(.bottom, showsAnalysis ? 0 : 8)
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
            guard let latest = try await library.activity(id), !latest.isHidden else {
                current = nil
                dismiss()
                return
            }
            current = latest
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
