//
//  ZField.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ZField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                TextField(
                    "",
                    value: $value,
                    format: .number.precision(.fractionLength(2))
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)

                Text("mm")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
