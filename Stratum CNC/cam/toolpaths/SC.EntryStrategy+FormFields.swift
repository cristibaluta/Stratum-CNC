//
//  SC.Entry.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC.EntryStrategy {

    /// Builds a variant field covering all four entry strategies. `onChange`
    /// receives the fully rebuilt `EntryStrategy` whenever the picked case,
    /// or one of that case's own parameters, changes. Reused by `.slotting`,
    /// `.contour`, `.pocket`, and `.counterbore` -- every case that has an
    /// `entry: EntryStrategy` parameter.
    public func formField(id: String = "entry",
                           label: String = "Entry Strategy",
                           onChange: @escaping (SC.EntryStrategy) -> Void) -> SC.ParameterField {

        // Ranges taken from the doc comments on EntryStrategy itself.
        let rampAngle: Double = { if case .ramp(let a) = self { return a } else { return 2.0 } }()
        let helixRadius: Double = { if case .helix(let r, _) = self { return r } else { return 1.0 } }()
        let helixAngle: Double = { if case .helix(_, let a) = self { return a } else { return 2.0 } }()
        let openEndStepover: Double = { if case .fromOpenEnd(let s) = self { return s } else { return 0.4 } }()

        let cases: [SC.ParameterField.VariantField.Case] = [
            .init(id: "plunge", label: "Plunge", fields: []),

            .init(id: "ramp", label: "Ramp", fields: [
                .double(.init(id: "\(id).ramp.angle", label: "Ramp Angle", unit: "°",
                              range: 1.0...5.0, value: rampAngle,
                              onChange: { onChange(.ramp(angleDegrees: $0)) }))
            ]),

            .init(id: "helix", label: "Helix", fields: [
                .double(.init(id: "\(id).helix.radius", label: "Helix Radius", unit: "mm",
                              range: 0.1...20.0, value: helixRadius,
                              onChange: { onChange(.helix(radius: $0, rampAngleDegrees: helixAngle)) })),
                .double(.init(id: "\(id).helix.angle", label: "Ramp Angle", unit: "°",
                              range: 1.5...3.0, value: helixAngle,
                              onChange: { onChange(.helix(radius: helixRadius, rampAngleDegrees: $0)) }))
            ]),

            .init(id: "fromOpenEnd", label: "From Open End", fields: [
                .double(.init(id: "\(id).fromOpenEnd.stepover", label: "Stepover", unit: "% of tool radius",
                              range: 0.0...1.0, value: openEndStepover,
                              onChange: { onChange(.fromOpenEnd(stepoverPercentage: $0)) }))
            ])
        ]

        let selectedId: String
        switch self {
            case .plunge: selectedId = "plunge"
            case .ramp: selectedId = "ramp"
            case .helix: selectedId = "helix"
            case .fromOpenEnd: selectedId = "fromOpenEnd"
        }

        return .variant(.init(id: id, label: label, cases: cases, selectedId: selectedId, onSelect: { newCaseId in
            switch newCaseId {
                case "plunge": onChange(.plunge)
                case "ramp": onChange(.ramp(angleDegrees: 2.0))
                case "helix": onChange(.helix(radius: 1.0, rampAngleDegrees: 2.0))
                case "fromOpenEnd": onChange(.fromOpenEnd(stepoverPercentage: 0.4))
                default: break
            }
        }))
    }
}
