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

/// A group (virtual object) as a row of the objects list.
struct GroupItem: Identifiable {
    let id: UUID
    let name: String
    let memberCount: Int
    /// The names of the members, shown as the row's tooltip
    var memberNames: [String] = []
    var memberIDs: [UUID] = []
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
    /// A setup is the selection (and not an object): only one of the two is highlighted.
    var isSetupSelected = false

    /// The horizontal padding of a list row (`inspectorListRow`).
    private static let rowInset: CGFloat = 6

    /// The groups (virtual objects): listed under the objects.
    var groups: [GroupItem] = []
    /// "New Group" in the + menu: groups the selected objects (an empty group when none is selected).
    var onCreateGroup: (() -> Void)?
    /// Right-click "Add to Group": the objects (the whole selection when the row is part of it) and the group.
    var onAddToGroup: (([UUID], UUID) -> Void)?
    var onRemoveFromGroup: (([UUID], UUID) -> Void)?
    /// A click on a group's row selects its members.
    var onSelectGroup: ((UUID) -> Void)?
    var onRenameGroup: ((UUID, String) -> Void)?
    /// "Ungroup": the group goes, its members stay.
    var onDeleteGroup: ((UUID) -> Void)?

    @State private var renamingGroupID: UUID?
    @State private var renameText = ""

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
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
        .alert("Rename Group", isPresented: Binding(get: { renamingGroupID != nil },
                                                    set: { if !$0 { renamingGroupID = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renamingGroupID {
                    onRenameGroup?(id, renameText)
                }
                renamingGroupID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingGroupID = nil
            }
        }
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

    /// The + at the top right: import 2D/3D objects, or make a group.
    private var addMenu: some View {
        Menu {
            Button {
                onAddNew?()
            } label: {
                Label("Import Objects…", systemImage: "square.and.arrow.down")
            }
            Button {
                onCreateGroup?()
            } label: {
                Label(selectedIDs.isEmpty ? "New Empty Group" : "New Group from \(selectedIDs.count) Selected",
                      systemImage: "square.on.square")
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
        .help("Import objects or create a group")
    }

    /// "Add to Group" and "Remove from …" for the objects a right-click is about.
    @ViewBuilder
    private func groupMenu(for ids: [UUID]) -> some View {
        if !groups.isEmpty {
            Menu {
                ForEach(groups) { group in
                    Button(group.name) {
                        onAddToGroup?(ids, group.id)
                    }
                    .disabled(ids.allSatisfy { group.memberIDs.contains($0) })
                }
            } label: {
                Label("Add to Group", systemImage: "plus.square.on.square")
            }
            ForEach(groups.filter { group in ids.contains { group.memberIDs.contains($0) } }) { group in
                Button {
                    onRemoveFromGroup?(ids, group.id)
                } label: {
                    Label("Remove from \(group.name)", systemImage: "minus.square")
                }
            }
        }
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
                // Rows pad their content by 6: grow them outward by as much, so the icons
                // line up with the header and the other elements
                .padding(.horizontal, -Self.rowInset)
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
        ForEach(groups) { group in
            groupRow(group)
        }
    }

    private func groupRow(_ group: GroupItem) -> some View {
        Button {
            onSelectGroup?(group.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(group.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(group.memberCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .inspectorListRow(isSelected: false)
        .help(group.memberNames.joined(separator: ", "))
        .contextMenu {
            Button {
                renameText = group.name
                renamingGroupID = group.id
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDeleteGroup?(group.id)
            } label: {
                Label("Ungroup", systemImage: "rectangle.3.group")
            }
        }
    }

    /// A row is highlighted when it is the focused object (unless a setup is the selection), or
    /// when several objects are selected.
    private func isRowSelected(_ id: UUID) -> Bool {
        if selectedIDs.count > 1 {
            return selectedIDs.contains(id)
        }
        return !isSetupSelected && focusedObjectID == id
    }

    private func objectRow(_ object: D2_Object) -> some View {
        HStack(spacing: 4) {
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

            InspectorVisibilityButton(isVisible: object.isVisible,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(object.id)
            }
        }
        .inspectorListRow(isSelected: isRowSelected(object.id))
        .contextMenu {
            Button {
                onGeneratePreview?(object.id)
            } label: {
                Label("Generate Project Preview", systemImage: "photo")
            }
            groupMenu(for: selectedIDs.count > 1 && selectedIDs.contains(object.id) ? Array(selectedIDs) : [object.id])
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
            groupMenu(for: [model.id])
            Divider()
            Button(role: .destructive) {
                onDeleteStepModel?(model.id)
            } label: {
                Label("Delete Object", systemImage: "trash")
            }
        }
    }
}
