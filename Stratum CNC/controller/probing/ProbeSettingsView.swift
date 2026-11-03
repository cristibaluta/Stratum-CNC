//
//  ProbeSettingsView.swift
//  Stratum CNC
//
//  The probing settings as a form. Shown in a popover from the dialog's
//  position step. `ProbeSettings` persists itself through `ControllerModel`.
//

import SwiftUI

struct ProbeSettingsView: View {

    @Binding var settings: ProbeSettings

    var body: some View {
        Form {
            Section("Safe position") {
                MeasurementField(title: "Safe Z above stock", value: $settings.safeZ, unit: "mm")
                Toggle("Park the probe when finished", isOn: $settings.usesParkPosition)
                if settings.usesParkPosition {
                    MeasurementField(title: "Park X (machine)", value: $settings.parkX, unit: "mm")
                    MeasurementField(title: "Park Y (machine)", value: $settings.parkY, unit: "mm")
                }
            }

            Section("Feed") {
                MeasurementField(title: "Search feed", value: $settings.searchFeed, unit: "mm/min")
                MeasurementField(title: "Measure feed", value: $settings.measureFeed, unit: "mm/min")
                Toggle("Touch twice (fast, then slow)", isOn: $settings.usesTwoPass)
            }

            Section("Distances") {
                MeasurementField(title: "Search distance", value: $settings.searchDistance, unit: "mm")
                MeasurementField(title: "Retract between touches", value: $settings.retractDistance, unit: "mm")
                MeasurementField(title: "Side depth below top", value: $settings.edgeDepth, unit: "mm")
                MeasurementField(title: "Start outside the edge by", value: $settings.outsideClearance, unit: "mm")
                MeasurementField(title: "Dot distance from the edge", value: $settings.startInset, unit: "mm")
            }

            Section("Probe") {
                MeasurementField(title: "Ball diameter", value: $settings.ballDiameter, unit: "mm")
                MeasurementField(title: "Z offset", value: $settings.zOffset, unit: "mm")
                LabeledContent("Tool number") {
                    HStack(spacing: 6) {
                        Text("T")
                            .foregroundStyle(.secondary)
                        Int2Field(value: $settings.probeTool)
                    }
                }
            }

            Section("Result") {
                Picker("Write the origin to", selection: $settings.workCoordinateSystem) {
                    ForEach(1...6, id: \.self) { index in
                        Text("G\(53 + index)").tag(index)
                    }
                }
                Toggle("Set Z as well", isOn: $settings.setsZ)
            }

            ForEach(settings.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Reset to Defaults") {
                settings = ProbeSettings()
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 520)
    }
}
