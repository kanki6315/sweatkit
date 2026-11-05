import SweatKitFlyover
import SwiftUI

struct HarnessView: View {
    @State private var model = HarnessModel()
    @State private var showsControls = true

    var body: some View {
        ZStack {
            if let built = model.built {
                FlyoverMap(route: built.route, bandColors: built.colors, scrubSample: $model.scrub, options: model.options)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                if model.isLoading { ProgressView("Decoding").tint(.white).foregroundStyle(.white) }
            }
            VStack(spacing: 8) {
                readout
                Spacer()
                controls
            }
            .padding(.horizontal, 12)
        }
        .task(id: model.choice) { await model.load() }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = model.loadError {
                Text(error).foregroundStyle(.red)
            }
            if let built = model.built, let track = model.track {
                Text("\(built.route.vertices.count) drawn / \(track.points.count) with GPS / \(track.recordCount) records · \(built.runCount) band runs")
            }
            let monitor = model.monitor
            Text(String(format: "now %.0f fps", monitor.currentFPS)
                + (monitor.worstFPS.map { String(format: " · worst %.0f fps", $0) } ?? "")
                + (monitor.longestFrame.map { String(format: " · longest %.1f ms", $0) } ?? "")
                + " · hitches \(monitor.hitches)"
                + (monitor.isMeasuring ? " · measuring" : ""))
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
        .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Slider(value: $model.scrub, in: model.sampleRange) { editing in
                    if editing { model.monitor.beginMeasuring() } else { model.monitor.endMeasuring() }
                }
                Button(model.isSweeping ? "Stop" : "Sweep") { model.toggleSweep() }
                    .buttonStyle(.bordered)
                Button(showsControls ? "Hide" : "More") { showsControls.toggle() }
                    .buttonStyle(.bordered)
            }
            if showsControls {
                Picker("Route", selection: $model.choice) {
                    ForEach(RouteChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(String(format: "Tolerance %.1f m", model.tolerance)).frame(width: 130, alignment: .leading)
                    Slider(value: $model.tolerance, in: 0...30, step: 0.5) { editing in
                        if !editing { model.rebuild() }
                    }
                }
                Picker("Drawing", selection: $model.options.lineDrawing) {
                    Text("Gradient").tag(FlyoverOptions.LineDrawing.gradient)
                    Text("Band runs").tag(FlyoverOptions.LineDrawing.bandRuns)
                }
                .pickerStyle(.segmented)
                Picker("Gradient stops", selection: $model.options.gradientLocations) {
                    Text("Stops by vertex").tag(GradientStops.Parameter.vertexIndex)
                    Text("Stops by length").tag(GradientStops.Parameter.projectedLength)
                }
                .pickerStyle(.segmented)
                .disabled(model.options.lineDrawing != .gradient)
                Picker("Camera", selection: $model.options.cameraMode) {
                    Text("Overview").tag(FlyoverOptions.CameraMode.overview)
                    Text("Follow").tag(FlyoverOptions.CameraMode.follow)
                }
                .pickerStyle(.segmented)
                Picker("Sweep", selection: $model.sweepSeconds) {
                    Text("Sweep 60 s").tag(60.0)
                    Text("Sweep 15 s").tag(15.0)
                }
                .pickerStyle(.segmented)
                Grid(alignment: .leading, horizontalSpacing: 16) {
                    GridRow {
                        Toggle("3D elevation", isOn: $model.options.realisticElevation)
                        Toggle("Standard map", isOn: Binding(
                            get: { model.options.mapStyle == .standard },
                            set: { model.options.mapStyle = $0 ? .standard : .satellite }
                        ))
                    }
                    GridRow {
                        Toggle("Dim ahead", isOn: $model.options.dimsAhead)
                        Toggle("Above labels", isOn: Binding(
                            get: { model.options.lineLevel == .aboveLabels },
                            set: { model.options.lineLevel = $0 ? .aboveLabels : .aboveRoads }
                        ))
                    }
                }
                .toggleStyle(.switch)
                .font(.footnote)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding(.bottom, 4)
    }
}
