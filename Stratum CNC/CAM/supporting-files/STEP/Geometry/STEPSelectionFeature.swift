//
//  STEPSelectionFeature.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.11.2026.
//

import Foundation
import StratumCAM

/// The kind of feature a selection of edges forms.
enum STEPSelectionFeature: Equatable, Sendable {
    /// Only full circles: the rims of holes or studs.
    case holes
    /// Edges that join into closed outlines (a face's contour, a pocket, a boss).
    /// `horizontal`: they lie in a plane facing up or down.
    case closedProfile(horizontal: Bool)
    /// One straight edge.
    case line
    /// Anything else: open chains of edges, arcs, curves.
    case openPath
    /// The two rails of a chamfer face (picked through the face). The toolpath cuts the sharp
    /// edge the chamfer replaced, not these.
    case chamfer
}

extension SC.MachiningOperation.Kind {

    /// The operations offered for a selection of STEP edges, most likely first.
    static func operations(for feature: STEPSelectionFeature) -> [SC.MachiningOperation.Kind] {
        switch feature {
            case .holes:
                return [.drilling, .threadMilling, .counterbore, .boring, .pocket, .contour, .chamfer]
            case .closedProfile(let horizontal):
                return horizontal
                    ? [.pocket, .contour, .facing, .chamfer, .engrave]
                    : [.pocket, .contour, .chamfer, .engrave]
            case .line:
                return [.contour, .slotting, .engrave, .chamfer]
            case .openPath:
                return [.contour, .engrave, .chamfer]
            case .chamfer:
                return [.chamfer, .contour]
        }
    }
}
