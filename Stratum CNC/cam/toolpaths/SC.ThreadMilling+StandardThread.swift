//
//  SC.ThreadMilling+StandardThread.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//
//  The "Standard Thread" dropdown on thread milling. Picking a preset sets the two
//  real fields (`pitch`, `targetDiameter`) at once and shows them grayed out; the
//  fields only become editable once "Custom" is chosen. Whether "Custom" was chosen
//  is the one piece of state the library's operation has no room for, so the app
//  keeps it (`OperationSettings.threadIsCustom`) and passes it in as `isCustom`.
//  Values that match no preset (older projects, hand-edited) count as custom too.
//

import Foundation
import StratumCAM

extension SC {

    /// One entry in the ISO metric coarse-pitch thread series.
    struct StandardThread: Identifiable, Hashable {
        var id: String { designation }
        var designation: String    // e.g. "M1.6"
        var diameter: Double       // major diameter, mm
        var pitch: Double          // mm
    }

    /// ISO 261 coarse-pitch metric threads from M1 to M8.
    static let standardThreads: [StandardThread] = [
        .init(designation: "M1",   diameter: 1.0, pitch: 0.25),
        .init(designation: "M1.1", diameter: 1.1, pitch: 0.25),
        .init(designation: "M1.2", diameter: 1.2, pitch: 0.25),
        .init(designation: "M1.4", diameter: 1.4, pitch: 0.3),
        .init(designation: "M1.6", diameter: 1.6, pitch: 0.35),
        .init(designation: "M1.8", diameter: 1.8, pitch: 0.35),
        .init(designation: "M2",   diameter: 2.0, pitch: 0.4),
        .init(designation: "M2.2", diameter: 2.2, pitch: 0.45),
        .init(designation: "M2.5", diameter: 2.5, pitch: 0.45),
        .init(designation: "M3",   diameter: 3.0, pitch: 0.5),
        .init(designation: "M3.5", diameter: 3.5, pitch: 0.6),
        .init(designation: "M4",   diameter: 4.0, pitch: 0.7),
        .init(designation: "M4.5", diameter: 4.5, pitch: 0.75),
        .init(designation: "M5",   diameter: 5.0, pitch: 0.8),
        .init(designation: "M6",   diameter: 6.0, pitch: 1.0),
        .init(designation: "M7",   diameter: 7.0, pitch: 1.0),
        .init(designation: "M8",   diameter: 8.0, pitch: 1.25)
    ]

    private static let customThreadId = "custom"

    /// The preset matching the current diameter/pitch pair, or `"custom"`
    /// once either value has been hand-edited away from a standard size.
    static func matchingStandardThreadId(diameter: Double, pitch: Double) -> String {
        standardThreads.first {
            abs($0.diameter - diameter) < 0.001 && abs($0.pitch - pitch) < 0.001
        }?.id ?? customThreadId
    }

    /// Whether the diameter/pitch pair is one of the standard sizes.
    static func isStandardThread(diameter: Double, pitch: Double) -> Bool {
        matchingStandardThreadId(diameter: diameter, pitch: pitch) != customThreadId
    }

    /// Builds the dropdown itself. `isCustom` pins it on "Custom" even when the current
    /// values happen to match a preset. `onSelect` is called for a real preset,
    /// `onSelectCustom` when "Custom" is picked (the values are left as they are).
    static func standardThreadChoice(id: String,
                                      label: String = "Standard Thread",
                                      diameter: Double,
                                      pitch: Double,
                                      isCustom: Bool = false,
                                      onSelectCustom: @escaping () -> Void = {},
                                      onSelect: @escaping (StandardThread) -> Void) -> ParameterField.ChoiceField {
        .init(id: id,
              label: label,
              options: [.init(id: customThreadId, label: "Custom")] + standardThreads.map { .init(id: $0.id, label: $0.designation) },
              selectedId: isCustom ? customThreadId : matchingStandardThreadId(diameter: diameter, pitch: pitch),
              onChange: { selectedId in
                  if selectedId == customThreadId {
                      onSelectCustom()
                      return
                  }
                  guard let thread = standardThreads.first(where: { $0.id == selectedId }) else { return }
                  onSelect(thread)
              })
    }
}
