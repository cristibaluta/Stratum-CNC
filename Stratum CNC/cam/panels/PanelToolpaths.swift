//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

struct PanelToolpaths: View {

    let toolpaths: [ToolpathData]
    let selectedID: UUID?
    var hiddenIDs: Set<UUID> = []

    // Setups. With one (or none) the panel looks as it did before setups: a plain list. With
    // several, the list is grouped under one collapsible header per setup, in machining order.
    var setups: [Setup] = []
    var activeSetupID: UUID?
    /// Results, for the status mark of each setup's header.
    var generations: [UUID: ToolpathGeneration] = [:]

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    /// The header's "+": adds to the active setup.
    var onAdd: (() -> Void)?
    var onAddToSetup: ((UUID) -> Void)?
    /// Called once when a drag ends. The index is within the toolpath's own setup.
    var onMove: ((UUID, Int) -> Void)?
    /// (toolpath, setup): "Move to" in a row's menu.
    var onMoveToSetup: ((UUID, UUID) -> Void)?
    var onSelectSetup: ((UUID) -> Void)?
    var onAddSetup: ((SetupFace) -> Void)?
    var onRenameSetup: ((UUID, String) -> Void)?
    var onSetSetupFace: ((UUID, SetupFace) -> Void)?
    var onMoveSetup: ((UUID, Int) -> Void)?
    var onDeleteSetup: ((UUID) -> Void)?

    /// One drag at a time across all the sections; a row only follows it when its own
    /// section is the one being dragged (see `rows(_:)`).
    @StateObject private var reorder = ToolpathReorderModel()
    @State private var collapsedSetups: Set<UUID> = []
    @State private var renamingSetupID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var setupToDelete: Setup?

