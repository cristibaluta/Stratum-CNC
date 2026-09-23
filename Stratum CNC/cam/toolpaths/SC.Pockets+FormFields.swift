//
//  SC.Adaptive+FormFields.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC.AdaptiveSettings {
    fileprivate func formFields(idPrefix: String,
                                 onChange: @escaping (SC.AdaptiveSettings) -> Void) -> [SC.ParameterField] {
        [
            .double(.init(id: "\(idPrefix).optimalLoad", label: "Optimal Load", unit: "mm",
                          range: 0.1...10.0, value: optimalLoad,
                          onChange: { onChange(.init(optimalLoad: $0)) }))
        ]
    }
}

extension SC.TrochoidalSettings {
    fileprivate func formFields(idPrefix: String,
                                 onChange: @escaping (SC.TrochoidalSettings) -> Void) -> [SC.ParameterField] {
        [
            .double(.init(id: "\(idPrefix).radialEngagement", label: "Radial Engagement", unit: "% of tool radius",
                          range: 0.0...1.0, value: radialEngagement,
                          onChange: { onChange(.init(radialEngagement: $0, loopRadius: loopRadius)) })),
            .double(.init(id: "\(idPrefix).loopRadius", label: "Loop Radius", unit: "mm",
                          range: 0.1...20.0, value: loopRadius,
                          onChange: { onChange(.init(radialEngagement: radialEngagement, loopRadius: $0)) }))
        ]
    }
}

extension SC.PocketClearingPattern {

    /// Variant field covering all five pocket clearing patterns.
    public func formField(id: String = "pattern",
                           label: String = "Clearing Pattern",
                           onChange: @escaping (SC.PocketClearingPattern) -> Void) -> SC.ParameterField {

        let currentSpiral: SC.SpiralDirection = { if case .spiral(let d) = self { return d } else { return .outsideIn } }()
        let currentTrochoidal: SC.TrochoidalSettings = { if case .trochoidal(let s) = self { return s } else { return .init(radialEngagement: 0.3, loopRadius: 1.0) } }()
        let currentAdaptive: SC.AdaptiveSettings = { if case .adaptive(let s) = self { return s } else { return .init(optimalLoad: 1.0) } }()

        let cases: [SC.ParameterField.VariantField.Case] = [
            .init(id: "offset", label: "Offset", fields: []),
            .init(id: "raster", label: "Raster", fields: []),
            .init(id: "spiral", label: "Spiral", fields: [
                .choice(SC.spiralDirectionChoice(id: "\(id).spiral.direction", current: currentSpiral,
                                                  onChange: { onChange(.spiral(direction: $0)) }))
            ]),
            .init(id: "trochoidal", label: "Trochoidal",
                  fields: currentTrochoidal.formFields(idPrefix: "\(id).trochoidal") { onChange(.trochoidal(settings: $0)) }),
            .init(id: "adaptive", label: "Adaptive",
                  fields: currentAdaptive.formFields(idPrefix: "\(id).adaptive") { onChange(.adaptive(settings: $0)) })
        ]

        let selectedId: String
        switch self {
            case .offset: selectedId = "offset"
            case .raster: selectedId = "raster"
            case .spiral: selectedId = "spiral"
            case .trochoidal: selectedId = "trochoidal"
            case .adaptive: selectedId = "adaptive"
        }

        return .variant(.init(id: id, label: label, cases: cases, selectedId: selectedId, onSelect: { newCaseId in
            switch newCaseId {
                case "offset": onChange(.offset)
                case "raster": onChange(.raster)
                case "spiral": onChange(.spiral(direction: .outsideIn))
                case "trochoidal": onChange(.trochoidal(settings: .init(radialEngagement: 0.3, loopRadius: 1.0)))
                case "adaptive": onChange(.adaptive(settings: .init(optimalLoad: 1.0)))
                default: break
            }
        }))
    }
}

extension SC.SlotClearingPattern {

    /// Variant field covering the three slot clearing patterns. Note this is
    /// a narrower set than `PocketClearingPattern` -- no `.offset` or
    /// `.spiral`, since neither makes sense for a linear slot -- so this is
    /// its own switch rather than a filtered reuse of the pocket one.
    public func formField(id: String = "pattern",
                           label: String = "Clearing Pattern",
                           onChange: @escaping (SC.SlotClearingPattern) -> Void) -> SC.ParameterField {

        let currentTrochoidal: SC.TrochoidalSettings = { if case .trochoidal(let s) = self { return s } else { return .init(radialEngagement: 0.3, loopRadius: 1.0) } }()
        let currentAdaptive: SC.AdaptiveSettings = { if case .adaptive(let s) = self { return s } else { return .init(optimalLoad: 1.0) } }()

        let cases: [SC.ParameterField.VariantField.Case] = [
            .init(id: "raster", label: "Raster", fields: []),
            .init(id: "trochoidal", label: "Trochoidal",
                  fields: currentTrochoidal.formFields(idPrefix: "\(id).trochoidal") { onChange(.trochoidal(settings: $0)) }),
            .init(id: "adaptive", label: "Adaptive",
                  fields: currentAdaptive.formFields(idPrefix: "\(id).adaptive") { onChange(.adaptive(settings: $0)) })
        ]

        let selectedId: String
        switch self {
            case .raster: selectedId = "raster"
            case .trochoidal: selectedId = "trochoidal"
            case .adaptive: selectedId = "adaptive"
        }

        return .variant(.init(id: id, label: label, cases: cases, selectedId: selectedId, onSelect: { newCaseId in
            switch newCaseId {
                case "raster": onChange(.raster)
                case "trochoidal": onChange(.trochoidal(settings: .init(radialEngagement: 0.3, loopRadius: 1.0)))
                case "adaptive": onChange(.adaptive(settings: .init(optimalLoad: 1.0)))
                default: break
            }
        }))
    }
}
