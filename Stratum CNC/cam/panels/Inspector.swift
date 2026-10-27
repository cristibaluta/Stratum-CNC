//
//  Inspector.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 27.10.2026.
//


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

struct InspectorNumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        InspectorRow(label: title) {
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