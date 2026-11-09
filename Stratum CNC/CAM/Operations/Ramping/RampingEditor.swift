//
// RampingEditor.swift
// Stratum CNC
//
// Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// The popover behind the Entry strategy row: the strategy picker (animated previews) on top,
/// then a drawing of the entry that follows the settings, and the fields. Same layout as `LeadInOutEditor`.
struct RampingEditor: View {

    @Binding var ramping: RampingSettings
    /// The feed rate of the entry move (the toolpath's plunge rate).
    @Binding var feedRate: Double
    let stepdown: Double
    let toolDiameter: Double
    /// The ramp types the operation accepts, in the order they are offered.
    var available: [RampType] = RampType.allCases
    @State private var helixDirection: HelixDirection = .outsideIn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RampTypeSelector(type: strategy,
                             angle: ramping.angle,
                             length: displayedLength,
                             stepdown: stepdown,
                             helixDirection: helixDirection,
                             selectable: available)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            EntryDiagram(type: ramping.type,
                         angle: ramping.angle,
                         stepdown: stepdown,
                         toolDiameter: toolDiameter)

            Text(strategyExplanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                if ramping.type != .none {
                    InspectorNumberField(title: "Entry angle", value: $ramping.angle, suffix: "°")
                        .help("How steeply the tool goes down, measured from the surface.")
                }
                if ramping.type == .helix {
                    InspectorRow(label: "Spiral") {
                        Picker("", selection: $helixDirection) {
                            ForEach(HelixDirection.allCases) { direction in
                                Text(direction.rawValue).tag(direction)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                InspectorNumberField(title: "Entry feed", value: $feedRate, suffix: "mm/min")
                    .help("Feed rate going down into the material.")
                if let note = angleNote {
                    InspectorNote(text: note, isIndented: false)
                }
            }
        }
        .padding(16)
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
    }

    // MARK: Bindings

    /// Picking a strategy also switches the entry on: the generator ignores the type while
    /// `enabled` is off, so a pick has to turn it back on.
    private var strategy: Binding<RampType> {
        Binding(
            get: { ramping.enabled ? ramping.type : .none },
            set: { newType in
                ramping.type = newType
                ramping.enabled = true
            }
        )
    }

    /// What the selector's previews receive as "length": the stored ramp length for a linear
    /// ramp, the tool-derived diameter for a helix.
    private var displayedLength: Double {
        ramping.type == .helix ? RampMath.helixDiameter(toolDiameter: toolDiameter) : ramping.length
    }

    // MARK: Copy

    private var strategyExplanation: String {
        switch ramping.type {
            case .none:   return "Straight down at 90°."
            case .linear: return "Down a slope, out and back along the same line."
            case .helix:  return "Spirals down in a circle as wide as the tool."
        }
    }

    /// Only the helix has a figure worth stating: the drawing already measures the ramp's run.
    private var angleNote: String? {
        guard ramping.type == .helix else {
            return nil
        }
        let diameter = RampMath.helixDiameter(toolDiameter: toolDiameter)
        let turns = RampMath.helixTurnsNeeded(angle: ramping.angle, diameter: diameter, stepdown: stepdown)
        return "About \(Self.format(turns)) turns, \(Self.format(diameter)) mm wide."
    }

    // MARK: Linear ramp length

    /// The stored length follows the angle and the stepdown, it is not typed.
    private func syncLinearRampLength() {
        guard ramping.type == .linear else {
            return
        }
        ramping.length = RampMath.linearRequiredLength(angle: ramping.angle, stepdown: stepdown)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }
}
