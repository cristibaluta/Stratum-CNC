//
//  PanelSetups.swift
//  Stratum CNC
//
//  The project's setups (stock orientations), in a panel of their own between the Objects
//  and the Toolpaths panels. With several objects the setups are grouped under the object
//  they cut; the ones that include several objects are listed as "Combined".
//

import SwiftUI

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
    /// A setup is the selection (and not an object): only then is the active setup highlighted.
    var isSetupSelected = false
    /// How many toolpaths each setup contains, by setup id
    var toolpathCounts: [UUID: Int] = [:]
    /// Front, back, left and right need a 3D model.
    var sideFacesAvailable = false
    /// The groups (virtual objects) setups can be made for.
    var groups: [ObjectItem] = []
    /// The selected 2D objects that can be combined into one setup.
    var combinableSelection: [UUID] = []

    var onSelectSetup: ((UUID) -> Void)?
    /// A new setup on a face; the object is nil for one that includes every object.
    var onAddSetup: ((UUID?, SetupFace, SetupAxis?) -> Void)?
    /// A new setup on a face for all the members of a group.
    var onAddGroupSetup: ((UUID, SetupFace, SetupAxis?) -> Void)?
    var onRenameSetup: ((UUID, String) -> Void)?
    var onDeleteSetup: ((UUID) -> Void)?
    /// "Combine into one setup": a new setup on a face that includes all the given objects.
    var onAddCombinedSetup: (([UUID], SetupFace, SetupAxis?) -> Void)?

    /// Collapsed, the panel is one line (title and count). Clicking it opens the list.
    @State private var isExpanded = true
    @State private var renamingSetupID: UUID?
    @State private var renameText = ""

    /// The horizontal padding of a list row (`inspectorListRow`).
    private static let rowInset: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider()
                    .padding(.vertical, 8)

                list
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
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
            if !groups.isEmpty {
                Divider()
                ForEach(groups) { group in
                    faceMenu(title: "Add New Setup for Group \(group.name)", systemImage: "square.on.square") { face, axis in
                        onAddGroupSetup?(group.id, face, axis)
                    }
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

    /// The object a setup is listed under: the only object it includes. A setup with several
    /// objects, or one that includes everything of a multi-object project, is "combined".
    private func ownerID(of setup: Setup) -> UUID? {
        if let groupID = setup.groupID, groups.contains(where: { $0.id == groupID }) {
            return nil
        }
        let ids = objects.map(\.id)
        if setup.items.isEmpty {
            return ids.count == 1 ? ids[0] : nil
        }
        if setup.items.count == 1, ids.contains(setup.items[0].objectID) {
            return setup.items[0].objectID
        }
        return nil
    }

    private var combinedSetups: [Setup] {
        setups.filter { setup in
            ownerID(of: setup) == nil
                && !(setup.groupID.map { id in groups.contains { $0.id == id } } ?? false)
        }
    }

    /// With a single object the group titles would only repeat its name.
    private var showsGroupTitles: Bool {
        objects.count > 1
    }

    @ViewBuilder
    private var list: some View {
        if setups.isEmpty {
            Text("No setups")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(objects) { object in
                    let owned = setups.filter { ownerID(of: $0) == object.id }
                    if !owned.isEmpty {
                        if showsGroupTitles {
                            groupTitle(object.name)
                        }
                        ForEach(owned) { setup in
                            setupRow(setup)
                        }
                    }
                }
                ForEach(groups) { group in
                    let owned = setups.filter { $0.groupID == group.id }
                    if !owned.isEmpty {
                        groupTitle("Group: \(group.name)")
                        ForEach(owned) { setup in
                            setupRow(setup)
                        }
                    }
                }
                if !combinedSetups.isEmpty {
                    groupTitle("Combined")
                    ForEach(combinedSetups) { setup in
                        setupRow(setup)
                    }
                }
            }
            // Rows pad their content by 6: grow them outward by as much, so the icons
            // line up with the header and the other elements
            .padding(.horizontal, -Self.rowInset)
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Self.rowInset)
            .padding(.top, 6)
    }

    private func setupRow(_ setup: Setup) -> some View {
        Button {
            onSelectSetup?(setup.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(setup.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let count = toolpathCounts[setup.id], count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(count == 1 ? "1 toolpath" : "\(count) toolpaths")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .inspectorListRow(isSelected: isSetupSelected && setup.id == activeSetupID)
        .contextMenu {
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
