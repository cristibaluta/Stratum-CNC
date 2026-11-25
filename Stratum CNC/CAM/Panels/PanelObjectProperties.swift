//
//  PanelObjectProperties.swift
//  Stratum CNC
//
//  The selected object's properties: face up, position, size (or the alignment pins' numbers),
//  in a panel of its own on the right. Split out of `PanelObjectsInspector`, which lists the
//  objects and their setups.
//

import SwiftUI

enum ObjectProperty: String {
    case x
    case y
    case width
    case height
    case rotation
}

enum STEPModelAxis {
    case x, y, z
}

struct PanelObjectProperties: View {

    let elements: [D2_Object]
    let selectedIDs: Set<UUID>
    /// The bounds of all selected objects together; what the group's X, Y and Width show.
    var selectionBounds: CGRect?

    var onValueChanged: ((UUID, ObjectProperty, CGFloat) -> Void)?
    var onNudge: ((UUID, ObjectProperty, CGFloat) -> Void)?
    var onScale: ((UUID, Int) -> Void)?
    var onRotate: ((UUID, CGFloat) -> Void)?
    /// Edits of several selected objects at once: they move and scale as a group.
    var onGroupValueChanged: ((ObjectProperty, CGFloat) -> Void)?
    var onGroupNudge: ((ObjectProperty, CGFloat) -> Void)?
    var onGroupScale: ((Int) -> Void)?
    /// The STEP model whose fields show, when no 2D object is selected.
    var stepModels: [STEPModelItem] = []
    var selectedStepModelID: UUID?
    var onStepModelValueChanged: ((UUID, STEPModelAxis, CGFloat) -> Void)?
    var onStepModelNudge: ((UUID, STEPModelAxis, CGFloat) -> Void)?
    var onStepModelOrientationChanged: ((UUID, SetupFace) -> Void)?
    /// The width field was edited: the body is scaled to that width.
    var onStepModelWidthChanged: ((UUID, CGFloat) -> Void)?
    /// ÷2 / ×2, like the 2D objects: a factor of -2 or 2.
    var onStepModelScale: ((UUID, Int) -> Void)?

    /// Objects the active setup places itself. Others use the project's (global) placement.
    var overriddenObjectIDs: Set<UUID> = []
    /// The Position panel offers "Project / This setup" only when there is more than one setup.
    var offersPlacementScope = false
    /// (object, true) = place it in this setup only; (object, false) = back to the global placement.
    var onPlacementOverrideChanged: ((UUID, Bool) -> Void)?

    // MARK: - Body

    @ViewBuilder
    var body: some View {
        let selected = elements.filter { selectedIDs.contains($0.id) }
        if selected.isEmpty, let model = stepModels.first(where: { $0.id == selectedStepModelID }) {
            propertiesChrome(title: model.position != nil ? "Object Properties" : nil) {
                stepModelPropertiesSection(for: model)
            }
        } else if selected.count == 1, let object = selected.first {
            propertiesChrome(title: object.alignmentPins == nil ? "Object Properties" : "Fixture") {
                if let spec = object.alignmentPins {
                    alignmentPinsSection(for: object, spec: spec)
                } else {
                    propertiesSection(for: object)
                }
            }
        } else if selected.count > 1, let bounds = selectionBounds {
            propertiesChrome(title: "Object Properties") {
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

                Divider()
                    .padding(.vertical, 8)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
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
                        valueRow("Width (X)", value: CGFloat(size.x), unit: "mm") {
                            onStepModelWidthChanged?(model.id, $0)
                        } trailing: {
                            SmallButton("÷2") { onStepModelScale?(model.id, -2) }
                            SmallButton("×2") { onStepModelScale?(model.id, 2) }
                        }
                        // Depth and height follow the width: the body is scaled as a whole.
                        readOnlyRow("Height (Y)", size.y)
                        readOnlyRow("Depth (Z)", size.z)
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
        InspectorRow(label: title) {
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

    /// A fixture has no position or size, and is not edited here: it belongs to a stock, and its two
    /// numbers are in the details of the setups cut from that stock.
    private func alignmentPinsSection(for object: D2_Object, spec: AlignmentPinsSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(object.name)
                .font(.system(size: 12))
            Text("Alignment pins: \(NumberField2.format(CGFloat(spec.diameter))) mm diameter, \(NumberField2.format(CGFloat(spec.offset))) mm from the stock's edges.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("They are a fixture of the stock. Change them in the setup's details.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func propertiesSection(for object: D2_Object) -> some View {
        // In "This setup" only the position is the setup's; size and rotation stay the project's
        let isPositionOnly = overriddenObjectIDs.contains(object.id)
        return VStack(alignment: .leading, spacing: 0) {
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
                .disabled(isPositionOnly)
            }
            InspectorSection(title: "Size") {
                valueRow("Width", value: object.width, unit: "mm") {
                    onValueChanged?(object.id, .width, $0)
                } trailing: {
                    SmallButton("÷2") { onScale?(object.id, -2) }
                    SmallButton("×2") { onScale?(object.id, 2) }
                }
                .disabled(isPositionOnly)
                // Height follows the width, so it is shown but can't be edited on its own.
                InspectorRow(label: "Height") {
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
                Text("Only the position is set per setup. Size and rotation are the project's.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                InspectorRow(label: "Height") {
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
        InspectorRow(label: title) {
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
