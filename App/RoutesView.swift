import SwiftUI
import Charts
import MapKit
import SweatKitModel
import SweatKitLibrary
import SweatKitRouteMatching
import SweatKitPalette

@MainActor @Observable final class RoutesModel {
    var catalog = RouteCatalog(routes: [], reviews: [])
    var units = UnitSystem.metric
    var loading = false
    var error: String?
    var library: ActivityLibrary?
    var didDecide: (@MainActor () async -> Void)?
    var includeOlderHistory = false
    private var generation = 0
    func reload(_ library: ActivityLibrary?) async {
        guard let library else { return }
        generation += 1
        let request = generation
        self.library = library
        loading = true
        defer { if request == generation { loading = false } }
        do {
            let result = try await library.routes(includeOlderHistory: includeOlderHistory)
            let resolvedUnits = try await library.profile().units
            guard request == generation else { return }
            units = resolvedUnits
            catalog = result; error = nil
        }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func decide(_ id: SourceIdentity, _ value: RouteDecision.Value) async {
        guard let library else { return }
        do { try await library.decideRoute(id, value: value, includeOlderHistory: includeOlderHistory); await didDecide?(); await reload(library) }
        catch { self.error = error.localizedDescription }
    }
}

struct RoutesView: View {
    let libraryModel: LibraryModel
    @State private var model = RoutesModel()
    @State private var search = ""
    @State private var byName = false
    @AppStorage("routes.includeOlderHistory") private var includeOlderHistory = false
    private var routes: [LibraryRoute] {
        let filtered = model.catalog.routes.filter { search.isEmpty || ($0.name.localizedCaseInsensitiveContains(search) || $0.region.localizedCaseInsensitiveContains(search)) }
        return byName ? filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : filtered
    }
    private var historyPicker: some View {
        Picker("History", selection: $includeOlderHistory) {
            Text("Past two years").tag(false)
            Text("All history").tag(true)
        }
    }
    private var regions: [String] { Array(Set(routes.map(\.region))).sorted() }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.catalog.routes.count) \(model.catalog.routes.count == 1 ? "route" : "routes") · \(model.catalog.routes.reduce(0) { $0 + $1.efforts.count }) efforts · by \(byName ? "name" : "most recent")")
                        .font(.subheadline).foregroundStyle(Color.secondary)
                    Text(includeOlderHistory ? "All history" : "Past two years")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.loading && !model.catalog.routes.isEmpty { ProgressView("Updating routes…") }
                    Text("Routes with five or more outings. Possible matches are optional to review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if let error = model.error {
                Section("Routes couldn’t refresh") {
                    Text(error)
                    Button("Try again") { Task { await model.reload(libraryModel.library) } }
                }
            }
            if !model.loading && model.catalog.routes.isEmpty && model.error == nil {
                ContentUnavailableView("No frequent routes yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Routes appear after five confirmed outings in the selected history. Try All history to include older activities."))
            } else if !search.isEmpty && routes.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            ForEach(regions, id: \.self) { region in
              Section(region) {
                ForEach(routes.filter { $0.region == region }) { route in
                    NavigationLink {
                        RoutePageView(routeID: route.id, model: model)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RouteGeographicThumbnail(line: route.reference.line).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12)).allowsHitTesting(false).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.name).font(.headline)
                                Text(routeMetadata(route, units: model.units)).font(.caption).foregroundStyle(Color.secondary)
                                Text("\(route.efforts.count) efforts · best \(routeTime(route.best))").font(.caption).monospacedDigit()
                                SourceAttributionView(sources: route.efforts.map { $0.activity.primary.source })
                                RouteDotChart(route: route, metric: .time, compact: true).frame(height: 20)
                            }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("route-row")
                }
                let regionalReviews = model.catalog.reviews.filter { review in
                    routes.contains { $0.id == review.routeID && $0.region == region }
                }
                if !regionalReviews.isEmpty {
                    DisclosureGroup("Optional review · \(Set(regionalReviews.map { $0.activity.id }).count)") {
                        ForEach(routes.filter { $0.region == region }) { route in
                            let pending = regionalReviews.filter { $0.routeID == route.id }
                            if !pending.isEmpty {
                                DisclosureGroup("\(route.name) · \(pending.count) possible match\(pending.count == 1 ? "" : "es")") {
                                    ForEach(pending) { review in
                                        NavigationLink {
                                            RouteReviewPage(review: review, route: route, model: model)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(review.activity.start, format: .dateTime.month().day().year().hour().minute())
                                                Text(review.explanation).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
              }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Routes")
        .toolbarTitleDisplayMode(.inlineLarge)
        .overlay {
            if model.loading && model.catalog.routes.isEmpty { ProgressView("Finding repeated routes…") }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Find a route")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu("Route options", systemImage: "line.3.horizontal.decrease") {
                historyPicker
                Picker("Sort routes", selection: $byName) {
                    Text("Most recent").tag(false)
                    Text("Name").tag(true)
                }
            }
        } }
        .onChange(of: includeOlderHistory) {
            model.includeOlderHistory = includeOlderHistory
            Task { await model.reload(libraryModel.library) }
        }
        .refreshable { await model.reload(libraryModel.library) }
        .task(id: libraryModel.trendsRevision) {
            model.includeOlderHistory = includeOlderHistory
            model.didDecide = { await libraryModel.reload() }
            await model.reload(libraryModel.library)
        }
    }
}

private struct RouteReviewPage: View {
    let review: RouteReview
    let route: LibraryRoute
    let model: RoutesModel
    @Environment(\.dismiss) private var dismiss
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var mapError: String?
    @State private var saving = false
    var body: some View {
        List {
            Section {
                Map {
                    MapPolyline(coordinates: route.reference.line.points.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }).stroke(.primary, lineWidth: 5)
                    MapPolyline(coordinates: coordinates).stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                }.frame(height: 300).listRowInsets(EdgeInsets())
                Text("Solid: usual route · Orange dashed: possible outing").font(.caption)
                if let mapError { Text(mapError).foregroundStyle(.secondary) }
                Text(review.activity.start, format: .dateTime.month().day().year().hour().minute())
                Text(review.explanation)
            }
            Section {
                Button("Include in this route") { decide(true) }.disabled(saving || coordinates.isEmpty)
                Button("Keep separate") { decide(false) }.disabled(saving)
                Text("You can leave this undecided. It won’t change your confirmed routes.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.error { Text(error).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                guard let library = model.library else { return }
                let stream = try await library.analysisStream(for: review.activity.id!)
                coordinates = (0..<stream.count).compactMap { stream.coordinate(at: $0) }.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                if coordinates.isEmpty { mapError = "This outing’s GPS track is unavailable." }
            } catch { mapError = "The outing’s track couldn’t load. Reopen this review to try again." }
        }
    }
    private func decide(_ included: Bool) {
        saving = true
        Task {
            await model.decide(review.routeID, .membership(activity: review.activity.id!, included: included))
            saving = false
            if model.error == nil { dismiss() }
        }
    }
}

func routeTime(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite else { return "Unavailable" }
    let value = Int(abs(seconds).rounded())
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}

struct RouteMap: View {
    let line: ReferenceLine
    var frame: GhostFrame?
    var satellite = false
    var follow = false
    var coloredRuns: [RouteColoredRun] = []
    @State private var camera = MapCameraPosition.automatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Map(position: $camera) {
            if coloredRuns.isEmpty {
                MapPolyline(coordinates: line.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.black.opacity(0.55), lineWidth: 7)
                MapPolyline(coordinates: line.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.white, lineWidth: 3)
            } else {
                ForEach(coloredRuns) { run in
                    MapPolyline(coordinates: run.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.black.opacity(0.55), lineWidth: 7)
                    MapPolyline(coordinates: run.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke((run.hex.map { RampColor(hex: $0).color } ?? .white).opacity(run.startDistance > (frame?.subjectRouteDistance ?? .infinity) ? 0.45 : 1), lineWidth: 3)
                }
            }
            if let frame {
                Annotation("Subject", coordinate: coordinate(frame.subjectRouteDistance)) { marker(filled: true) }
                Annotation("Baseline", coordinate: coordinate(frame.baselineRouteDistance)) { marker(filled: false) }
            }
        }
        .safeAreaInset(edge: .bottom) { if satellite { Color.clear.frame(height: 24) } }
        .mapStyle(satellite ? .imagery(elevation: .realistic) : .standard(elevation: .flat))
        .onChange(of: frame) { updateCamera() }
        .onChange(of: follow) { updateCamera() }
        .onChange(of: reduceMotion) { updateCamera() }
        .accessibilityLabel(frame == nil ? "Route map" : "Subject and baseline on the shared clock")
    }
    private func updateCamera() {
        guard follow, !reduceMotion, let frame else { camera = .automatic; return }
        let here = coordinate(frame.subjectRouteDistance)
        let ahead = coordinate(frame.subjectRouteDistance + 200)
        let heading = atan2((ahead.longitude - here.longitude) * cos(here.latitude * .pi / 180), ahead.latitude - here.latitude) * 180 / .pi
        camera = .camera(MapCamera(centerCoordinate: here, distance: 1800, heading: heading, pitch: 55))
    }
    private func coordinate(_ distance: Double) -> CLLocationCoordinate2D {
        let point = line.coordinate(atRouteDistance: distance)
        return .init(latitude: point.latitude, longitude: point.longitude)
    }
    private func marker(filled: Bool) -> some View {
        Circle().fill(filled ? Color.white : Color.black).frame(width: 20, height: 20)
            .overlay(Circle().stroke(.white, lineWidth: 3)).padding(3).background(.black, in: Circle())
    }
}

enum RouteChartMetric: String, CaseIterable {
    case time = "Moving time", power = "Power", heartRate = "Heart rate", efficiency = "Efficiency"
    func value(_ effort: RouteEffort) -> Double? {
        switch self {
        case .time: effort.movingTime
        case .power: effort.metrics?.power.average.value
        case .heartRate: effort.metrics?.heartRate.average.value
        case .efficiency: effort.activity.sport.family == .cycling ? effort.metrics?.cyclingEfficiency.value : effort.metrics?.onFootEfficiency.value
        }
    }
}
struct RouteDotChart: View {
    let route: LibraryRoute
    let metric: RouteChartMetric
    var compact = false
    var body: some View {
        Chart {
            ForEach(route.efforts) { effort in
                if let value = metric.value(effort) {
                    PointMark(x: .value("Date", effort.activity.start), y: .value(metric.rawValue, metric == .time ? -value : value))
                        .foregroundStyle(effort.id == route.ranked.first?.id ? Color.primary : Color.secondary)
                        .symbolSize(compact ? 12 : 60)
                        .accessibilityLabel(Text(effort.activity.start.formatted(date: .abbreviated, time: .omitted)))
                        .accessibilityValue(Text(metric == .time ? routeTime(value) : String(format: "%.1f", value)))
                        .annotation(position: .top) {
                            if !compact {
                                let best = effort.id == route.ranked.first?.id
                                let latest = effort.id == route.efforts.max(by: { $0.activity.start < $1.activity.start })?.id
                                if best || latest { Text(best && latest ? "Best · Latest" : best ? "Best" : "Latest").font(.caption2).foregroundStyle(Color.primary) }
                            }
                        }
                }
            }
            if !compact, metric == .time, let median = route.median {
                RuleMark(y: .value("Median", -median)).lineStyle(StrokeStyle(dash: [4])).foregroundStyle(Color.secondary).annotation(position: .top, alignment: .leading) { Text("Median").font(.caption2) }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis {
            if !compact {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric == .time ? routeTime(abs(number)) : String(format: "%.1f", number))
                        }
                    }
                }
            }
        }
        .accessibilityLabel("\(metric.rawValue) by effort date")
    }
}

