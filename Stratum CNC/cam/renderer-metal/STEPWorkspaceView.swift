import SwiftUI

struct STEPWorkspaceView: View {
    @ObservedObject var workspace: STEPWorkspace
    let onImport: () -> Void
    let onReload: (UUID) -> Void
    let onRemove: (UUID) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("STEP wireframe").font(.headline)
                Picker("Source", selection: $workspace.activeID) {
                    ForEach(workspace.sources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .frame(maxWidth: 300)
                Spacer()
                Button("Import…", action: onImport)
                Button("2D canvas") { workspace.isPresented = false }
                Button {
                    SettingsTab.canvas.select()
                    openSettings()
                } label: { Image(systemName: "computermouse") }
                .help("Mouse controls")
            }
            .padding(12)
            Divider()
            if let id = workspace.activeID {
                if workspace.loadingIDs.contains(id) {
                    VStack(spacing: 12) {
                        ProgressView("Reading STEP geometry…")
                        Button("Cancel") { workspace.cancel(id) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let scene = workspace.documents[id] {
                    STEPDocumentView(scene: scene, onReload: { onReload(id) }, onRemove: { onRemove(id) })
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text(workspace.errors[id] ?? "No geometry loaded")
                            .multilineTextAlignment(.center).textSelection(.enabled)
                        HStack {
                            Button("Retry") { onReload(id) }
                            Button("Remove source") { onRemove(id) }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("No STEP source", systemImage: "cube.transparent")
            }
        }
    }
}

private struct STEPDocumentView: View {
    @ObservedObject var scene: STEPDocumentScene
    let onReload: () -> Void
    let onRemove: () -> Void
    @StateObject private var zoom = CanvasZoomModel()

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(CanvasLayer.model.label, isOn: $scene.isModelVisible)
                    ForEach(scene.content.geometry.bodies, id: \.id) { body in
                        Toggle("Body #\(body.id.entityID) · \(body.edges.count) edges", isOn: Binding(
                            get: { !scene.hiddenBodies.contains(body.id) },
                            set: { scene.setBodyVisible(body.id, $0) }
                        ))
                        .disabled(!scene.isModelVisible)
                    }
                    Divider()
                    Text("\(scene.selectedEdges.count) edges selected").font(.headline)
                    Button("Clear selection") { scene.clearSelection() }
                        .disabled(scene.selectedEdges.isEmpty)
                    Text("Click an edge to select. Shift-click or Command-click toggles selection. Drag to navigate using your mouse settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Stored edges only — no surface occlusion or silhouettes. Selection does not create machining targets.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("\(scene.content.model.edges.count) edges shown · \(scene.content.model.skippedEdgeCount) skipped")
                    if let bounds = scene.content.model.bounds {
                        let size = bounds.max - bounds.min
                        Text(String(format: "%g × %g × %g mm", size.x, size.y, size.z))
                    }
                    ForEach(Array(scene.content.model.diagnostics.prefix(100).enumerated()), id: \.offset) { _, diagnostic in
                        Text((diagnostic.entityID.map { "#\($0): " } ?? "") + diagnostic.message)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if scene.content.model.diagnostics.count > 100 {
                        Text("\(scene.content.model.diagnostics.count - 100) more diagnostics…").font(.caption)
                    }
                    Divider()
                    Button("Reload source", action: onReload)
                    Button("Remove source", action: onRemove)
                }
                .padding(12)
            }
            .frame(width: 250)
            Divider()
            ZStack(alignment: .bottom) {
                MetalCanvasView(objects: .constant(scene.visibleObjects), interactionMode: .free3D,
                                clearColor: SIMD4<Float>(0.075, 0.085, 0.105, 1), zoomModel: zoom,
                                on3DClick: { point, size, matrix, modifiers in
                                    scene.pick(point: point, viewport: size, matrix: matrix,
                                               extend: modifiers.contains(.shift) || modifiers.contains(.command))
                                }, adaptiveModelFit: true, fitRequest: scene.fitRequest)
                    .id(ObjectIdentifier(scene))
                if scene.visibleObjects.isEmpty {
                    Text(scene.content.model.edges.isEmpty ? "No supported edges in this source" : "Model hidden")
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                HStack {
                    Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { scene.fitRequest &+= 1 }
                        .disabled(scene.visibleObjects.isEmpty)
                    CanvasZoomButton(zoomModel: zoom)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 16)
            }
        }
    }
}
