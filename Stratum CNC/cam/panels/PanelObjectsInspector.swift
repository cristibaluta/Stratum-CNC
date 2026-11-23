//
//  ObjectsInspectorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 03/09/2026.
//

import SwiftUI

enum ObjectProperty: String {
    case x
    case y
    case width
    case height
    case rotation
}

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

enum STEPModelAxis {
    case x, y, z
}

struct PanelObjectsInspector: View {

    let elements: [D2_Object]
    let selectedIDs: Set<UUID>
    /// The bounds of all selected objects together; what the group's X, Y and Width show.
    var selectionBounds: CGRect?

    /// The object clicked, and whether to add it to / remove it from the selection (Shift
    /// or Cmd held) instead of replacing the selection.
    var onSelectionChanged: ((UUID, Bool) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onValueChanged: ((UUID, ObjectProperty, CGFloat) -> Void)?
    var onNudge: ((UUID, ObjectProperty, CGFloat) -> Void)?
    var onScale: ((UUID, Int) -> Void)?
    var onRotate: ((UUID, CGFloat) -> Void)?
    /// Edits of several selected objects at once: they move and scale as a group.
    var onGroupValueChanged: ((ObjectProperty, CGFloat) -> Void)?
    var onGroupNudge: ((ObjectProperty, CGFloat) -> Void)?
    var onGroupScale: ((Int) -> Void)?
    /// "Import 2D/3D objects…" in the + menu: opens the file picker.
    var onAddNew: (() -> Void)?
    /// "Create alignment pins…" in the + menu: opens the dialog.
    var onCreateAlignmentPins: (() -> Void)?
    /// The alignment pins' Diameter and Offset fields: (object, diameter, offset). Returns a message
    /// when the pins would not fit the stock; nothing changes then.
    var onAlignmentPinsChanged: ((UUID, Double, Double) -> String?)?

    /// Collapsed, the panel is one line (title and count). Clicking it opens the list.
    @State private var isExpanded = true

    @State private var pinsMessage: String?
    /// Bumped after each edit of the pins' fields, so a field shows what was really applied.
    @State private var pinsRefresh = 0
    var onDelete: ((UUID) -> Void)?
    /// Right-click "Generate Project Preview": the project card's picture is made from this object alone.
    var onGeneratePreview: ((UUID) -> Void)?

    /// STEP models are listed after the 2D objects. Selecting one shows its X, Y, Z.
    var stepModels: [STEPModelItem] = []
    var selectedStepModelID: UUID?
    var onSelectStepModel: ((UUID) -> Void)?
    var onToggleStepModelVisibility: ((UUID) -> Void)?
    var onStepModelValueChanged: ((UUID, STEPModelAxis, CGFloat) -> Void)?
    var onStepModelNudge: ((UUID, STEPModelAxis, CGFloat) -> Void)?
    var onStepModelOrientationChanged: ((UUID, SetupFace) -> Void)?
    /// The width field was edited: the body is scaled to that width.
    var onStepModelWidthChanged: ((UUID, CGFloat) -> Void)?
    /// ÷2 / ×2, like the 2D objects: a factor of -2 or 2.
    var onStepModelScale: ((UUID, Int) -> Void)?
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

    /// Objects the active setup places itself. Others use the project's (global) placement.
    var overriddenObjectIDs: Set<UUID> = []
    /// The Position panel offers "Project / This setup" only when there is more than one setup.
    var offersPlacementScope = false
    /// (object, true) = place it in this setup only; (object, false) = back to the global placement.
    var onPlacementOverrideChanged: ((UUID, Bool) -> Void)?

    /// The object whose setups are open; its face up, position and size are in the right-hand panel.
    var focusedObjectID: UUID?
    /// A plain click on an object's row: focuses it and opens its first setup.
    var onSelectObject: ((UUID) -> Void)?
    /// A setup is the selection (and not an object): only one of the two is highlighted.
    var isSetupSelected = false

    /// The same view is used twice: the list on the left, the selected object's properties on the right.
    enum Part {
        case list
        case properties
    }
    var part: Part = .list

    /// Objects whose setups are shown under them.
    @State private var expandedObjects: Set<UUID> = []

    /// Narrow, left-aligned label column: leaves the width to the fields.
    private static let labelWidth: CGFloat = 56
    /// The horizontal padding of a list row (`inspectorListRow`).
    private static let rowInset: CGFloat = 6

    // MARK: - Body

    var body: some View {
        switch part {
            case .list:
                listPanel
            case .properties:
                propertiesPanel
        }
    }

    // MARK: - Properties panel (right side)

    @ViewBuilder
    private var propertiesPanel: some View {
        let selected = elements.filter { selectedIDs.contains($0.id) }
        if selected.isEmpty, let model = stepModels.first(where: { $0.id == selectedStepModelID }) {
            propertiesChrome(title: model.position != nil ? "Placement" : nil) {
                stepModelPropertiesSection(for: model)
            }
        } else if selected.count == 1, let object = selected.first {
            propertiesChrome(title: object.alignmentPins == nil ? "Placement" : nil) {
                if let spec = object.alignmentPins {
                    alignmentPinsSection(for: object, spec: spec)
                } else {
                    propertiesSection(for: object)
                }
            }
        } else if selected.count > 1, let bounds = selectionBounds {
            propertiesChrome(title: "Placement") {
                groupPropertiesSection(count: selected.count, bounds: bounds)
            }
        }
    }

    private func propertiesChrome<Content: View>(title: String? = nil,
                                                 @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
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
                Label("Delete", systemImage: "trash")
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
                Label("Delete", systemImage: "trash")
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
                Label("Delete", systemImage: "trash")
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

    /// "New Setup" with a face to pick. `objectID` nil makes a setup of every object.
    @ViewBuilder
    private func newSetupMenu(for objectID: UUID?) -> some View {
        Menu {
            ForEach(setupFaceChoices, id: \.id) { choice in
                Button(choice.title) {
                    onAddSetup?(objectID, choice.face, choice.axis)
                }
            }
        } label: {
            Label("New Setup", systemImage: "plus.square.on.square")
        }
    }

    // MARK: - Properties

    private func stepModelPropertiesSection(for model: STEPModelItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let position = model.position {
                if let orientation = model.orientation {
                    InspectorSection(title: "Face up", showsDivider: false) {
                        STEPFaceUpPicker(selection: orientation) { face in
                            onStepModelOrientationChanged?(model.id, face)
                        }
                    }
                }
                InspectorSection(title: "Position", showsDivider: model.orientation != nil) {
                    stepAxisRow("X", model.id, .x, position.x)
                    stepAxisRow("Y", model.id, .y, position.y)
                    // The top of the model; 0 puts its top at the stock's top surface.
                    stepAxisRow("Z", model.id, .z, position.z)
                }
                if let size = model.size {
                    InspectorSection(title: "Size") {
                        valueRow("Width", value: CGFloat(size.x), unit: "mm") {
                            onStepModelWidthChanged?(model.id, $0)
                        } trailing: {
                            SmallButton("÷2") { onStepModelScale?(model.id, -2) }
                            SmallButton("×2") { onStepModelScale?(model.id, 2) }
                        }
                        // Depth and height follow the width: the body is scaled as a whole.
                        readOnlyRow("Depth", size.y)
                        readOnlyRow("Height", size.z)
                    }
                }
            } else {
                Text("The model is not loaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepAxisRow(_ title: String, _ id: UUID, _ axis: STEPModelAxis, _ value: Float) -> some View {
        valueRow(title, value: CGFloat(value), unit: "mm") {
            onStepModelValueChanged?(id, axis, $0)
        } trailing: {
            SmallButton("−1") { onStepModelNudge?(id, axis, -1) }
            SmallButton("+1") { onStepModelNudge?(id, axis, 1) }
        }
    }

    private func readOnlyRow(_ title: String, _ value: Float) -> some View {
        InspectorRow(label: title, labelWidth: Self.labelWidth, labelAlignment: .leading) {
            HStack(spacing: 6) {
                Text(NumberField2.format(CGFloat(value)))
                    .font(.system(size: 12))
                Text("mm")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .inspectorField()
        }
    }

    /// The alignment pins have no position or size: just the two numbers they are built from.
    private func alignmentPinsSection(for object: D2_Object, spec: AlignmentPinsSpec) -> some View {
        func apply(diameter: Double, offset: Double) {
            pinsMessage = onAlignmentPinsChanged?(object.id, diameter, offset)
            pinsRefresh += 1
        }
        return VStack(alignment: .leading, spacing: 0) {
            InspectorSection(title: "Alignment pins", showsDivider: false) {
                valueRow("Diameter", value: CGFloat(spec.diameter), unit: "mm") {
                    apply(diameter: Double($0), offset: spec.offset)
                } trailing: {
                    EmptyView()
                }
                valueRow("Offset", value: CGFloat(spec.offset), unit: "mm") {
                    apply(diameter: spec.diameter, offset: Double($0))
                } trailing: {
                    EmptyView()
                }
                Text("Offset is the distance from the stock margin to the centre of each pin. The pins follow the stock when its size changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let pinsMessage {
                    Text(pinsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(pinsRefresh)
        }
        .onChange(of: object.id) { _, _ in
            pinsMessage = nil
        }
    }

    private func propertiesSection(for object: D2_Object) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if offersPlacementScope {
                placementScopeSection(for: object)
            }
            InspectorSection(title: "Position", showsDivider: offersPlacementScope) {
                valueRow("X", value: object.position.x, unit: "mm") {
                    onValueChanged?(object.id, .x, $0)
                } trailing: {
                    SmallButton("−1") { onNudge?(object.id, .x, -1) }
                    SmallButton("+1") { onNudge?(object.id, .x, 1) }
                }
                valueRow("Y", value: object.position.y, unit: "mm") {
                    onValueChanged?(object.id, .y, $0)
                } trailing: {
                    SmallButton("−1") { onNudge?(object.id, .y, -1) }
                    SmallButton("+1") { onNudge?(object.id, .y, 1) }
                }
                valueRow("Rotation", value: object.rotationDegrees, unit: "°") {
                    onValueChanged?(object.id, .rotation, $0)
                } trailing: {
                    // Preserving the original canvas rotation direction.
                    SmallButton("−90°") { onRotate?(object.id, 90) }
                    SmallButton("+90°") { onRotate?(object.id, -90) }
                }
            }
            InspectorSection(title: "Size") {
                valueRow("Width", value: object.width, unit: "mm") {
                    onValueChanged?(object.id, .width, $0)
                } trailing: {
                    SmallButton("÷2") { onScale?(object.id, -2) }
                    SmallButton("×2") { onScale?(object.id, 2) }
                }
                // Height follows the width, so it is shown but can't be edited on its own.
                InspectorRow(label: "Height", labelWidth: Self.labelWidth, labelAlignment: .leading) {
                    HStack(spacing: 6) {
                        Text(NumberField2.format(object.height))
                            .font(.system(size: 12))
                        Text("mm")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "lock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .inspectorField()
                }
            }
        }
    }

    /// Whose placement the fields below edit: the project's, or this setup's own.
    private func placementScopeSection(for object: D2_Object) -> some View {
        let isOverridden = overriddenObjectIDs.contains(object.id)
        return InspectorSection(title: nil, showsDivider: false) {
            Picker("", selection: Binding(get: { isOverridden },
                                          set: { onPlacementOverrideChanged?(object.id, $0) })) {
                Text("Project").tag(false)
                Text("This setup").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if isOverridden {
                Button("Reset to global") {
                    onPlacementOverrideChanged?(object.id, false)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    /// Several objects selected: they move and scale together. X, Y and Width describe the
    /// group's bounds; there is no rotation.
    private func groupPropertiesSection(count: Int, bounds: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection(title: "Position · \(count) objects", showsDivider: false) {
                valueRow("X", value: bounds.minX, unit: "mm") {
                    onGroupValueChanged?(.x, $0)
                } trailing: {
                    SmallButton("−1") { onGroupNudge?(.x, -1) }
                    SmallButton("+1") { onGroupNudge?(.x, 1) }
                }
                valueRow("Y", value: bounds.minY, unit: "mm") {
                    onGroupValueChanged?(.y, $0)
                } trailing: {
                    SmallButton("−1") { onGroupNudge?(.y, -1) }
                    SmallButton("+1") { onGroupNudge?(.y, 1) }
                }
            }
            InspectorSection(title: "Size") {
                valueRow("Width", value: bounds.width, unit: "mm") {
                    onGroupValueChanged?(.width, $0)
                } trailing: {
                    SmallButton("÷2") { onGroupScale?(-2) }
                    SmallButton("×2") { onGroupScale?(2) }
                }
                InspectorRow(label: "Height", labelWidth: Self.labelWidth, labelAlignment: .leading) {
                    HStack(spacing: 6) {
                        Text(NumberField2.format(bounds.height))
                            .font(.system(size: 12))
                        Text("mm")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "lock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .inspectorField()
                }
            }
        }
    }

    /// A labelled number field with its unit inside, and a few small buttons after it.
    private func valueRow<Trailing: View>(_ title: String,
                                          value: CGFloat,
                                          unit: String,
                                          onCommit: @escaping (CGFloat) -> Void,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        InspectorRow(label: title, labelWidth: Self.labelWidth, labelAlignment: .leading) {
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    NumberField2(value: value, onCommit: onCommit)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .inspectorField()

                trailing()
            }
        }
    }
}

struct NumberField2: View {
    let value: CGFloat
    let onCommit: (CGFloat) -> Void

    @State private var text: String

    init(value: CGFloat, onCommit: @escaping (CGFloat) -> Void) {
        self.value = value
        self.onCommit = onCommit

        _text = State(
            initialValue: NumberField2.format(value)
        )
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .onSubmit {
                commit()
            }
            .onChange(of: value) { _, newValue in
                text = Self.format(newValue)
            }
    }

    private func commit() {
        guard let number = Double(text), number.isFinite else {
            text = Self.format(value)
            return
        }

        let newValue = CGFloat(number)
        onCommit(newValue)
        text = Self.format(newValue)
    }

    static func format(_ value: CGFloat) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
        }

        var text = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(value)
        )
        // Only trailing zeros and a dangling point go; trimming both ends ate the leading
        // "0" of values below 1 ("0.5" became "5").
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}


private struct SmallButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String,
         action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HoverChipButton(title: title, action: action)
    }
}
