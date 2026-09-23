//
//  SC.LeadIn.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC.LeadInOut {

    /// Fields for an already-present `LeadInOut` -- a style variant plus its
    /// own feed rate. Wrapped in an `.optionalGroup` by the caller (`.contour`)
    /// since `leadIn`/`leadOut` can be entirely `nil`.
    public func formFields(idPrefix: String,
                            onChange: @escaping (SC.LeadInOut) -> Void) -> [SC.ParameterField] {

        let currentLength: Double = { if case .linear(let l) = style { return l } else { return 3.0 } }()
        let currentArcRadius: Double = { if case .arc(let r, _) = style { return r } else { return 3.0 } }()
        let currentArcSweep: Double = { if case .arc(_, let s) = style { return s } else { return 90.0 } }()

        let styleCases: [SC.ParameterField.VariantField.Case] = [
            .init(id: "linear", label: "Linear", fields: [
                .double(.init(id: "\(idPrefix).style.length", label: "Length", unit: "mm",
                              range: 0.1...20.0, value: currentLength,
                              onChange: { onChange(.init(style: .linear(length: $0), feedRate: feedRate)) }))
            ]),
            .init(id: "arc", label: "Arc", fields: [
                .double(.init(id: "\(idPrefix).style.radius", label: "Radius", unit: "mm",
                              range: 0.1...20.0, value: currentArcRadius,
                              onChange: { onChange(.init(style: .arc(radius: $0, sweepAngleDegrees: currentArcSweep), feedRate: feedRate)) })),
                .double(.init(id: "\(idPrefix).style.sweep", label: "Sweep Angle", unit: "°",
                              range: 1.0...180.0, value: currentArcSweep,
                              onChange: { onChange(.init(style: .arc(radius: currentArcRadius, sweepAngleDegrees: $0), feedRate: feedRate)) }))
            ])
        ]

        let selectedId: String
        switch style {
            case .linear: selectedId = "linear"
            case .arc: selectedId = "arc"
        }

        return [
            .variant(.init(id: "\(idPrefix).style", label: "Style", cases: styleCases, selectedId: selectedId, onSelect: { newId in
                switch newId {
                    case "linear": onChange(.init(style: .linear(length: 3.0), feedRate: feedRate))
                    case "arc": onChange(.init(style: .arc(radius: 3.0, sweepAngleDegrees: 90.0), feedRate: feedRate))
                    default: break
                }
            })),
            .double(.init(id: "\(idPrefix).feedRate", label: "Feed Rate", unit: "mm/min",
                          range: 50.0...3000.0, value: feedRate,
                          onChange: { onChange(.init(style: style, feedRate: $0)) }))
        ]
    }

    /// Builds the `.optionalGroup` field for a `LeadInOut?` -- used for both
    /// `leadIn` and `leadOut` on `.contour`. When absent, toggling it on seeds
    /// a default linear 3mm lead at 300mm/min.
    static func optionalFormField(idPrefix: String,
                                   label: String,
                                   current: SC.LeadInOut?,
                                   onChange: @escaping (SC.LeadInOut?) -> Void) -> SC.ParameterField {
        .optionalGroup(.init(
            id: idPrefix,
            label: label,
            isPresent: current != nil,
            fields: current?.formFields(idPrefix: idPrefix) { onChange($0) } ?? [],
            onToggle: { enabled in
                onChange(enabled ? SC.LeadInOut(style: .linear(length: 3.0), feedRate: 300.0) : nil)
            }
        ))
    }
}
