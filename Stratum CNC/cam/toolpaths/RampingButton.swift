//
//  RampingButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct RampingButton: View {
    let ramping: RampingSettings
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {

            Text("RAMPING")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Button(action: action) {
                HStack(spacing: 5) {

                    Circle()
                        .fill(
                            ramping.enabled
                            ? .green
                            : .secondary
                        )
                        .frame(width: 7, height: 7)

                    Text(
                        ramping.enabled
                        ? ramping.type.rawValue
                        : "Off"
                    )
                    .font(.system(size: 12, weight: .medium))

                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
    }
}
