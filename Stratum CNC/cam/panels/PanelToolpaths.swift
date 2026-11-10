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

    // Faces (setups). A segmented control named after each face, always visible, picks which
    // one's toolpaths the list shows; a "+" button next to it adds a face.
    var setups: [Setup] = []
    var activeSetupID: UUID?
    /// The side faces (front, back, left, right) stand the stock on its edge, which only makes sense
    /// for a 3D model: a project of flat shapes only offers the top and the bottom.
    var sideFacesAvailable = true

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    /// "Add toolpath" in the header's menu: adds to the active face.
    var onAdd: (() -> Void)?
    /// Called once when a drag ends. The index is within the toolpath's own face.
    var onMove: ((UUID, Int) -> Void)?
    /// (toolpath, setup): "Move to" in a row's menu.
    var onMoveToSetup: ((UUID, UUID) -> Void)?
    var onSelectSetup: ((UUID) -> Void)?
    /// (face, the axis it is turned about): the axis only matters for the bottom.
    var onAddSetup: ((SetupFace, SetupAxis) -> Void)?
    /// (setup, axis): which axis a flipped face turns about, so which way its shapes mirror.
    var onSetSetupAxis: ((UUID, SetupAxis) -> Void)?
    var onDeleteSetup: ((UUID) -> Void)?

    @StateObject private var reorder = ToolpathReorderModel()
    @State private var setupToDelete: Setup?

    /// The faces the "+" button offers.
    private var addableFaces: [SetupFace] {
        SetupFace.allCases.filter { sideFacesAvailable || !$0.isSide }
    }

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

            Divider()

            facePicker

            if visibleToolpaths.isEmpty {
                Text("No toolpaths")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                rows(visibleToolpaths)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
        .confirmationDialog(setupToDelete.map { "Delete \($0.name)?" } ?? "",
                            isPresented: Binding(get: { setupToDelete != nil },
                                                 set: { if !$0 { setupToDelete = nil } }),
                            presenting: setupToDelete) { setup in
            Button("Delete face and its \(toolpathsOf(setup).count) toolpaths", role: .destructive) {
                onDeleteSetup?(setup.id)
            }
        } message: { _ in
            Text("The face's toolpaths are deleted with it. This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Toolpaths")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                Button("Add toolpath") {
                    onAdd?()
                }
                .disabled(onAdd == nil)

                // Only a flipped face has a choice: the others are reached about one axis only
                if let activeSetup, activeSetup.face?.hasChoiceOfAxis == true {
                    Menu("Flip about") {
                        ForEach(SetupAxis.allCases) { axis in
                            Button {
                                onSetSetupAxis?(activeSetup.id, axis)
                            } label: {
                                if activeSetup.axis == axis {
                                    Label(Self.flipTitle(axis), systemImage: "checkmark")
                                } else {
                                    Text(Self.flipTitle(axis))
                                }
                            }
                        }
                    }
                    .disabled(onSetSetupAxis == nil)
                }

                Divider()

                Button("Delete active face", role: .destructive) {
                    guard let activeSetup else {
                        return
                    }
                    if toolpathsOf(activeSetup).isEmpty {
                        onDeleteSetup?(activeSetup.id)
                    } else {
                        setupToDelete = activeSetup
                    }
                }
                // The last face can't be deleted
                .disabled(setups.count < 2 || onDeleteSetup == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Add a toolpath, or change the active face")
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

    /// The faces as a segmented control, always visible, with the "+" that adds one at its right.
    private var facePicker: some View {
        HStack(spacing: 6) {
            Picker("Face", selection: Binding(
                get: { activeSetup?.id ?? UUID() },
                set: { onSelectSetup?($0) }
            )) {
                ForEach(setups) { setup in
                    Text(setup.name).tag(setup.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            addFaceMenu
        }
    }

    private var addFaceMenu: some View {
        Menu {
            ForEach(addableFaces) { face in
                if face.hasChoiceOfAxis {
                    // Which axis the stock is flipped about decides which way its shapes mirror
                    Menu(face.title) {
                        ForEach(SetupAxis.allCases) { axis in
                            Button(Self.flipTitle(axis)) {
                                onAddSetup?(face, axis)
                            }
                        }
                    }
                } else {
                    Button(face.title) {
                        onAddSetup?(face, face.axis)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(onAddSetup == nil)
        .help("Add a face")
    }

    /// "Flip about X (mirrors Y)": turning the stock over about an axis mirrors the shapes across it.
    private static func flipTitle(_ axis: SetupAxis) -> String {
        "Flip about \(axis.title) (mirrors \(axis == .x ? "Y" : "X"))"
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
            if setups.count > 1, toolpath.operation.kind != .restMachining {
                Menu("Move to face") {
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

    /// Rotation of the stock about X (or Y: seen from the front), degrees (see `Setup.angle`).
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
