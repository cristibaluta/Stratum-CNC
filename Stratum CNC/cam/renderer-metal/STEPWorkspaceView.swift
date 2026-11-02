import SwiftUI

/// Floating panel over the CAM canvas while it is in 3D (STEP) mode. It used to
/// be a full-screen view of its own; the canvas is now the shared one, and this
/// only carries the layer toggles, the selection and, folded away, the import
/// details that are mostly useful for debugging.
struct STEPInfoPanel: View {
    @ObservedObject var workspace: STEPWorkspace
    let onImport: () -> Void
    let onReload: (UUID) -> Void
    let onRemove: (UUID) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                // Short content sizes to itself, long content scrolls.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.transparent")
            Text("STEP wireframe").font(.headline)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.sources.count > 1 {
                Picker("Source", selection: $workspace.activeID) {
                    ForEach(workspace.sources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .labelsHidden()
            } else if let source = workspace.sources.first {
                Text(source.name)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            if let id = workspace.activeID {
                if workspace.loadingIDs.contains(id) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading STEP geometry…")
                        Spacer()
                        Button("Cancel") { workspace.cancel(id) }.controlSize(.small)
                    }
                } else if let scene = workspace.documents[id] {
                    STEPSceneDetails(scene: scene,
                                     onImport: onImport,
                                     onReload: { onReload(id) },
                                     onRemove: { onRemove(id) })
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Could not load this source", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                        Text(workspace.errors[id] ?? "No geometry loaded")
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Button("Retry") { onReload(id) }
                            Button("Remove source") { onRemove(id) }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct STEPSceneDetails: View {
    @ObservedObject var scene: STEPDocumentScene
    let onImport: () -> Void
    let onReload: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(CanvasLayer.model.label, isOn: $scene.isModelVisible)
            ForEach(scene.content.geometry.bodies, id: \.id) { body in
                Toggle("Body #\(body.id.entityID) · \(body.edges.count) edges", isOn: Binding(
                    get: { !scene.hiddenBodies.contains(body.id) },
                    set: { scene.setBodyVisible(body.id, $0) }
                ))
                .disabled(!scene.isModelVisible)
                .padding(.leading, 16)
            }

            Divider()

            HStack {
                Text("\(scene.selectedEdges.count) edges selected").font(.subheadline)
                Spacer()
                Button("Clear") { scene.clearSelection() }
                    .controlSize(.small)
                    .disabled(scene.selectedEdges.isEmpty)
            }
            Text("Click an edge to select. Shift-click or Command-click toggles it.")
                .font(.caption).foregroundStyle(.secondary)

            // The import numbers, the diagnostics and the limits of the view:
            // useful when something looks wrong, noise otherwise.
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(scene.content.model.edges.count) edges shown · \(scene.content.model.skippedEdgeCount) skipped")
                    if let bounds = scene.content.model.bounds {
                        let size = bounds.max - bounds.min
                        Text(String(format: "%g × %g × %g mm", size.x, size.y, size.z))
                    }
                    Text("Stored edges only — no surface occlusion or silhouettes. Selection does not create machining targets.")
                        .font(.caption).foregroundStyle(.secondary)
                    let diagnostics = scene.content.model.diagnostics
                    ForEach(Array(diagnostics.prefix(100).enumerated()), id: \.offset) { _, diagnostic in
                        Text((diagnostic.entityID.map { "#\($0): " } ?? "") + diagnostic.message)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if diagnostics.count > 100 {
                        Text("\(diagnostics.count - 100) more diagnostics…").font(.caption)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            Divider()

            HStack {
                Button("Import…", action: onImport)
                Button("Reload", action: onReload)
                Button("Remove", role: .destructive, action: onRemove)
            }
            .controlSize(.small)
        }
    }
}
