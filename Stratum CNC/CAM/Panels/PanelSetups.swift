//
//  PanelSetups.swift
//  Stratum CNC
//
//  The project's setups (stock orientations), a section of the project tree under the Objects.
//  A setup can use any combination of the objects (chosen in its details), so the list is flat:
//  the setups under the "Setups" row, each with its toolpaths under it.
//

import SwiftUI
import StratumCAM
struct PanelSetups: View {

    /// An object a setup can cut: its id and the name shown for it.
    struct ObjectItem: Identifiable {
        let id: UUID
        let name: String
    }

    /// The objects that can have setups: everything except the fixtures.
    let objects: [ObjectItem]
    let setups: [Setup]
    var activeSetupID: UUID?
    /// The setup whose details are open: the only row that is highlighted. The active setup is
    /// marked by its dot, whatever else is selected (a toolpath, an object).
    var editingSetupID: UUID?
    /// How many toolpaths each setup contains, by setup id
    var toolpathCounts: [UUID: Int] = [:]
    /// Every toolpath of the project: each setup lists its own under it.
    var toolpaths: [ToolpathData] = []
    var selectedToolpathID: UUID?
    /// Needed by the toolpath rows (ticking, sending) and the send bar
    var projectModel: ProjectModel?
    /// The "+" of a setup: adds a toolpath of the chosen operation to it.
    var onAddToolpath: ((UUID, SC.MachiningOperation.Kind) -> Void)?
    var onSelectToolpath: ((UUID) -> Void)?
    var onDeleteToolpath: ((UUID) -> Void)?
    var onDuplicateToolpath: ((UUID) -> Void)?
    var onMoveToolpath: ((UUID, Int) -> Void)?
    var onMoveToolpathToSetup: ((UUID, UUID) -> Void)?
    /// Front, back, left and right need a 3D model.
    var sideFacesAvailable = false
    /// The selected 2D objects that can be combined into one setup.
    var combinableSelection: [UUID] = []

    var onSelectSetup: ((UUID) -> Void)?
    /// The pencil / "Edit…": opens the setup's details.
    var onEditSetup: ((UUID) -> Void)?
    /// A new setup on a face; the object is nil for one that includes every object.
    var onAddSetup: ((UUID?, SetupFace, SetupAxis?) -> Void)?
    var onRenameSetup: ((UUID, String) -> Void)?
    var onDeleteSetup: ((UUID) -> Void)?
    /// "Combine into one setup": a new setup on a face that includes all the given objects.
    var onAddCombinedSetup: (([UUID], SetupFace, SetupAxis?) -> Void)?
    /// Context menu: a new setup on a face, on the same objects as the given setup.
    var onAddSetupLike: ((UUID, SetupFace, SetupAxis?) -> Void)?

    /// Drawn as a section of `PanelProject`: no card of its own, and no send bar (the project's footer has it).
    var embedded = false

    /// Collapsed, the panel is one line (title and count). Clicking it opens the list.
    @State private var isExpanded = true
    @State private var renamingSetupID: UUID?
    @State private var renameText = ""
    /// The setups whose toolpaths are listed under them
    @State private var expandedSetupIDs: Set<UUID> = []
    /// The setup whose "+" is open, to choose the operation of the new toolpath
    @State private var choosingOperationFor: UUID?
    /// The setup row under the pointer, which shows its pencil
    @State private var hoveredSetupID: UUID?

    /// The horizontal padding of a list row (`inspectorListRow`).
    private static let rowInset: CGFloat = 6
    /// How far the rows sit in from the section header (the chevron's width)
    private static let indent: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                list
                    .padding(.top, 4)

