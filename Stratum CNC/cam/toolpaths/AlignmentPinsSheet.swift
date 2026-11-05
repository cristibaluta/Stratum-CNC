//
//  AlignmentPinsSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 05.11.2026.
//
//
//  The dialog behind "Create alignment pins" in the objects panel's + menu.
//

import SwiftUI

struct AlignmentPinsSheet: View {

    let stock: StockMaterial?
    /// (diameter, distance from the corner), both in mm.
    let onCreate: (Double, Double) -> Void
    let onCancel: () -> Void

    @State private var diameter: Double = 6
    @State private var inset: Double = 10

    private var problem: String? {
        do {
            _ = try AlignmentPins.centers(on: stock, diameter: diameter, inset: inset)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create alignment pins")
                .font(.headline)

            Text("Four pins, one in each corner of the stock, to line it up again when it is flipped over.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Pin diameter")
                    field($diameter)
                }
                GridRow {
                    Text("Distance from the corner")
                    field($inset)
                }
            }
            .font(.system(size: 12))

            Text("Measured from each of the two stock edges to the pin's centre.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onCreate(diameter, inset)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func field(_ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("mm")
                .foregroundStyle(.secondary)
        }
    }
}
