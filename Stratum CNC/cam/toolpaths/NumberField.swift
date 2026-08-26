//
//  NumberField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.primary)

            HStack {
                TextField(
                    "",
                    value: $value,
                    format: .number
                )
                .textFieldStyle(.plain)

                Text(suffix)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct IntField: View {
    let title: String
    @Binding var value: Int
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.primary)

            HStack {
                TextField(
                    "",
                    value: $value,
                    format: .number
                )
                .textFieldStyle(.plain)

                Text(suffix)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
