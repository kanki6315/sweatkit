import SwiftUI
import MapKit
import SweatKitLibrary
import SweatKitModel
import SweatKitRouteMatching

struct RouteHistoryPage: View {
    let routeID: SourceIdentity
    let model: RoutesModel
    private var route: LibraryRoute? {
        (model.catalog.routes + (model.catalog.developingRoutes ?? [])).first { $0.id == routeID }
    }
    var body: some View {
        Group {
            if let route {
                List {
                    Section {
                        RouteMap(line: route.reference.line).frame(height: 250).allowsHitTesting(false)
                            .listRowInsets(EdgeInsets())
                        Text("\(route.efforts.count) confirmed outings")
                            .font(.headline).monospacedDigit()
                        Text(route.efforts.count < 5
                             ? "This group appears as a frequent route after five confirmed outings. Select an outing to inspect its path and matching evidence."
                             : "This group now has enough outings to appear as a frequent route.")
                            .foregroundStyle(.secondary)
                    }
                    Section("Outings") {
                        ForEach(route.efforts.sorted { $0.activity.start > $1.activity.start }) { effort in
                            NavigationLink {
                                RouteOutingInspectionPage(effort: effort, groupID: route.id, model: model)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(effort.activity.start, format: .dateTime.month().day().year().hour().minute())
                                    Text(effort.activity.title).font(.subheadline)
                                    if let distance = effort.activity.distance {
                                        Text(routeDistance(distance, units: model.units)).monospacedDigit()
                                    }
                                    SourceAttributionView(sources: effort.activity.members.map(\.source))
                                    if effort.id == route.referenceID { Text("Reference outing").font(.caption).foregroundStyle(.secondary) }
                                }
                            }.accessibilityIdentifier("route-history-outing")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Group no longer available", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Its outings may have changed or moved outside the selected history."))
            }
        }
        .navigationTitle(route?.name ?? "Route history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RouteOutingInspectionPage: View {
    let effort: RouteEffort
    let groupID: SourceIdentity
    let model: RoutesModel
    @State private var comparisonID: SourceIdentity?
    @State private var inspection: RouteInspection?
    @State private var error: String?
    @State private var retry = 0
    private var choices: [LibraryRoute] { model.catalog.routes + (model.catalog.developingRoutes ?? []) }
    private var reference: LibraryRoute? { choices.first { $0.id == (comparisonID ?? groupID) } }
    private var requestKey: String { "\(comparisonID ?? groupID)-\(retry)-\(reference?.reference.line.hashValue.description ?? "")" }

    var body: some View {
        List {
            Section {
                Text(effort.activity.start, format: .dateTime.month().day().year().hour().minute())
                Text(effort.activity.title)
                Picker("Compare with", selection: Binding(get: { comparisonID ?? groupID }, set: { comparisonID = $0 })) {
                    ForEach(choices) { route in
                        Text("\(route.name) · \(route.efforts.map(\.activity.start).min()?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                            .tag(route.id)
                    }
                }.pickerStyle(.navigationLink)
            }
            if let reference {
                Section {
                    Map {
                        MapPolyline(coordinates: coordinates(reference.reference.line.points))
                            .stroke(.black.opacity(0.55), lineWidth: 7)
                        MapPolyline(coordinates: coordinates(reference.reference.line.points))
                            .stroke(.white, lineWidth: 4)
                        if let inspection {
                            MapPolyline(coordinates: coordinates(inspection.coordinates))
                                .stroke(.black, style: StrokeStyle(lineWidth: 5, dash: [7, 5]))
                            MapPolyline(coordinates: coordinates(inspection.coordinates))
                                .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                        }
                    }.id(requestKey).frame(height: 280).listRowInsets(EdgeInsets())
                    Text("Solid white: reference route · Blue dashed: selected outing")
                        .font(.caption)
                    Text("Pinch and drag the map to inspect differences.").font(.caption).foregroundStyle(.secondary)
                }
                if let inspection {
                    evidence(inspection)
                } else if let error {
                    Section("Track couldn’t load") {
                        Text(error)
                        Button("Try again") { retry += 1 }
                    }
                } else { ProgressView("Loading outing and matching evidence…") }
            } else {
                Text("This route is no longer in the selected history.")
            }
        }
        .navigationTitle("Inspect outing")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestKey) {
            inspection = nil; error = nil
            guard let reference, let library = model.library else { return }
            do {
                let result = try await library.inspectRoute(activity: effort.id, against: reference)
                try Task.checkCancellation()
                inspection = result
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = "The outing or its GPS track is unavailable. Refresh Routes or try again." } }
        }
    }

    @ViewBuilder private func evidence(_ result: RouteInspection) -> some View {
        Section("Matching evidence") {
            if let included = result.explicitMembership {
                Text(included ? "You explicitly included this outing in this route." : "You chose to keep this outing separate from this route.")
            }
            Text("These checks compare the selected outing with this reference. They do not change its group or resolve matches to other routes.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Sport family", value: result.detection.sameSportFamily ? "Same" : "Different")
            LabeledContent("Distance within 10%", value: result.detection.distanceWithinTolerance ? "Yes" : "No")
            LabeledContent("Starts within 200 m", value: result.detection.startWithinTolerance ? "Yes" : "No")
            LabeledContent("Finishes within 200 m", value: result.detection.finishWithinTolerance ? "Yes" : "No")
            LabeledContent("Exact grid overlap", value: percent(result.detection.sharedCellFraction))
            if result.shortlisted && !result.detection.isShortlisted {
                Text("Nearby grid cells allowed these tracks through the GPS-noise check. Alignment still decides whether the paths match.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let measures = result.measures {
                Text(measures.outcome() == .join ? "The pair passes the alignment checks." : measures.outcome() == .manualReview ? "The pair needs review before joining automatically." : "The pair fails the full-route alignment checks.")
                    .font(.headline)
                LabeledContent("Points within 30 m", value: percent(measures.proximity))
                LabeledContent("Start / end gaps", value: "\(metres(measures.startGap)) / \(metres(measures.endGap))")
                LabeledContent("Timed-section coverage", value: percent(measures.coverage))
                LabeledContent("Longest unmapped stretch", value: metres(measures.longestUnmappedStretch))
                LabeledContent("Timed-section length ratio", value: percent(measures.lengthRatio))
                LabeledContent("Worst 200 m side offset", value: metres(measures.worstSideOffset))
                Text("Automatic alignment requires at least 90% proximity and 95% coverage, no unmapped stretch over 50 m, end gaps within 25 m, and a length ratio within 3%. Sustained side offsets need review; small localized GPS drift has a separate allowance.")
                    .font(.caption).foregroundStyle(.secondary)
                let failed = measures.failedMeasures()
                if !failed.isEmpty {
                    Text("Checks not passed: \(failed.sorted { $0.rawValue < $1.rawValue }.map { measureName($0) }.joined(separator: ", ")).")
                }
            } else {
                Text("These tracks did not pass detection, so alignment was not attempted.").font(.headline)
            }
        }
    }
    private func coordinates(_ points: [Coordinate]) -> [CLLocationCoordinate2D] {
        points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }
    private func percent(_ value: Double) -> String { value.isFinite ? value.formatted(.percent.precision(.fractionLength(1))) : "Unavailable" }
    private func metres(_ value: Double) -> String { value.isFinite ? String(format: "%.1f m", value) : "Unavailable" }
    private func measureName(_ measure: AlignmentMeasure) -> String {
        switch measure {
        case .proximity: "path proximity"
        case .ends: "route ends"
        case .coverage: "coverage"
        case .lengthRatio: "length ratio"
        case .sideOffset: "side offset"
        }
    }
}
