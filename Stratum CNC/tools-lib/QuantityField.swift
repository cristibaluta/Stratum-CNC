//
//  QuantityField.swift
//  Stratum CNC
//
//  Quantity row for the tool and stock editors: a number field between two large − / + buttons,
//  instead of the system stepper whose arrows are too small to hit comfortably.
//

import SwiftUI

struct QuantityField: View {

    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                stepButton(systemImage: "minus", delta: -1)
                    .disabled(value <= range.lowerBound)

                TextField(title, value: $value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .onChange(of: value) {
                        // Typed values outside the range snap back.
                        let clamped = min(max(value, range.lowerBound), range.upperBound)
                        if clamped != value {
                            value = clamped
                        }
                    }

                stepButton(systemImage: "plus", delta: 1)
                    .disabled(value >= range.upperBound)
            }
        }
    }

    private func stepButton(systemImage: String, delta: Int) -> some View {
        Button {
            value = min(max(value + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(delta < 0 ? "Decrease \(title)" : "Increase \(title)")
    }
}
