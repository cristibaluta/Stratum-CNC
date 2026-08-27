//
//  MeasurementField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct MeasurementField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(
                    "",
                    value: $value,
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 80, maxWidth: 120)

                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 55, alignment: .leading)
            }
        }
    }
}

struct OptionalMeasurementField: View {
    let title: String
    @Binding var value: Double?
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(
                    "",
                    value: Binding(
                        get: { value ?? 0 },
                        set: { value = $0 }
                    ),
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 80, maxWidth: 120)

                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 55, alignment: .leading)
            }
        }
    }
}
