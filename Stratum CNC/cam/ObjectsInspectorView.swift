//
//  ObjectsInspectorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 03/09/2026.
//

import SwiftUI

enum Property: String {
    case x
    case y
    case width
    case height
    case rotation
}

struct ObjectsInspectorView: View {

    let elements: [D2_Object]
    let selectedID: UUID?

    var onSelectionChanged: ((UUID) -> Void)?
    var onValueChanged: ((UUID, Property, CGFloat) -> Void)?
    var onNudge: ((UUID, Property, CGFloat) -> Void)?
    var onScale: ((UUID, Int) -> Void)?
    var onRotate: ((UUID, CGFloat) -> Void)?
    var onAddNew: (() -> Void)?
    var onDelete: ((UUID) -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            objectsSection
            Divider()
            propertiesSection
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Objects

    private var objectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Objects")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button {
                    onAddNew?()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if elements.isEmpty {
                Text("No SVG objects")
                    .foregroundStyle(.secondary)
                    .font(.callout)
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
        Button {
            onSelectionChanged?(object.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: object.id == selectedID
                      ? "checkmark.circle.fill"
                      : "circle")
                .foregroundStyle(object.id == selectedID ? .red : .secondary)

                Text(object.name)
                    .lineLimit(1)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(object.id == selectedID ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Properties

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties")
                .font(.system(size: 13, weight: .bold))

            if let selectedID,
               let object = elements.first(where: { $0.id == selectedID }) {

                positionRow(title: "X", value: object.position.x, property: .x, id: object.id)
                positionRow(title: "Y", value: object.position.y, property: .y, id: object.id)
                scaleRow(title: "Width", value: object.width, id: object.id)
                heightRow(title: "Height", value: object.height, id: object.id)
                rotationRow(value: object.rotationDegrees, id: object.id)

            } else {
                Text("Select an object")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    // MARK: - Position

    private func positionRow(title: String, value: CGFloat, property: Property, id: UUID) -> some View {
        HStack(spacing: 4) {
            rowLabel(title)

            NumberField2(value: value) { newValue in
                onValueChanged?(id, property, newValue)
            }

            Text("mm")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            SmallButton("−1") {
                onNudge?(id, property, -1)
            }
            SmallButton("+1") {
                onNudge?(id, property, 1)
            }
        }
    }

    // MARK: - Width

    private func scaleRow(title: String, value: CGFloat, id: UUID) -> some View {
        HStack(spacing: 4) {
            rowLabel(title)

            NumberField2(value: value) { newValue in
                onValueChanged?(id, .width, newValue)
            }

            Text("mm")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            SmallButton("÷2") {
                onScale?(id, -2)
            }
            SmallButton("×2") {
                onScale?(id, 2)
            }
        }
    }

    // MARK: - Height

    private func heightRow(title: String, value: CGFloat, id: UUID) -> some View {
        HStack(spacing: 4) {
            rowLabel(title)

            NumberField2(value: value) { newValue in
                onValueChanged?(id, .height, newValue)
            }

            Text("mm")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            Text("🔒")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rotation

    private func rotationRow(value: CGFloat, id: UUID) -> some View {
        HStack(spacing: 4) {
            rowLabel("Rotation")

            NumberField2(value: value) { newValue in
                onValueChanged?(id, .rotation, newValue)
            }
            SmallButton("−90°") {
                // Preserving your original canvas rotation direction.
                onRotate?(id, 90)
            }
            SmallButton("+90°") {
                // Preserving your original canvas rotation direction.
                onRotate?(id, -90)
            }
        }
    }

    // MARK: - Helpers

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: 50, alignment: .trailing)
    }
}

private struct NumberField2: View {
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
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
            .onSubmit {
                commit()
            }
            .onChange(of: value) { _, newValue in
                text = Self.format(newValue)
            }
    }

    private func commit() {
        guard let number = Double(text) else {
            text = Self.format(value)
            return
        }

        let newValue = CGFloat(number)
        onCommit(newValue)
        text = Self.format(newValue)
    }

    private static func format(_ value: CGFloat) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }

        return String(
            format: "%.3f",
            locale: Locale.current,
            Double(value)
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
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
        Button(title, action: action)
            .controlSize(.small)
    }
}
