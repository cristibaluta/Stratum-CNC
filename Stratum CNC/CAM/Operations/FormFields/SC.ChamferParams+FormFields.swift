//
//  SC.Chamfer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC.ChamferParams {

    /// The fields in the order the panel shows them: the bevel's width, whether the selected edge
    /// is its bottom edge, the tip offset, then the side and the direction (which the panel draws
    /// with controls of its own). The bevel's depth isn't a field: it always follows from the
    /// width and the V-bit's angle.
    public func formFields(idPrefix: String = "chamfer",
                            onChange: @escaping (SC.ChamferParams) -> Void) -> [SC.ParameterField] {

        // Every field hands back the whole value with just its own part changed, so editing one
        // never resets the others.
        func updated(_ change: (inout SC.ChamferParams) -> Void) -> SC.ChamferParams {
            var copy = self
            change(&copy)
            return copy
        }

        return [
            .double(.init(id: "\(idPrefix).width",
                          label: "Width",
                          unit: "mm",
                          range: 0.1...20.0,
                          value: width,
                          onChange: { value in onChange(updated { $0.width = value }) })),

            // Off: the selected edge is the bevel's top edge. On: it is the bottom edge (the wall).
            .bool(.init(id: "\(idPrefix).edge",
                        label: "Bottom edge",
                        value: edge == .bottom,
                        onChange: { isBottom in onChange(updated { $0.edge = isBottom ? .bottom : .top }) })),

            // Which part of the flank cuts the bevel, for wear compensation (see `ChamferParams.tipOffset`).
            .double(.init(id: "\(idPrefix).tipOffset",
                          label: "Tip offset",
                          unit: "mm",
                          range: 0...20.0,
                          value: tipOffset,
                          onChange: { value in onChange(updated { $0.tipOffset = value }) })),

            .choice(SC.cutSideChoice(id: "\(idPrefix).side",
                                     current: side,
                                     onChange: { value in onChange(updated { $0.side = value }) })),

            .choice(SC.cutDirectionChoice(id: "\(idPrefix).direction",
                                          current: direction,
                                          onChange: { value in onChange(updated { $0.direction = value }) }))
        ]
    }
}
