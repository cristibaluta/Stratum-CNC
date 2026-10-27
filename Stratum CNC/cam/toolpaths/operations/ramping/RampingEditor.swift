//
// RampingEditor.swift
// Stratum CNC
//
// Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct RampingEditor: View {

    @Binding var ramping: RampingSettings
    let stepdown: Double
    let toolDiameter: Double
    /// The ramp types the operation accepts, in the order they are offered.
    var available: [RampType] = RampType.allCases
    @State private var helixDirection: HelixDirection = .outsideIn

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            rampSelector
                .padding(.vertical, 10)
            rampVizualization
                .padding(.vertical, 10)
            if ramping.type != .none {
                rampParams
            }
        }
        .onAppear {
            syncLinearRampLength()
        }
        .onChange(of: ramping.type) { _, _ in
            syncLinearRampLength()
        }
        .onChange(of: ramping.angle) { _, _ in
            syncLinearRampLength()
        }
        .onChange(of: stepdown) { _, _ in
            syncLinearRampLength()
        }
        .padding(16)
    }

    private var rampSelector: some View {
        RampTypeSelector(type: $ramping.type,
                         angle: ramping.angle,
                         length: displayedLength,
                         stepdown: stepdown,
                         helixDirection: helixDirection,
                         selectable: available)
    }

    private var rampVizualization: some View {
        Group {
            RampVisualization(type: ramping.type,
                              angle: ramping.angle,
                              length: displayedLength,
                              stepdown: stepdown,
                              mode: .profileDetail,
                              helixDirection: helixDirection)
                .frame(height: RampGeometry.detailSize)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.rampCardBackground))
                )
                .animation(.easeInOut(duration: 0.2), value: ramping.type)

            if ramping.type == .helix {
                Picker("Spiral direction", selection: $helixDirection) {
                    ForEach(HelixDirection.allCases) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(rampDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

//            if !rampMetrics.isEmpty {
//                Text(rampMetrics)
//                    .font(.caption.monospacedDigit())
//                    .foregroundStyle(.secondary)
//            }
        }
    }

    private var rampParams: some View {
        Group {
            HStack {
                Text("Ramp angle")
                TextField("", value: $ramping.angle, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("°")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if ramping.type == .linear {
                HStack {
                    Text("Required ramp distance ")
                    Text(String(format: "%.2f mm", linearRampLength))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Calculated automatically from the angle and current stepdown. It is not editable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func syncLinearRampLength() {
        guard ramping.type == .linear else {
            return
        }
        ramping.length = linearRampLength
    }

    private var helixDiameter: Double {
        RampMath.helixDiameter(toolDiameter: toolDiameter)
    }

    /// What the drawings receive as "length": the stored ramp length for a
    /// linear ramp, the tool-derived diameter for a helix.
    private var displayedLength: Double {
        ramping.type == .helix ? helixDiameter : ramping.length
    }

    private var linearRampLength: Double {
        RampMath.linearRequiredLength(angle: ramping.angle, stepdown: stepdown)
    }

    private var rampDescription: String {
        switch ramping.type {
            case .none:
                return "The tool plunges vertically."
            case .linear:
                let result = RampMath.linearRampOutcome(angle: ramping.angle, length: ramping.length, stepdown: stepdown)
                if result.reachesStepdown {
                    return "The tool descends at \(String(format: "%.1f", ramping.angle))° over half of the ramp distance, then returns to the start point descending the rest of the way, reaching the \(String(format: "%.2f", stepdown)) mm stepdown. The distance is calculated automatically."
                } else {
                    return "⚠️ At this angle, \(String(format: "%.1f", ramping.length)) mm of ramp length only reaches \(String(format: "%.2f", result.depth)) mm — short of the \(String(format: "%.2f", stepdown)) mm stepdown. Increase length or use a shallower angle."
                }
            case .helix:
                switch helixDirection {
                    case .outsideIn:
                        return "The tool spirals downward from the outside edge inward, shown here from above."
                    case .insideOut:
                        return "The tool spirals downward from the center outward, shown here from above."
                }
        }
    }

    private var rampMetrics: String {
        switch ramping.type {
            case .linear:
                let result = RampMath.linearRampOutcome(angle: ramping.angle, length: ramping.length, stepdown: stepdown)
                if result.reachesStepdown {
                    return String(format: "Required distance: %.2f mm at %.1f°", result.usedLength, RampMath.clampedAngle(ramping.angle))
                } else {
                    return String(format: "Needs ≥ %.1f mm at this angle to reach stepdown", RampMath.linearRequiredLength(angle: ramping.angle, stepdown: stepdown))
                }
            case .helix:
                let turns = RampMath.helixTurnsNeeded(angle: ramping.angle, diameter: helixDiameter, stepdown: stepdown)
                return String(format: "%.1f turns to reach the %.2f mm stepdown", turns, stepdown)
            case .none:
                return ""
        }
    }

}
