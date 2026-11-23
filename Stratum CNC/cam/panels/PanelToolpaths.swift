//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

struct PanelToolpaths: View {

    @ObservedObject var projectModel: ProjectModel
    let toolpaths: [ToolpathData]
    let selectedID: UUID?

    // The setups are listed in the Objects panel, which owns choosing, adding and removing them.
    // This panel only shows the active setup's toolpaths.
    var setups: [Setup] = []
    var activeSetupID: UUID?

    var onSelect: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    /// The "+": adds a toolpath of the chosen operation to the active setup.
    var onAdd: ((SC.MachiningOperation.Kind) -> Void)?
    /// Called once when a drag ends. The index is within the toolpath's own face.
    var onMove: ((UUID, Int) -> Void)?
    /// (toolpath, setup): "Move to" in a row's menu.
    var onMoveToSetup: ((UUID, UUID) -> Void)?

    @StateObject private var reorder = ToolpathReorderModel()
    /// Collapsed, the panel is one line (title and count). Clicking it opens the list.
    @State private var isExpanded = true
    /// The "+" opens the operations to choose what the new toolpath does.
    @State private var isChoosingOperation = false

    /// The face the list shows: the active one, or the first when the active id is unknown.
    private var activeSetup: Setup? {
        setups.first { $0.id == activeSetupID } ?? setups.first
    }

