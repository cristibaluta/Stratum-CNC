//
//  InspectorStyle.swift
//  Stratum CNC
//
//  The building blocks of the toolpath inspector, modelled on Xcode's right sidebar:
//  a section is a muted bold header with a hairline above it, and every setting is a row
//  with a right-aligned label on the left and its control on the right, all controls
//  starting on the same vertical edge.
//

import SwiftUI

enum Inspector {
    /// Width of the right-aligned label column.
    static let labelWidth: CGFloat = 92
    /// Gap between the label column and the control.
    static let columnSpacing: CGFloat = 10
    static let fieldHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 8
}

// MARK: - Section

/// A titled group of rows, separated from the previous one by a hairline.
struct InspectorSection<Content: View>: View {
    let title: String
    var showsDivider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Divider()
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Row

/// A label on the left, the control on the right.
struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: Inspector.columnSpacing) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: Inspector.labelWidth, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Inspector.fieldHeight)
    }
}

/// A small caption under a control, aligned with the control column.
struct InspectorNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Inspector.columnSpacing) {
            Color.clear
                .frame(width: Inspector.labelWidth, height: 0)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Field chrome

extension View {
    /// The soft gray rounded field every text field and pop-up button sits in.
    func inspectorField() -> some View {
        self
            .padding(.horizontal, 8)
            .frame(height: Inspector.fieldHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The face of a pop-up button: its content, then the up/down arrows.
struct InspectorMenuLabel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .inspectorField()
        .contentShape(Rectangle())
    }
}

// MARK: - Number fields

struct InspectorNumberField<Accessory: View>: View {
    let title: String
    @Binding var value: Double
    let suffix: String
    /// Optional control on the right of the field, on the same row (e.g. a helper button).
    let accessory: Accessory

    init(title: String, value: Binding<Double>, suffix: String,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self._value = value
        self.suffix = suffix
        self.accessory = accessory()
    }

    var body: some View {
        InspectorRow(label: title) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    TextField("", value: $value,
                              format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !suffix.isEmpty {
                        Text(suffix)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .inspectorField()

                accessory
            }
        }
    }
}

extension InspectorNumberField where Accessory == EmptyView {

    init(title: String, value: Binding<Double>, suffix: String) {
        self.init(title: title, value: value, suffix: suffix) {
            EmptyView()
        }
    }
}

struct InspectorIntField: View {
    let title: String
    @Binding var value: Int
    let suffix: String

    var body: some View {
        InspectorRow(label: title) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .inspectorField()
        }
    }
}

// MARK: - Panel header and list rows

/// A panel's title in the same muted bold as a section header, with an optional add button.
struct InspectorHeader: View {
    let title: String
    var addHelp: String = "Add"
    var onAdd: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(addHelp)
            }
        }
    }
}

extension View {
    /// The look of a row in a list: tight padding, accent wash while selected.
    func inspectorListRow(isSelected: Bool) -> some View {
        self
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The eye button at the start of a list row.
struct InspectorVisibilityButton: View {
    let isVisible: Bool
    let showHelp: String
    let hideHelp: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(.system(size: 12))
                .frame(width: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isVisible ? Color.secondary : Color.secondary.opacity(0.5))
        .help(isVisible ? hideHelp : showHelp)
    }
}
