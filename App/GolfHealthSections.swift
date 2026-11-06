import SwiftUI
import Charts
import MapKit
import SweatKitLibrary
import SweatKitModel

/// Extends the existing summary with the primary Health original's actual data.
struct GolfHealthSections: View {
    let recording: GolfHealthRecording
    let units: SweatKitModel.UnitSystem

    var body: some View {
        Section("Golf · Recorded summary") {
            SourceAttributionView(sources: [.healthKit])
            LabeledContent("Recorded by", value: recording.sourceName)
            if let start = recording.stated.start {
                LabeledContent("Started", value: start.formatted(date: .abbreviated, time: .shortened))
            }
            if let end = recording.stated.end {
                LabeledContent("Ended", value: end.formatted(date: .abbreviated, time: .shortened))
            }
            if let start = recording.stated.start, let end = recording.stated.end, end >= start {
                LabeledContent("Elapsed time", value: duration(end.timeIntervalSince(start)))
            }
            if let timer = recording.stated.timerTime, timer.isFinite, timer >= 0 {
                LabeledContent("Recorded workout time", value: duration(timer))
            }
            if let distance = recording.stated.distance, distance.isFinite, distance >= 0 {
                LabeledContent("Recorded distance", value: String(format: "%.2f %@",
                    distance / (units == .metric ? 1000 : 1609.344), units == .metric ? "km" : "mi"))
            } else {
                LabeledContent("Recorded distance", value: "Unavailable")
            }
        }
        Section {
            if recording.positions.isEmpty {
                Text("No route locations in this Health recording.").foregroundStyle(.secondary)
            } else {
                NavigationLink { locationsMap } label: {
                    Label("View recorded locations", systemImage: "map")
                }
                LabeledContent("Locations", value: recording.positions.count.formatted())
            }
        } header: { Text("Route") } footer: {
            Text("Locations describe the recorder’s path. They do not identify shots or holes.")
        }
        if recording.channels.isEmpty {
            Section {
                Text("No measurement samples in this Health recording.").foregroundStyle(.secondary)
            } header: { Text("Recorded samples") } footer: {
                Text("Only data in the selected Health recording is shown. Missing values are not estimated.")
            }
        } else {
            ForEach(recording.channels.indices, id: \.self) { index in
                let channel = recording.channels[index]
                Section {
                    Chart(Array(channel.readings.enumerated()), id: \.offset) { _, reading in
                        PointMark(x: .value("Time", reading.timestamp), y: .value(channel.unit, reading.value))
                            .foregroundStyle(Color.primary)
                            .symbolSize(12)
                            .accessibilityLabel(reading.timestamp.formatted(date: .omitted, time: .standard))
                            .accessibilityValue("\(reading.value.formatted()) \(channel.unit)")
                    }
                    .chartXScale(domain: timeRange(for: channel))
                    .chartYAxisLabel(channel.unit)
                    .frame(height: 160)
                    LabeledContent("Recorded samples", value: channel.readings.count.formatted())
                } header: { Text(channel.name) } footer: {
                    Text("Each point is a recorded sample. Gaps are not filled.")
                }
            }
        }
        if !recording.laps.isEmpty || !recording.segments.isEmpty {
            Section {
                intervals(recording.laps, label: "Lap")
                intervals(recording.segments, label: "Segment")
            } header: { Text("Recorded intervals") } footer: {
                Text("Intervals come from the recording app; they are not identified as golf holes.")
            }
        }
    }

    private var locationsMap: some View {
        Map {
            ForEach(recording.positions.indices, id: \.self) { index in
                let point = recording.positions[index]
                MapCircle(center: CLLocationCoordinate2D(latitude: point.coordinate.latitude,
                                                       longitude: point.coordinate.longitude), radius: 3)
                    .foregroundStyle(.primary)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .safeAreaInset(edge: .bottom) {
            Text("\(recording.positions.count.formatted()) recorded locations · no points added")
                .font(.footnote).padding().frame(maxWidth: .infinity)
                .background(.regularMaterial)
        }
        .navigationTitle("Recorded locations")
        .navigationBarTitleDisplayMode(.inline)

    }

    private func timeRange(for channel: GolfHealthRecording.Channel) -> ClosedRange<Date> {
        // Include empty time at the beginning/end of a workout, rather than
        // stretching sparse samples to imply whole-round coverage.
        let first = channel.readings.first!.timestamp
        let last = channel.readings.last!.timestamp
        let start = min(recording.stated.start ?? first, first)
        let end = max(recording.stated.end ?? last, last)
        return start...max(end, start.addingTimeInterval(1))
    }

    private func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    @ViewBuilder private func intervals(_ values: [RecordedLap], label: String) -> some View {
        ForEach(values.indices, id: \.self) { index in
            let interval = values[index]
            LabeledContent("\(label) \(index + 1)", value: "\(interval.start.formatted(date: .omitted, time: .standard)) – \(interval.end.formatted(date: .omitted, time: .standard))")
        }
    }
}