    /// What the list shows: the active face's toolpaths (all of them when there is one face).
    private var visibleToolpaths: [ToolpathData] {
        guard let activeSetup else {
            return toolpaths
        }
        return toolpathsOf(activeSetup)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if isExpanded {
                Divider()

                if visibleToolpaths.isEmpty {
                    Text("No toolpaths")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .padding(.vertical, 2)
                } else {
                    rows(visibleToolpaths)
                        // Rows pad their content by 6: grow them outward by as much, so the
                        // icons line up with the header and the other elements
                        .padding(.horizontal, -6)
                }

                Divider()

                footer
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
    }

    // MARK: - Header

    /// The title, how many toolpaths there are, and the chevron. The whole line toggles the panel.
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("Toolpaths")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !visibleToolpaths.isEmpty {
                    Text("\(visibleToolpaths.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                InspectorChevron(isExpanded: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide toolpaths" : "Show toolpaths")
    }

    /// The + at the bottom left.
    private var footer: some View {
        HStack {
            Button {
                isChoosingOperation.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(onAdd == nil)
            .help("Add a toolpath")
            .popover(isPresented: $isChoosingOperation, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                OperationGridPicker(selected: nil) { kind in
                    isChoosingOperation = false
                    onAdd?(kind)
                }
            }

            Spacer()
            PreviewInControllerButton(gCodeStore: projectModel.gCodeStore) {
                projectModel.saveIfNeeded()
                projectModel.previewInController()
            }
        }
    }

    // MARK: - Faces

    private func toolpathsOf(_ setup: Setup) -> [ToolpathData] {
        let known = Set(setups.map(\.id))
        let first = setups.first?.id
        return toolpaths.filter { toolpath in
            let id = toolpath.setupID.flatMap { known.contains($0) ? $0 : nil } ?? first
            return id == setup.id
        }
    }

    // MARK: - Rows

    /// One draggable list: the toolpaths of one setup (or all of them when there is a single one).
    private func rows(_ items: [ToolpathData]) -> some View {
        // The shared drag state only moves rows of the list the dragged row is in
        let ownsDrag = reorder.draggingID.map { dragging in items.contains { $0.id == dragging } } ?? false

        return VStack(alignment: .leading, spacing: ToolpathReorderModel.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, toolpath in
                let isLifted = reorder.isLifted(toolpath.id)

                toolpathRow(toolpath, at: index, count: items.count)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ToolpathRowHeightKey.self,
                                                   value: proxy.size.height)
                        }
                    )
                    .background {
                        if isLifted {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.thickMaterial)
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                    }
                    .offset(y: ownsDrag ? reorder.yOffset(for: toolpath.id, at: index) : 0)
                    .zIndex(toolpath.id == reorder.draggingID ? 1 : 0)
                    // The lifted row follows the pointer, so it must not animate
                    .transaction { transaction in
                        if isLifted {
                            transaction.animation = nil
                        }
                    }
            }
        }
        .coordinateSpace(name: ToolpathReorderModel.listSpace)
        .onPreferenceChange(ToolpathRowHeightKey.self) { height in
            if height > 0 {
                reorder.rowHeight = height
            }
        }
    }

    private func toolpathRow(_ toolpath: ToolpathData, at index: Int, count: Int) -> some View {
        let isSelected = toolpath.id == selectedID

        return HStack(spacing: 6) {
            OperationIcon(kind: toolpath.operation.kind, isRest: toolpath.operation.isRest, size: 13)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(toolpath.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                subtitle(for: toolpath)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .inspectorListRow(isSelected: isSelected)
        // The whole cell is the drag target and the select target. A tap and a drag on the
        // same view don't fight: the drag only starts after a few points of movement.
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(toolpath.id)
        }
        .gesture(dragGesture(for: toolpath, at: index, count: count))
        .contextMenu {
            if setups.count > 1, !toolpath.operation.isRest {
                Menu("Move to setup") {
                    ForEach(setups.filter { $0.id != toolpath.setupID }) { setup in
                        Button(setup.displayTitle) {
                            onMoveToSetup?(toolpath.id, setup.id)
                        }
                    }
                }
            }
            Button(role: .destructive) {
                onDelete?(toolpath.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Subtitle

    /// The row's second line: the tool's diameter and where the toolpath ends.
    private func subtitle(for toolpath: ToolpathData) -> some View {
        HStack(spacing: 6) {
            Text("Ø\(Self.number(Double(toolpath.tool.toolDiameter)))")
                .lineLimit(1)
                .help("Tool: \(toolpath.tool.name)")
            Text(Self.endZText(of: toolpath))
                .lineLimit(1)
                .fixedSize()
                .help("Final Z")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    /// A counterbore keeps its depth apart from `endZ`, as a positive number below the top.
    private static func endZText(of toolpath: ToolpathData) -> String {
        let z = toolpath.operation.kind == .counterbore
            ? -toolpath.operation.counterboreDepth
            : toolpath.endZ
        // Depth below the top, so shown without the sign: "Z1.5"
        return "Z\(number(abs(z)))"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func title(of type: ToolType) -> String {
        switch type {
            case .endMill:           return "End mill"
            case .ballNose:          return "Ball nose"
            case .engraving:         return "Engraving"
            case .drill:             return "Drill"
            case .vBit:              return "V-bit"
            case .corn:              return "Corn"
            case .chamfer:           return "Chamfer"
            case .solderMaskRemover: return "Solder mask"
            case .threadMill:        return "Thread mill"
        }
    }

    // MARK: - Reordering

    private func dragGesture(for toolpath: ToolpathData, at index: Int, count: Int) -> some Gesture {
        // Measured in the list's own space: the row moves under the pointer while it is
        // dragged, so a translation in the row's space would feed back into itself.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ToolpathReorderModel.listSpace))
            .onChanged { value in
                reorder.dragChanged(id: toolpath.id,
                                    index: index,
                                    translation: value.translation.height,
                                    count: count)
            }
            .onEnded { value in
                reorder.dragEnded(id: toolpath.id,
                                  translation: value.translation.height,
                                  count: count) { id, target in
                    onMove?(id, target)
                }
            }
    }
}

/// The height of a toolpath row, so the drag knows how far a slot is.
private struct ToolpathRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Icon and text close together, for the row's subtitle.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}


/// A setup's orientation as a small picture: the stock seen from the machine's right (front of
/// the machine on the left, back on the right), with a bar on the side that faces up. It is drawn
/// from the angle, so a rotary index lands between the faces without a new asset.
struct SetupGlyph: View {

    /// Rotation of the stock about X (or Y: seen from the front), degrees (see `Setup.angle`).
    let angle: Double

    var body: some View {
        Canvas { context, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            context.stroke(Path(roundedRect: box, cornerRadius: 2), with: .color(.secondary), lineWidth: 1)

            // Where the up direction leaves the stock: Rx(θ)·ẑ = (0, −sin θ, cos θ) in (Y, Z), and Y is
            // to the right and Z up on screen.
            let radians = angle.inRadians
            let direction = CGPoint(x: -sin(radians), y: -cos(radians))   // screen y points down
            let half = box.width / 2
            let center = CGPoint(x: box.midX, y: box.midY)
            let rim = CGPoint(x: center.x + direction.x * half, y: center.y + direction.y * half)
            let along = CGPoint(x: -direction.y, y: direction.x)          // along the marked side
            var bar = Path()
            bar.move(to: CGPoint(x: rim.x - along.x * half * 0.7, y: rim.y - along.y * half * 0.7))
            bar.addLine(to: CGPoint(x: rim.x + along.x * half * 0.7, y: rim.y + along.y * half * 0.7))
            context.stroke(bar, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

/// Same look as the Controller's "Refresh from CAM" button: prominent, with the refresh
/// icon, and a spinner while the program is being generated.
private struct PreviewInControllerButton: View {

    @ObservedObject var gCodeStore: GCodeStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if gCodeStore.isGeneratingFromCAM {
                ProgressView().controlSize(.small)
            } else {
                Label("Preview in Controller", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(gCodeStore.isGeneratingFromCAM)
        .help("Generate all toolpaths and open them in the Controller")
    }
}