                if !embedded, let projectModel, !toolpaths.isEmpty {
                    Divider()
                        .padding(.vertical, 8)

                    ToolpathSendBar(projectModel: projectModel, toolpaths: toolpaths)
                }
            }
        }
        .onAppear {
            if let activeSetupID {
                expandedSetupIDs.insert(activeSetupID)
            }
        }
        // Choosing a setup (or opening a toolpath, which makes its setup the active one) shows its toolpaths
        .onChange(of: activeSetupID) { _, id in
            if let id {
                expandedSetupIDs.insert(id)
            }
        }
        .modifier(PanelCardChrome(isCard: !embedded))
        .alert("Rename Setup", isPresented: Binding(get: { renamingSetupID != nil },
                                                    set: { if !$0 { renamingSetupID = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renamingSetupID {
                    onRenameSetup?(id, renameText)
                }
                renamingSetupID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSetupID = nil
            }
        }
    }

    // MARK: - Header

    /// The chevron, the title and how many setups there are; the + is at the top right.
    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    InspectorChevron(isExpanded: isExpanded)

                    Text("Setups")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if !setups.isEmpty {
                        Text("\(setups.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide setups" : "Show setups")

            addMenu
        }
    }

    /// The + at the top right: a new setup, for one object or for all of them.
    private var addMenu: some View {
        Menu {
            if objects.count <= 1 {
                faceMenu(title: "Add New Setup", systemImage: "plus.square.on.square") { face, axis in
                    onAddSetup?(objects.first?.id, face, axis)
                }
            } else {
                ForEach(objects) { object in
                    faceMenu(title: "Add New Setup for \(object.name)", systemImage: "plus.square.on.square") { face, axis in
                        onAddSetup?(object.id, face, axis)
                    }
                }
                faceMenu(title: "Add New Setup for All Objects", systemImage: "square.on.square") { face, axis in
                    onAddSetup?(nil, face, axis)
                }
            }
            if combinableSelection.count >= 2 {
                Divider()
                faceMenu(title: "Combine \(combinableSelection.count) Selected into One Setup",
                         systemImage: "square.on.square") { face, axis in
                    onAddCombinedSetup?(combinableSelection, face, axis)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .padding(3)
        }
        .stBorderlessMenuStyle()
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Add a setup")
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if setups.isEmpty {
            Text("No setups")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.vertical, 2)
                .padding(.leading, Self.indent)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(setups) { setup in
                    setupRow(setup)
                }
            }
            // Rows pad their content by 6: grow them outward by as much, then indent
            // them under the header's chevron
            .padding(.leading, Self.indent - Self.rowInset)
            .padding(.trailing, -Self.rowInset)
        }
    }

    /// The toolpaths of a setup. One without a setup, or whose setup is gone, belongs to the first.
    private func toolpaths(of setup: Setup) -> [ToolpathData] {
        let known = Set(setups.map(\.id))
        let first = setups.first?.id
        return toolpaths.filter { toolpath in
            (toolpath.setupID.flatMap { known.contains($0) ? $0 : nil } ?? first) == setup.id
        }
    }

    /// While choosing what to send only the active setup is open (only its toolpaths can be sent),
    /// so its checkboxes are all in view and the other setups stay closed.
    private func isOpen(_ setup: Setup) -> Bool {
        if projectModel?.isChoosingToolpathsToSend ?? false {
            return setup.id == activeSetupID
        }
        return expandedSetupIDs.contains(setup.id)
    }

    /// A setup: its row, and under it (when open) its toolpaths.
    private func setupRow(_ setup: Setup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            setupHeader(setup)
            if isOpen(setup), let projectModel {
                SetupToolpaths(projectModel: projectModel,
                               toolpaths: toolpaths(of: setup),
                               selectedID: selectedToolpathID,
                               setups: setups,
                               onSelect: onSelectToolpath,
                               onDelete: onDeleteToolpath,
                               onDuplicate: onDuplicateToolpath,
                               onMove: onMoveToolpath,
                               onMoveToSetup: onMoveToolpathToSetup)
                    .padding(.leading, 12)
            }
        }
    }

    /// The pencil and the + only show on the row under the pointer, or while the
    /// operation picker is open, so a list of setups isn't a column of buttons.
    private func showsRowActions(_ setup: Setup) -> Bool {
        hoveredSetupID == setup.id || choosingOperationFor == setup.id
    }

    private func setupHeader(_ setup: Setup) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expandedSetupIDs.contains(setup.id) {
                        expandedSetupIDs.remove(setup.id)
                    } else {
                        expandedSetupIDs.insert(setup.id)
                    }
                }
            } label: {
                InspectorChevron(isExpanded: isOpen(setup))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(projectModel?.isChoosingToolpathsToSend ?? false)
            .help(isOpen(setup) ? "Hide toolpaths" : "Show toolpaths")

            Button {
                onSelectSetup?(setup.id)
            } label: {
                HStack(spacing: 6) {
                    Text(setup.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // The setup that new toolpaths go to: a dot, as the selected row is already highlighted.
                    // It stays when an object is selected instead, and only the highlight goes.
                    if setup.id == activeSetupID {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .help("Active setup")
                    }
                    Spacer(minLength: 4)
                    if let count = toolpathCounts[setup.id], count > 0 {
                        Text(count == 1 ? "1 op" : "\(count) ops")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .help(count == 1 ? "1 toolpath" : "\(count) toolpaths")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Double click: the same as the pencil
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onEditSetup?(setup.id)
            })

            // The pencil and the + take the place of the count at the right only while the row is
            // hovered: the count then moves left, next to the name.
            if showsRowActions(setup) {
                Button {
                    onEditSetup?(setup.id)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Edit \(setup.name)")

                addToolpathButton(for: setup)
            }
        }
        .inspectorListRow(isSelected: setup.id == editingSetupID && selectedToolpathID == nil)
        .onHover { inside in
            if inside {
                hoveredSetupID = setup.id
            } else if hoveredSetupID == setup.id {
                hoveredSetupID = nil
            }
        }
        .contextMenu {
            setupContextMenu(setup)
        }
    }

    private func addToolpathButton(for setup: Setup) -> some View {
        Button {
            choosingOperationFor = setup.id
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(onAddToolpath == nil || (projectModel?.isChoosingToolpathsToSend ?? false))
        .help("Add a toolpath to \(setup.name)")
        .popover(isPresented: Binding(get: { choosingOperationFor == setup.id },
                                      set: { if !$0 { choosingOperationFor = nil } }),
                 attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            OperationGridPicker(selected: nil) { kind in
                choosingOperationFor = nil
                expandedSetupIDs.insert(setup.id)
                onAddToolpath?(setup.id, kind)
            }
        }
    }

    @ViewBuilder
    private func setupContextMenu(_ setup: Setup) -> some View {
            Button {
                onEditSetup?(setup.id)
            } label: {
                Label("Edit…", systemImage: "slider.horizontal.3")
            }
            faceMenu(title: "Add Setup on Same Objects", systemImage: "plus.square.on.square") { face, axis in
                onAddSetupLike?(setup.id, face, axis)
            }
            Button {
                renameText = setup.name
                renamingSetupID = setup.id
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDeleteSetup?(setup.id)
            } label: {
                Label("Delete Setup", systemImage: "trash")
            }
            .disabled(setups.count <= 1)
    }

    // MARK: - Faces

    /// What a "new setup" menu offers: each face, with the bottom split in two by the axis it is flipped on.
    private var setupFaceChoices: [(id: String, title: String, face: SetupFace, axis: SetupAxis?)] {
        var choices: [(id: String, title: String, face: SetupFace, axis: SetupAxis?)] = []
        for face in SetupFace.allCases where !face.isSide || sideFacesAvailable {
            if face.hasChoiceOfAxis {
                for axis in SetupAxis.allCases {
                    choices.append((id: "\(face.rawValue)-\(axis.rawValue)",
                                    title: "\(face.title) (flip on \(axis.title))",
                                    face: face, axis: axis))
                }
            } else {
                choices.append((id: "\(face.rawValue)", title: face.title, face: face, axis: nil))
            }
        }
        return choices
    }

    /// A submenu with a face to pick.
    private func faceMenu(title: String,
                          systemImage: String,
                          pick: @escaping (SetupFace, SetupAxis?) -> Void) -> some View {
        Menu {
            ForEach(setupFaceChoices, id: \.id) { choice in
                Button(choice.title) {
                    pick(choice.face, choice.axis)
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
