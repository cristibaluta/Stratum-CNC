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

/// The list of imported objects (2D shapes and STEP models). The fixtures are not objects of the
/// project: they belong to the stocks and are in the setup's details. The setups are `PanelSetups`;
/// the selected object's placement (position, size, face up) is `PanelObjectProperties`.
struct PanelObjectsInspector: View {

    let elements: [D2_Object]
    let selectedIDs: Set<UUID>

    /// The object clicked, and whether to add it to / remove it from the selection (Shift
    /// or Cmd held) instead of replacing the selection.
    var onSelectionChanged: ((UUID, Bool) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    /// "Import 2D/3D objects…" in the + menu: opens the file picker.
    var onAddNew: (() -> Void)?

    /// Drawn as a section of `PanelProject`: no card of its own.
    var embedded = false

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

    /// The focused object: its row is highlighted (its face up, position and size are in the right-hand panel).
    var focusedObjectID: UUID?
    /// A plain click on an object's row: focuses it and opens its first setup.
    var onSelectObject: ((UUID) -> Void)?
    /// The pencil / hover button: opens the object's properties panel.
    var onEditObject: ((UUID) -> Void)?
    /// A setup is the selection (and not an object): only one of the two is highlighted.
    var isSetupSelected = false

    /// The horizontal padding of a list row (`inspectorListRow`).
    private static let rowInset: CGFloat = 6
    /// How far the rows sit in from the section header (the chevron's width)
    private static let indent: CGFloat = 18

    /// The object row under the pointer, which shows its pencil
    @State private var hoveredRowID: UUID?
    /// "Add Setup" in an object's context menu: a new setup on a face for that object.
    var onAddSetup: ((UUID, SetupFace, SetupAxis?) -> Void)?
    /// Front, back, left and right need a 3D model.
    var sideFacesAvailable = false

    // MARK: - Body

    var body: some View {
        listPanel
    }

    // MARK: - List panel (left side)

    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                objectsSection
                    .padding(.top, 4)
            }
        }
        .modifier(PanelCardChrome(isCard: !embedded))
    }

    // MARK: - Header

    /// The chevron, the title and how many objects there are; the + is at the top right. The
    /// chevron, title and count toggle the panel.
    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    InspectorChevron(isExpanded: isExpanded)

                    Text("Objects")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    let count = regularShapes.count + stepModels.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide objects" : "Show objects")

            addMenu
        }
    }

    /// The + at the top right: import 2D/3D objects.
    private var addMenu: some View {
        Button {
            onAddNew?()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .padding(3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Import objects\nSupported files: SVG and DXF (2D), STEP / STP and STL (3D), and ZIP archives with Gerber / Excellon files")
    }

    // MARK: - Objects

    private var objectsSection: some View {
        Group {
            if regularShapes.isEmpty && stepModels.isEmpty {
                Text("No object imported!")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    objectList
                }
                // Rows pad their content by 6: grow them outward by as much, then indent
                // them under the header's chevron
                .padding(.leading, Self.indent - Self.rowInset)
                .padding(.trailing, -Self.rowInset)
            }
        }
    }

    // MARK: - List

    /// The imported shapes: the fixtures of the stocks are canvas objects too, but not listed here.
    private var regularShapes: [D2_Object] {
        elements.filter { !$0.isParametric }
    }

    @ViewBuilder
    private var objectList: some View {
        ForEach(regularShapes, id: \.id) { object in
            objectRow(object)
        }
        ForEach(stepModels) { model in
            stepModelRow(model)
        }
    }

    /// A row is highlighted when it is the focused object (unless a setup is the selection), or
    /// when several objects are selected.
    private func isRowSelected(_ id: UUID) -> Bool {
        // Only what is selected on the canvas: clicking empty space clears it
        selectedIDs.contains(id) || selectedStepModelID == id
    }

    /// "Add Setup" submenu: each face, with the bottom split by the axis it is flipped on.
    private func addSetupMenu(for id: UUID) -> some View {
        Menu {
            ForEach(SetupFace.allCases.filter { !$0.isSide || sideFacesAvailable }, id: \.rawValue) { face in
                if face.hasChoiceOfAxis {
                    ForEach(SetupAxis.allCases, id: \.rawValue) { axis in
                        Button("\(face.title) (flip on \(axis.title))") {
                            onAddSetup?(id, face, axis)
                        }
                    }
                } else {
                    Button(face.title) {
                        onAddSetup?(id, face, nil)
                    }
                }
            }
        } label: {
            Label("Add Setup", systemImage: "plus.square.on.square")
        }
    }

    private func editButton(for id: UUID, name: String) -> some View {
        Button {
            onEditObject?(id)
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .medium))
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .opacity(hoveredRowID == id ? 1 : 0)
        .help("Edit \(name)")
    }

    private func objectRow(_ object: D2_Object) -> some View {
        HStack(spacing: 4) {
            InspectorVisibilityButton(isVisible: object.isVisible,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(object.id)
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
                    Text(object.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .opacity(object.isVisible ? 1 : 0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            editButton(for: object.id, name: object.name)
        }
        .inspectorListRow(isSelected: isRowSelected(object.id))
        .onHover { inside in
            if inside {
                hoveredRowID = object.id
            } else if hoveredRowID == object.id {
                hoveredRowID = nil
            }
        }
        .contextMenu {
            Button {
                onEditObject?(object.id)
            } label: {
                Label("Edit…", systemImage: "slider.horizontal.3")
            }
            Button {
                onGeneratePreview?(object.id)
            } label: {
                Label("Generate Project Preview", systemImage: "photo")
            }
            addSetupMenu(for: object.id)
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
            InspectorVisibilityButton(isVisible: model.isVisible,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleStepModelVisibility?(model.id)
            }

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

            editButton(for: model.id, name: model.name)
        }
        .inspectorListRow(isSelected: isRowSelected(model.id))
        .onHover { inside in
            if inside {
                hoveredRowID = model.id
            } else if hoveredRowID == model.id {
                hoveredRowID = nil
            }
        }
        .help(model.detail.map { "\(model.name) — \($0)" } ?? model.name)
        .contextMenu {
            Button {
                onEditObject?(model.id)
            } label: {
                Label("Edit…", systemImage: "slider.horizontal.3")
            }
            addSetupMenu(for: model.id)
            Divider()
            Button(role: .destructive) {
                onDeleteStepModel?(model.id)
            } label: {
                Label("Delete Object", systemImage: "trash")
            }
        }
    }
}
