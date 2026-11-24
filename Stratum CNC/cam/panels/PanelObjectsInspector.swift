//
//  PanelObjectsInspector.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 03/09/2026.
//

import SwiftUI

/// A STEP model as a row of the objects list.
struct STEPModelItem: Identifiable {
    let id: UUID
    let name: String
    let isVisible: Bool
    /// Where the model sits (its corner and its top), in mm. `nil` while it is
    /// loading or when it failed to load.
    let position: SIMD3<Float>?
    /// Width (X), depth (Y) and height (Z) of the model, in mm.
    let size: SIMD3<Float>?
    /// Which face of the model faces up. `nil` while it is loading or failed to load.
    var orientation: SetupFace? = nil
    /// What the file calls the body (occurrence path and name), shown as the row's tooltip.
    var detail: String? = nil
}

/// The list of objects, their setups and the STEP models. The selected object's placement
/// (position, size, face up) is `PanelObjectProperties`.
struct PanelObjectsInspector: View {

    let elements: [D2_Object]
    let selectedIDs: Set<UUID>

    /// The object clicked, and whether to add it to / remove it from the selection (Shift
    /// or Cmd held) instead of replacing the selection.
    var onSelectionChanged: ((UUID, Bool) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    /// "Import 2D/3D objects…" in the + menu: opens the file picker.
    var onAddNew: (() -> Void)?
    /// "Create alignment pins…" in the + menu: opens the dialog.
    var onCreateAlignmentPins: (() -> Void)?

    /// Collapsed, the panel is one line (title and count). Clicking it opens the list.
    @State private var isExpanded = true

    var onDelete: ((UUID) -> Void)?
    /// Right-click "Generate Project Preview": the project card's picture is made from this object alone.
    var onGeneratePreview: ((UUID) -> Void)?

    /// STEP models are listed after the 2D objects. Selecting one shows its X, Y, Z.
    var stepModels: [STEPModelItem] = []
    var selectedStepModelID: UUID?
    var onSelectStepModel: ((UUID) -> Void)?
    var onToggleStepModelVisibility: ((UUID) -> Void)?
    var onDeleteStepModel: ((UUID) -> Void)?

    /// The project's setups, listed under the object they cut. The active one is highlighted.
    var setups: [Setup] = []
    var activeSetupID: UUID?
    /// How many toolpaths each setup contains, by setup id
    var toolpathCounts: [UUID: Int] = [:]
    /// Front, back, left and right need a 3D model.
    var sideFacesAvailable = false
    var onSelectSetup: ((UUID) -> Void)?
    /// A new setup on a face; the object is nil for one that includes every object.
    var onAddSetup: ((UUID?, SetupFace, SetupAxis?) -> Void)?
    var onRenameSetup: ((UUID, String) -> Void)?
    var onDeleteSetup: ((UUID) -> Void)?
    /// "Combine into one setup": a new setup on a face that includes all the given objects.
    var onAddCombinedSetup: (([UUID], SetupFace, SetupAxis?) -> Void)?

    @State private var renamingSetupID: UUID?
    @State private var renameText = ""

    /// The object whose setups are open; its face up, position and size are in the right-hand panel.
    var focusedObjectID: UUID?
    /// A plain click on an object's row: focuses it and opens its first setup.
    var onSelectObject: ((UUID) -> Void)?
    /// A setup is the selection (and not an object): only one of the two is highlighted.
    var isSetupSelected = false

    /// Objects whose setups are shown under them.
    @State private var expandedObjects: Set<UUID> = []

    /// The horizontal padding of a list row (`inspectorListRow`).
    private static let rowInset: CGFloat = 6

    // MARK: - Body

    var body: some View {
        listPanel
    }

    // MARK: - List panel (left side)

    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider()
                    .padding(.vertical, 8)

                objectsSection

                // Separates the list (and the properties under it) from the + button, like in
                // the Toolpaths panel
                Divider()
                    .padding(.top, 10)

                footer
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
    }

