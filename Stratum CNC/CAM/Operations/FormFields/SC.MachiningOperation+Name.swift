//
//  SC.MachiningOperation+Name.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.11.2026.
//

import Foundation
import StratumCAM

extension SC.MachiningOperation {
    /// Display name for the operation
    public var displayName: String {
        switch self {
            case .facing: return "Facing"
            case .slotting: return "Slotting"
            case .threadMilling: return "Thread Milling"
            case .engrave: return "Engrave"
            case .contour: return "Contour"
            case .pocket: return "Pocket"
            case .drilling: return "Drilling"
            case .chamfer: return "Chamfer"
            case .boring: return "Boring"
            case .counterbore: return "Counterbore"
        }
    }
}
