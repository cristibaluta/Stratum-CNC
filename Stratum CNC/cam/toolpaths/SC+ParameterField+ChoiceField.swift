
//
//  SC.a.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

/// Shared `ChoiceField` builders for the no-payload enums (`CutDirection`,
/// `CutSide`, `ThreadDirection`, `SpiralDirection`), so every operation's
/// `formFields` reuses the same option list and labels instead of redefining
/// them per case.
extension SC {

    static func cutDirectionChoice(id: String,
                                    label: String = "Direction",
                                    current: CutDirection,
                                    onChange: @escaping (CutDirection) -> Void) -> ParameterField.ChoiceField {
        .init(id: id,
              label: label,
              options: [.init(id: CutDirection.climb.rawValue, label: "Climb"),
                        .init(id: CutDirection.conventional.rawValue, label: "Conventional")],
              selectedId: current.rawValue,
              onChange: { onChange(CutDirection(rawValue: $0) ?? current) })
    }

    static func cutSideChoice(id: String,
                               label: String = "Side",
                               current: CutSide,
                               onChange: @escaping (CutSide) -> Void) -> ParameterField.ChoiceField {
        .init(id: id,
              label: label,
              options: [.init(id: CutSide.inside.rawValue, label: "Inside"),
                        .init(id: CutSide.outside.rawValue, label: "Outside"),
                        .init(id: CutSide.onContour.rawValue, label: "On Contour")],
              selectedId: current.rawValue,
              onChange: { onChange(CutSide(rawValue: $0) ?? current) })
    }

    static func threadDirectionChoice(id: String,
                                       label: String = "Handedness",
                                       current: ThreadDirection,
                                       onChange: @escaping (ThreadDirection) -> Void) -> ParameterField.ChoiceField {
        .init(id: id,
              label: label,
              options: [.init(id: ThreadDirection.rightHand.rawValue, label: "Right-Hand"),
                        .init(id: ThreadDirection.leftHand.rawValue, label: "Left-Hand")],
              selectedId: current.rawValue,
              onChange: { onChange(ThreadDirection(rawValue: $0) ?? current) })
    }

    static func spiralDirectionChoice(id: String,
                                       label: String = "Spiral Direction",
                                       current: SpiralDirection,
                                       onChange: @escaping (SpiralDirection) -> Void) -> ParameterField.ChoiceField {
        .init(id: id,
              label: label,
              options: [.init(id: SpiralDirection.outsideIn.rawValue, label: "Outside → In"),
                        .init(id: SpiralDirection.insideOut.rawValue, label: "Inside → Out")],
              selectedId: current.rawValue,
              onChange: { onChange(SpiralDirection(rawValue: $0) ?? current) })
    }
}