struct RoutePageView: View {
    let routeID: SourceIdentity
    @Bindable var model: RoutesModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var statWidth = 78.0
    @State private var metric = RouteChartMetric.time
    @State private var byTime = true
    @State private var editing = false
    @State private var name = ""
    var route: LibraryRoute? { model.catalog.routes.first { $0.id == routeID } }
    var body: some View {
        Group {
            if let route {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        RouteMap(line: route.reference.line, satellite: true).frame(height: 320)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(route.name).font(.title.bold())
                            Text(routeMetadata(route, units: model.units)).font(.subheadline).foregroundStyle(Color.secondary)
                            SourceAttributionView(sources: route.efforts.flatMap { $0.activity.members.map(\.source) })
                            if let first = route.efforts.min(by: { $0.activity.start < $1.activity.start }) {
                                Text("\(first.activity.isVirtual ? "Virtual ride" : first.activity.sport.rawValue.capitalized) · first recorded \(first.activity.start.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(Color.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: statWidth))], alignment: .leading, spacing: 16) {
                                stat("Efforts", String(route.efforts.count))
                                stat("Best", routeTime(route.best))
                                stat("Latest", routeTime(route.efforts.max(by: { $0.activity.start < $1.activity.start })?.movingTime))
                                stat("Median", routeTime(route.median))
                            }
                            Group {
                                if typeSize.isAccessibilitySize { metricPicker.pickerStyle(.menu) }
                                else { metricPicker.pickerStyle(.segmented) }
                            }
                            if route.efforts.contains(where: { metric.value($0) != nil }) {
                                RouteDotChart(route: route, metric: metric).frame(height: 160).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                            } else { Text("\(metric.rawValue) is unavailable for these efforts.").foregroundStyle(Color.secondary) }
                            HStack {
                                Text("Efforts").font(.title2.bold()); Spacer()
                                Button(byTime ? "By time" : "By date", systemImage: "arrow.up.arrow.down") { byTime.toggle() }
                            }
                            ForEach(sorted(route)) { effort in
                                VStack(alignment: .leading, spacing: 8) {
                                    NavigationLink {
                                        RouteComparisonView(route: route, subject: effort, library: model.library, units: model.units)
                                    } label: {
                                        HStack {
                                            Text(route.rank(of: effort.id).map(String.init) ?? "—").foregroundStyle(Color.secondary)
                                            VStack(alignment: .leading) {
                                                Text(routeTime(effort.movingTime ?? effort.elapsedTime)).font(.title3).monospacedDigit()
                                                HStack {
                                                    Text(effort.activity.start, style: .date)
                                                    SourceAttributionView(sources: effort.activity.members.map(\.source))
                                                }.font(.caption).foregroundStyle(Color.secondary)
                                                Text("\(effort.metrics?.power.average.value.map { String(format: "%.0f W", $0) } ?? "Power unavailable") · \(effort.metrics?.heartRate.average.value.map { String(format: "%.0f bpm", $0) } ?? "Heart rate unavailable")").font(.caption).foregroundStyle(Color.secondary)
                                                if effort.movingTime == nil { Text("Elapsed only · pause positions unknown").font(.caption) }
                                            }
                                            Spacer(); Image(systemName: "chevron.right")
                                        }.foregroundStyle(Color.primary).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("route-effort")
                                    Menu("Edit effort", systemImage: "ellipsis") {
                                        Button("Use as reference") { Task { await model.decide(route.id, .reference(effort.id)) } }
                                        Button("Remove from route", role: .destructive) { Task { await model.decide(route.id, .membership(activity: effort.id, included: false)) } }
                                    }
                                }.padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                            }
                        }.padding(20)
                            .background(Color(uiColor: .systemGroupedBackground), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                            .padding(.top, -24)
                    }.padding(.bottom)
                }.background(Color(uiColor: .systemGroupedBackground)).ignoresSafeArea(edges: .top)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar { Menu("Edit route", systemImage: "ellipsis") {
                    Button("Rename") { name = route.name; editing = true }
                    Menu("Merge route") {
                        ForEach(model.catalog.routes.filter { $0.id != route.id }) { other in
                            Button(other.name) { Task { await model.decide(route.id, .merge(other.id)) } }
                        }
                    }
                } }
            } else { ContentUnavailableView("Route no longer available", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("At least five visible outings in the selected history are needed.")) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename route", isPresented: $editing) {
            TextField("Route name", text: $name)
            Button("Save") { Task { await model.decide(routeID, .name(name.trimmingCharacters(in: .whitespacesAndNewlines))) } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Route couldn’t update", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var metricPicker: some View {
        Picker("Chart", selection: $metric) { ForEach(RouteChartMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(value).font(.title2.bold()).monospacedDigit(); Text(title).font(.caption).foregroundStyle(Color.secondary) }
    }
    private func sorted(_ route: LibraryRoute) -> [RouteEffort] {
        byTime ? route.efforts.sorted { ($0.movingTime ?? .infinity) < ($1.movingTime ?? .infinity) } : route.efforts.sorted { $0.activity.start > $1.activity.start }
    }
}

func routeDistance(_ metres: Double, units: UnitSystem) -> String {
    String(format: "%.1f %@", metres / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi")
}

/// An offline route outline. Fit the full geometry instead of cropping a live map into a tiny square.
private struct RouteThumbnail: View {
    let line: ReferenceLine
    var body: some View {
        Canvas { context, size in
            let latitude = line.points.map(\.latitude)
            let longitude = line.points.map(\.longitude)
            guard let minLat = latitude.min(), let maxLat = latitude.max(),
                  let minLon = longitude.min(), let maxLon = longitude.max() else { return }
            let correction = cos((minLat + maxLat) / 2 * .pi / 180)
            let width = max((maxLon - minLon) * correction, 0.000001)
            let height = max(maxLat - minLat, 0.000001)
            let scale = min((size.width - 16) / width, (size.height - 16) / height)
            var path = Path()
            for (index, point) in line.points.enumerated() {
                let p = CGPoint(x: (size.width - width * scale) / 2 + (point.longitude - minLon) * correction * scale,
                                y: (size.height - height * scale) / 2 + (maxLat - point.latitude) * scale)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(.secondary), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }.background(Color(uiColor: .tertiarySystemGroupedBackground))
    }
}

private func routeMetadata(_ route: LibraryRoute, units: UnitSystem) -> String {
    let effort = route.efforts.first { $0.id == route.referenceID } ?? route.efforts.first
    let sport = effort.map { $0.activity.isVirtual ? "Virtual ride" : $0.activity.sport.rawValue.capitalized } ?? "Route"
    let ascent = effort?.activity.ascent.map { String(format: "%.0f %@", $0 * (units == .metric ? 1 : 3.28084), units == .metric ? "m" : "ft") }
    return ([sport, routeDistance(route.reference.line.length, units: units)] + (ascent.map { [$0] } ?? [])).joined(separator: " · ")
}

/// Map imagery is optional. Geometry is immediately available offline and remains if imagery fails.
private struct RouteGeographicThumbnail: View {
    let line: ReferenceLine
    @Environment(\.colorScheme) private var scheme
    @State private var snapshot: UIImage?
    var body: some View {
        Group {
            if let snapshot { Image(uiImage: snapshot).resizable().scaledToFit() }
            else { RouteThumbnail(line: line) }
        }.task(id: "\(line.hashValue)-\(scheme)") {
            snapshot = nil
            let coordinates = line.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            let bounds = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
            let side = max(bounds.width, bounds.height) * 1.3
            let options = MKMapSnapshotter.Options()
            options.mapRect = MKMapRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            options.size = CGSize(width: 150, height: 150)
            options.traitCollection = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            options.pointOfInterestFilter = .excludingAll
            do {
                let result = try await MKMapSnapshotter(options: options).start()
                try Task.checkCancellation()
                snapshot = UIGraphicsImageRenderer(size: options.size).image { context in
                    result.image.draw(at: .zero)
                    let path = UIBezierPath()
                    for (index, coordinate) in coordinates.enumerated() {
                        let point = result.point(for: coordinate)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.lineJoinStyle = .round; path.lineCapStyle = .round
                    UIColor.black.withAlphaComponent(0.55).setStroke(); path.lineWidth = 7; path.stroke()
                    UIColor.white.setStroke(); path.lineWidth = 3; path.stroke()
                }
            } catch { /* Keep the local outline. Map tiles are not library data. */ }
        }
    }
}
