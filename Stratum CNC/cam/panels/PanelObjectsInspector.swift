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
    var onAddNew: (() -> Void)?
    var onDelete: ((UUID) -> Void)?
    /// Right-click "Generate Project Preview": the project card's picture is made from this object alone.
    var onGeneratePreview: ((UUID) -> Void)?

    /// Narrow, left-aligned label column: leaves the width to the fields.
    private static let labelWidth: CGFloat = 56

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorHeader(title: "Objects", addHelp: "Import an object") {
                onAddNew?()
            }
            .padding(.bottom, 8)

            Divider()
                .padding(.bottom, 8)

            objectsSection

            let selected = elements.filter { selectedIDs.contains($0.id) }
            if selected.count == 1, let object = selected.first {
                propertiesSection(for: object)
                    .padding(.top, 10)
            } else if selected.count > 1, let bounds = selectionBounds {
                groupPropertiesSection(count: selected.count, bounds: bounds)
                    .padding(.top, 10)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Objects

    private var objectsSection: some View {
        Group {
            if elements.isEmpty {
                Text("No object imported!")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(elements, id: \.id) { object in
                        objectRow(object)
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
                Text(object.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .opacity(object.isVisible ? 1 : 0.5)
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

    // MARK: - Properties

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
