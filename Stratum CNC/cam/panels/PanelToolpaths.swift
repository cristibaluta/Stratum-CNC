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

    // Setups (the faces the stock is held on). A "Setups" dropdown shows the active one and
    // opens a list of every setup the app offers: a checkmark means the project has it, and
    // checking or unchecking adds or removes it. Clicking a row makes that setup the active one,
    // whose toolpaths the list shows.
    var setups: [Setup] = []
    var activeSetupID: UUID?
    /// The side faces (front, back, left, right) stand the stock on its edge, which only makes sense
    /// for a 3D model: a project of flat shapes only offers the top and the bottom.
    var sideFacesAvailable = true

    var onSelect: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    /// The "+": adds a toolpath of the chosen operation to the active setup.
    var onAdd: ((SC.MachiningOperation.Kind) -> Void)?
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
    /// Collapsed, the panel is one line (title and count). Clicking it opens the list.
    @State private var isExpanded = true
    /// The "+" opens the operations to choose what the new toolpath does.
    @State private var isChoosingOperation = false
    /// The Setups dropdown is open.
    @State private var isChoosingSetup = false

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

                setupPicker

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

                if !toolpaths.isEmpty {
                    Text("\(toolpaths.count)")
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

    /// One line of the Setups list: an offered setup, and the project's own setup that fills it
    /// (`nil` while the project doesn't have it).
    private struct SetupEntry: Identifiable {
        let id: String
        let title: String
        /// The face a missing setup would be added as; nil for a setup that isn't one of the offered ones.
        let face: SetupFace?
        let axis: SetupAxis
        let setup: Setup?
    }

    /// Every setup the app offers, in a fixed order (the bottom once per flip axis), each tied to
    /// the project's setup of that kind when there is one. A project's setup that matches none
    /// of them (a second "Front", a side face of a project that no longer has a 3D model, an angle
    /// between faces) is listed after them, so it can still be chosen and removed.
    private var setupEntries: [SetupEntry] {
        var used = Set<UUID>()
        var entries: [SetupEntry] = []

        for face in SetupFace.allCases where sideFacesAvailable || !face.isSide {
            let axes: [SetupAxis] = face.hasChoiceOfAxis ? SetupAxis.allCases : [face.axis]
            for axis in axes {
                let match = setups.first { !used.contains($0.id) && $0.face == face && $0.axis == axis }
                if let match {
                    used.insert(match.id)
                }
                entries.append(SetupEntry(id: "\(face.rawValue)-\(axis.rawValue)",
                                          title: face.hasChoiceOfAxis ? "\(face.title) (flip \(axis.title))" : face.title,
                                          face: face,
                                          axis: axis,
                                          setup: match))
            }
        }
        for setup in setups where !used.contains(setup.id) {
            entries.append(SetupEntry(id: setup.id.uuidString, title: setup.name, face: nil, axis: setup.axis, setup: setup))
        }
        return entries
    }

    /// "Setups" and a button with the active setup's name, which opens the list.
    private var setupPicker: some View {
        HStack(spacing: 8) {
            Text("Setups")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                isChoosingSetup.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(activeSetup?.name ?? "No setup")
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Choose, add or remove a setup")
            .popover(isPresented: $isChoosingSetup, arrowEdge: .bottom) {
                setupList
            }
        }
    }

    private var setupList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(setupEntries) { entry in
                setupRow(entry)
            }
        }
        .padding(8)
        .frame(width: 240)
    }

    private func setupRow(_ entry: SetupEntry) -> some View {
        let exists = entry.setup != nil
        let isLast = exists && setups.count < 2

        return HStack(spacing: 8) {
            // Adds or removes the setup; the row itself picks it
            Toggle("", isOn: Binding(get: { exists }, set: { _ in toggle(entry) }))
                .labelsHidden()
                .stCheckboxToggleStyle()
                .controlSize(.small)
                .disabled(isLast)
                .help(isLast ? "The last setup can't be removed"
                             : exists ? "Remove this setup and its toolpaths" : "Add this setup")

            Button {
                choose(entry)
            } label: {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 12))
                        .foregroundStyle(exists ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let setup = entry.setup {
                        let count = toolpathsOf(setup).count
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .inspectorListRow(isSelected: entry.setup != nil && entry.setup?.id == activeSetup?.id)
    }

    /// The checkmark: adds the setup, or removes it (asking first when it has toolpaths, which go with it).
    private func toggle(_ entry: SetupEntry) {
        guard let setup = entry.setup else {
            add(entry)
            return
        }
        guard setups.count > 1 else {
            return
        }
        if toolpathsOf(setup).isEmpty {
            onDeleteSetup?(setup.id)
        } else {
            // The dialog belongs to the panel, not to the list: close the list first
            isChoosingSetup = false
            setupToDelete = setup
        }
    }

    /// The row: makes the setup the active one, adding it first when the project doesn't have it.
    private func choose(_ entry: SetupEntry) {
        if let setup = entry.setup {
            onSelectSetup?(setup.id)
        } else {
            add(entry)
        }
        isChoosingSetup = false
    }

    /// Adds the setup of `entry` and makes it the active one. The project has one bottom: asking
    /// for the other flip axis turns the existing bottom about it (its toolpaths stay, mirrored),
    /// instead of adding a second one.
    private func add(_ entry: SetupEntry) {
        guard let face = entry.face else {
            return
        }
        if face.hasChoiceOfAxis, let bottom = setups.first(where: { $0.face == face }) {
            onSetSetupAxis?(bottom.id, entry.axis)
            onSelectSetup?(bottom.id)
        } else {
            onAddSetup?(face, entry.axis)
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
                    .help("Pocketing: \(toolpath.operation.pocketPattern.title)")
            }

            if toolpath.operation.isRest {
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