    private var showsSections: Bool {
        setups.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorHeader(title: "Toolpaths", addHelp: addHelp) {
                onAdd?()
            }

            Divider()

            if showsSections {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(setups.enumerated()), id: \.element.id) { index, setup in
                        section(for: setup, at: index)
                    }
                }
            } else if toolpaths.isEmpty {
                Text("No toolpaths")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                rows(toolpaths)
            }

            if onAddSetup != nil {
                addSetupMenu
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(setupToDelete.map { "Delete \($0.name)?" } ?? "",
                            isPresented: Binding(get: { setupToDelete != nil },
                                                 set: { if !$0 { setupToDelete = nil } }),
                            presenting: setupToDelete) { setup in
            Button("Delete setup and its \(toolpathsOf(setup).count) toolpaths", role: .destructive) {
                onDeleteSetup?(setup.id)
            }
        } message: { _ in
            Text("The setup's toolpaths are deleted with it. This can't be undone.")
        }
    }

    private var addHelp: String {
        guard showsSections, let active = setups.first(where: { $0.id == activeSetupID }) else {
            return "Add a toolpath"
        }
        return "Add a toolpath to \(active.name)"
    }

    // MARK: - Setup sections

    private func toolpathsOf(_ setup: Setup) -> [ToolpathData] {
        let known = Set(setups.map(\.id))
        let first = setups.first?.id
        return toolpaths.filter { toolpath in
            let id = toolpath.setupID.flatMap { known.contains($0) ? $0 : nil } ?? first
            return id == setup.id
        }
    }

    private func section(for setup: Setup, at index: Int) -> some View {
        let items = toolpathsOf(setup)
        let isCollapsed = collapsedSetups.contains(setup.id)

        return VStack(alignment: .leading, spacing: 2) {
            setupHeader(setup, at: index, items: items, isCollapsed: isCollapsed)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    if items.isEmpty {
                        Text("No toolpaths")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        rows(items)
                    }
                    Button {
                        onAddToSetup?(setup.id)
                    } label: {
                        Label("Add toolpath", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                }
                .padding(.leading, 12)
            }
        }
    }

    private func setupHeader(_ setup: Setup, at index: Int, items: [ToolpathData], isCollapsed: Bool) -> some View {
        let isActive = setup.id == activeSetupID

        return HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isCollapsed { collapsedSetups.remove(setup.id) } else { collapsedSetups.insert(setup.id) }
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isCollapsed ? "Show the toolpaths" : "Hide the toolpaths")

            SetupGlyph(angle: setup.angle)
                .frame(width: 14, height: 14)
                .help("Stock turned \(Int(setup.angle.rounded()))° about X: \(setup.orientationTitle) up")

            if renamingSetupID == setup.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .focused($renameFocused)
                    .onAppear { renameFocused = true }
                    .onSubmit { commitRename(of: setup) }
                    .onExitCommand { renamingSetupID = nil }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused, renamingSetupID == setup.id { commitRename(of: setup) }
                    }
            } else {
                Text("\(index + 1) · \(setup.name)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            statusMark(for: items)

            Text("\(items.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            setupMenu(for: setup, at: index, items: items)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectSetup?(setup.id)
        }
    }

    private func setupMenu(for setup: Setup, at index: Int, items: [ToolpathData]) -> some View {
        Menu {
            Button("Rename…") {
                renameText = setup.name
                renamingSetupID = setup.id
                renameFocused = true
            }
            Menu("Face") {
                ForEach(SetupFace.allCases) { face in
                    Button {
                        onSetSetupFace?(setup.id, face)
                    } label: {
                        if setup.face == face {
                            Label(face.title, systemImage: "checkmark")
                        } else {
                            Text(face.title)
                        }
                    }
                }
            }
            Button("Add toolpath") {
                onAddToSetup?(setup.id)
            }
            Divider()
            Button("Move up") {
                onMoveSetup?(setup.id, index - 1)
            }
            .disabled(index == 0)
            Button("Move down") {
                onMoveSetup?(setup.id, index + 1)
            }
            .disabled(index >= setups.count - 1)
            Divider()
            Button("Delete setup", role: .destructive) {
                if items.isEmpty {
                    onDeleteSetup?(setup.id)
                } else {
                    setupToDelete = setup
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }

    private func commitRename(of setup: Setup) {
        guard renamingSetupID == setup.id else {
            return
        }
        renamingSetupID = nil
        onRenameSetup?(setup.id, renameText)
    }

    /// A tick when every toolpath of the setup has a current result; a warning with the count
    /// when some are not generated, failed or outdated. Nothing for a setup with nothing to cut.
    @ViewBuilder
    private func statusMark(for items: [ToolpathData]) -> some View {
        let cutting = items.filter(\.hasGeometry)
        let pending = cutting.filter { toolpath in
            guard let generation = generations[toolpath.id], case .success = generation.outcome else {
                return true
            }
            return !generation.isCurrent(for: toolpath)
        }.count

        if !cutting.isEmpty {
            if pending == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Every toolpath is generated")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(pending == 1 ? "1 toolpath is not generated or is outdated"
                                       : "\(pending) toolpaths are not generated or are outdated")
            }
        }
    }

    private var addSetupMenu: some View {
        Menu {
            ForEach(SetupFace.allCases) { face in
                Button(face.title) {
                    onAddSetup?(face)
                }
            }
        } label: {
            Label("Add setup", systemImage: "plus.square.on.square")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Machine another side of the stock")
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
        let isHidden = hiddenIDs.contains(toolpath.id)

        return HStack(spacing: 6) {
            OperationIcon(kind: toolpath.operation.kind, size: 13)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .opacity(isHidden ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(toolpath.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                subtitle(for: toolpath)
            }
            .opacity(isHidden ? 0.5 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)

            InspectorVisibilityButton(isVisible: !isHidden,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(toolpath.id)
            }
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
            if showsSections, toolpath.operation.kind != .restMachining {
                Menu("Move to setup") {
                    ForEach(setups.filter { $0.id != toolpath.setupID }) { setup in
                        Button(setup.name) {
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

    /// What the toolpath does, without the operation's name (the title already says it): the
    /// tool, how it enters, how a pocket is cleared and where it ends.
    private func subtitle(for toolpath: ToolpathData) -> some View {
        let requirements = toolpath.machiningOperation.requirements
        let entryType: RampType = toolpath.ramping.enabled ? toolpath.ramping.type : .none
        let toolText = "Ø\(Self.number(Double(toolpath.tool.toolDiameter))) \(Self.title(of: toolpath.tool.type))"

        return HStack(spacing: 6) {
            // The one that gives way when the row is narrow; the icons and the depth keep their size
            Text(toolText)
                .lineLimit(1)
                .help("Tool: \(toolpath.tool.name)")

            if let side = Self.cutSide(of: toolpath) {
                ContourTypeGlyph(position: side, tint: .secondary)
                    .frame(width: 20, height: 13)
                    .help("Side: \(side.label)")
            }

            if requirements.usesEntry {
                // The glyph is drawn in absolute points (18x14), so it is scaled down, not resized
                RampTypeGlyph(type: entryType, tint: .secondary)
                    .frame(width: 18, height: 14)
                    .scaleEffect(0.65)
                    .frame(width: 12, height: 9)
                    .help("Entry: \(entryType.title)")
            }

            if !requirements.pocketPatterns.isEmpty {
                PatternGlyph(pattern: toolpath.operation.pocketPattern, tint: .secondary)
                    .frame(width: 18, height: 14)
                    .help("Pocketing: \(toolpath.operation.pocketPattern.rawValue)")
            }

            if toolpath.operation.kind == .restMachining {
                // Linked to a pocket instead of shapes
                let source = toolpaths.first { $0.id == toolpath.operation.restSourceID }
                Label(source?.name ?? "Source missing", systemImage: "link")
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(source == nil ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .help(source.map { "Cuts the corners of \($0.name)" } ?? "The pocket this belongs to was deleted")
            } else if !toolpath.cutsWholeStock {
                // The same hint as in the details panel: orange while nothing is selected yet
                Label("\(toolpath.targets.count + toolpath.stepTargets.count)", systemImage: "cursorarrow.click")
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(toolpath.hasGeometry ? Color.secondary : Color.orange)
                    .fixedSize()
                    .help(toolpath.selectionSummary)
            }

            Text(Self.endZText(of: toolpath))
                .lineLimit(1)
                .fixedSize()
                .help("End Z")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    /// The side of the shape the tool follows, for the operations that have one.
    private static func cutSide(of toolpath: ToolpathData) -> SC.CutSide? {
        switch toolpath.operation.kind {
            case .contour: return toolpath.contour
            case .chamfer: return toolpath.operation.chamferSide.position
            default:       return nil
        }
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

    /// Rotation of the stock about X, degrees (see `Setup.angle`).
    let angle: Double

    var body: some View {
        Canvas { context, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            context.stroke(Path(roundedRect: box, cornerRadius: 2), with: .color(.secondary), lineWidth: 1)

            // Where the up direction leaves the stock: Rx(θ)·ẑ = (0, −sin θ, cos θ) in (Y, Z), and Y is
            // to the right and Z up on screen.
            let radians = angle * .pi / 180
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
