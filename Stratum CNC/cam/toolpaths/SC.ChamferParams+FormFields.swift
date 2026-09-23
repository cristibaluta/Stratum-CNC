//
//  SC.Chamfer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC.ChamferParams {

    public func formFields(idPrefix: String = "chamfer",
                            onChange: @escaping (SC.ChamferParams) -> Void) -> [SC.ParameterField] {
        [
            .double(.init(id: "\(idPrefix).width", label: "Width", unit: "mm",
                          range: 0.1...20.0, value: width,
                          onChange: { onChange(.init(width: $0, depth: depth, side: side, direction: direction)) })),

            // nil => depth is derived from width + the tool's V-bit angle (see resolvedDepth(for:)).
            .optionalDouble(.init(id: "\(idPrefix).depth", label: "Depth Override", unit: "mm",
                          range: 0.05...20.0, defaultValueWhenEnabled: 1.0,
                          value: depth,
                          onChange: { onChange(.init(width: width, depth: $0, side: side, direction: direction)) })),

            .choice(SC.cutSideChoice(id: "\(idPrefix).side", current: side,
                          onChange: { onChange(.init(width: width, depth: depth, side: $0, direction: direction)) })),

            .choice(SC.cutDirectionChoice(id: "\(idPrefix).direction", current: direction,
                          onChange: { onChange(.init(width: width, depth: depth, side: side, direction: $0)) }))
        ]
    }
}
