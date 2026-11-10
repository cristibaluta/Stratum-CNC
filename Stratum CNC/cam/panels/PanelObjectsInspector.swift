//
//  ObjectsInspectorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 03/09/2026.
//

import SwiftUI
import AppKit

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
    var onDeleteStepModel: ((UUID) -> Void)?

    /// Narrow, left-aligned label column: leaves the width to the fields.
    private static let labelWidth: CGFloat = 56

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)

            Divider()
                .padding(.bottom, 8)

            objectsSection

            let selected = elements.filter { selectedIDs.contains($0.id) }
            if selected.isEmpty, let model = stepModels.first(where: { $0.id == selectedStepModelID }) {
                stepModelPropertiesSection(for: model)
                    .padding(.top, 10)
            } else if selected.count == 1, let object = selected.first {
                if let spec = object.alignmentPins {
                    alignmentPinsSection(for: object, spec: spec)
                        .padding(.top, 10)
                } else {
                    propertiesSection(for: object)
                        .padding(.top, 10)
                }
            } else if selected.count > 1, let bounds = selectionBounds {
                groupPropertiesSection(count: selected.count, bounds: bounds)
                    .padding(.top, 10)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
    }

    // MARK: - Header

    /// Same look as `InspectorHeader`, but the + opens a menu instead of acting at once.
    private var header: some View {
        HStack {
            Text("Objects")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

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
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .padding(3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Add objects")
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
                    ForEach(elements, id: \.id) { object in
                        objectRow(object)
                    }
                    ForEach(stepModels) { model in
                        stepModelRow(model)
                    }
                }
            }
        }
    }

    private func objectRow(_ object: D2_Object) -> some View {
        HStack(spacing: 8) {
            Button {
                let flags = NSEvent.modifierFlags
                onSelectionChanged?(object.id, flags.contains(.shift) || flags.contains(.command))
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
        .inspectorListRow(isSelected: selectedIDs.contains(object.id))
        .contextMenu {
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
        HStack(spacing: 8) {
            Button {
                onSelectStepModel?(model.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cube")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(model.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(model.isVisible ? 1 : 0.5)
                }
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
        .inspectorListRow(isSelected: selectedStepModelID == model.id)
        .contextMenu {
            Button(role: .destructive) {
                onDeleteStepModel?(model.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Properties

    private func stepModelPropertiesSection(for model: STEPModelItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let position = model.position {
                if let orientation = model.orientation {
                    InspectorSection(title: "Face up") {
                        STEPFaceUpPicker(selection: orientation) { face in
                            onStepModelOrientationChanged?(model.id, face)
                        }
                    }
                }
                InspectorSection(title: "Position") {
                    stepAxisRow("X", model.id, .x, position.x)
                    stepAxisRow("Y", model.id, .y, position.y)
                    // The top of the model; 0 puts its top at the stock's top surface.
                    stepAxisRow("Z", model.id, .z, position.z)
                }
                if let size = model.size {
                    InspectorSection(title: "Size") {
                        readOnlyRow("Width", size.x)
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
            InspectorSection(title: "Alignment pins") {
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
            InspectorSection(title: "Position") {
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

    /// Several objects selected: they move and scale together. X, Y and Width describe the
    /// group's bounds; there is no rotation.
    private func groupPropertiesSection(count: Int, bounds: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection(title: "Position · \(count) objects") {
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

    init(
        _ title: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HoverChipButton(title: title, action: action)
    }
}