    // MARK: - Header

    /// The title, how many objects there are, and the chevron. The whole line toggles the panel.
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("Objects")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                let count = elements.count + stepModels.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                InspectorChevron(isExpanded: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide objects" : "Show objects")
    }

    // MARK: - Footer

    /// The + at the bottom left; it opens a menu instead of acting at once.
    private var footer: some View {
        HStack {
            Menu {
                Button {
                    onAddNew?()
                } label: {
                    Label("Import 2D/3D Objects…", systemImage: "square.and.arrow.down")
                }
                Button {
                    onCreateAlignmentPins?()
                } label: {
                    Label("Create Alignment Pins…", systemImage: "circle.grid.2x2")
                }
                Divider()
                newSetupMenu(for: regularObjectIDs.count == 1 ? regularObjectIDs[0] : nil)
                combineMenu
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .padding(3)
            }
            .stBorderlessMenuStyle()
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Add objects")

            Spacer()
        }
    }

    // MARK: - Objects

    private var objectsSection: some View {
        Group {
            if elements.isEmpty && stepModels.isEmpty {
                Text("No object imported!")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    objectTree
                }
                // Rows pad their content by 6: grow them outward by as much, so the icons
                // line up with the header and the other elements
                .padding(.horizontal, -Self.rowInset)
            }
        }
        .onAppear {
            if let focusedObjectID {
                expandedObjects.insert(focusedObjectID)
            }
        }
        .onChange(of: focusedObjectID) { _, new in
            if let new {
                // Opening the new object's setups is part of the switch: no animation
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    expandedObjects.insert(new)
                }
            }
        }
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

    // MARK: - Tree (Object > Setups)

    /// The objects that can have setups: everything except the alignment pins.
    private var regularShapes: [D2_Object] {
        elements.filter { !$0.isParametric }
    }

    private var fixtureShapes: [D2_Object] {
        elements.filter { $0.isParametric }
    }

    private var regularObjectIDs: [UUID] {
        regularShapes.map(\.id) + stepModels.map(\.id)
    }

    /// With a single object the object level is hidden: only its setups are listed.
    private var hidesObjectLevel: Bool {
        regularObjectIDs.count <= 1
    }

    /// The object a setup is listed under: the only object it includes. A setup with several
    /// objects, or one that includes everything of a multi-object project, is "combined".
    private func ownerID(of setup: Setup) -> UUID? {
        let ids = regularObjectIDs
        if setup.items.isEmpty {
            return ids.count == 1 ? ids[0] : nil
        }
        if setup.items.count == 1, ids.contains(setup.items[0].objectID) {
            return setup.items[0].objectID
        }
        return nil
    }

    private func setups(under objectID: UUID) -> [Setup] {
        setups.filter { ownerID(of: $0) == objectID }
    }

    private var combinedSetups: [Setup] {
        setups.filter { ownerID(of: $0) == nil }
    }

    @ViewBuilder
    private var objectTree: some View {
        ForEach(regularShapes, id: \.id) { object in
            objectRow(object)
            if expandedObjects.contains(object.id) {
                ForEach(setups(under: object.id)) { setup in
                    setupRow(setup)
                        .padding(.leading, 20)
                }
            }
        }
        ForEach(stepModels) { model in
            stepModelRow(model)
            if expandedObjects.contains(model.id) {
                ForEach(setups(under: model.id)) { setup in
                    setupRow(setup)
                        .padding(.leading, 20)
                }
            }
        }
        if !combinedSetups.isEmpty {
            groupTitle("Combined")
            ForEach(combinedSetups) { setup in
                setupRow(setup)
            }
        }
        // Only once pins exist
        if !fixtureShapes.isEmpty {
            groupTitle("Fixtures")
            ForEach(fixtureShapes, id: \.id) { object in
                objectRow(object)
            }
        }
    }

    /// The triangle in front of an object: opens and closes its setups.
    private func disclosure(_ id: UUID) -> some View {
        Button {
            if expandedObjects.contains(id) {
                expandedObjects.remove(id)
            } else {
                expandedObjects.insert(id)
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expandedObjects.contains(id) ? 90 : 0))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expandedObjects.contains(id) ? "Hide setups" : "Show setups")
    }

    /// A row is highlighted when it is the focused object and its setups are closed (open, the
    /// active setup carries the highlight), or when several objects are selected.
    private func isRowSelected(_ id: UUID) -> Bool {
        if selectedIDs.count > 1 {
            return selectedIDs.contains(id)
        }
        return !isSetupSelected && focusedObjectID == id
    }

    private func objectRow(_ object: D2_Object) -> some View {
        HStack(spacing: 4) {
            if object.isParametric {
                Color.clear.frame(width: 14, height: 14)
            } else {
                disclosure(object.id)
            }
            Button {
                let flags = CanvasModifiers.current
                if flags.contains(.shift) || flags.contains(.command) {
                    onSelectionChanged?(object.id, true)
                } else {
                    onSelectObject?(object.id)
                }
            } label: {
                HStack(spacing: 6) {
                    if object.isParametric {
                        Image(systemName: "circle.grid.2x2")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(object.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .opacity(object.isVisible ? 1 : 0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InspectorVisibilityButton(isVisible: object.isVisible,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(object.id)
            }
        }
        .inspectorListRow(isSelected: isRowSelected(object.id))
        .contextMenu {
            if !object.isParametric {
                newSetupMenu(for: object.id)
            }
            if !object.isParametric {
                combineMenu
            }
            Button {
                onGeneratePreview?(object.id)
            } label: {
                Label("Generate Project Preview", systemImage: "photo")
            }
            Divider()
            Button(role: .destructive) {
                onDelete?(object.id)
            } label: {
                Label("Delete Object", systemImage: "trash")
            }
        }
    }

    private func stepModelRow(_ model: STEPModelItem) -> some View {
        HStack(spacing: 4) {
            disclosure(model.id)
            Button {
                onSelectObject?(model.id)
            } label: {
                Text(model.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(model.isVisible ? 1 : 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            InspectorVisibilityButton(isVisible: model.isVisible,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleStepModelVisibility?(model.id)
            }
        }
        .inspectorListRow(isSelected: isRowSelected(model.id))
        .help(model.detail.map { "\(model.name) — \($0)" } ?? model.name)
        .contextMenu {
            newSetupMenu(for: model.id)
            Divider()
            Button(role: .destructive) {
                onDeleteStepModel?(model.id)
            } label: {
                Label("Delete Object", systemImage: "trash")
            }
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
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
                Text(setup.displayTitle)
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

    /// The selected objects that can be combined: 2D shapes, not the alignment pins.
    private var combinableSelection: [UUID] {
        regularShapes.filter { selectedIDs.contains($0.id) }.map(\.id)
    }

    /// "Combine Selected into One Setup" with a face to pick; only with two or more objects selected.
    @ViewBuilder
    private var combineMenu: some View {
        let ids = combinableSelection
        if ids.count >= 2 {
            Menu {
                ForEach(setupFaceChoices, id: \.id) { choice in
                    Button(choice.title) {
                        onAddCombinedSetup?(ids, choice.face, choice.axis)
                    }
                }
            } label: {
                Label("Combine \(ids.count) Selected into One Setup", systemImage: "square.on.square")
            }
        }
    }

    /// "Add New Setup" with a face to pick. `objectID` nil makes a setup of every object.
    @ViewBuilder
    private func newSetupMenu(for objectID: UUID?) -> some View {
        Menu {
            ForEach(setupFaceChoices, id: \.id) { choice in
                Button(choice.title) {
                    onAddSetup?(objectID, choice.face, choice.axis)
                }
            }
        } label: {
            Label("Add New Setup", systemImage: "plus.square.on.square")
        }
    }
}
