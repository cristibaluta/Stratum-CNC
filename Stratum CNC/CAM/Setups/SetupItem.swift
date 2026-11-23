//
//  SetupItem.swift
//  Stratum CNC
//
//  One object a setup includes, and optionally where it sits in that setup. A setup with no items
//  includes every object of the project (what every setup did before objects were separate, and
//  what a one-object project wants). A setup with items includes only those.
//
//  Placement: `transformOverride` nil means the object's global transform (`ProjectObject.transform`).
//  A value replaces it for this setup only, whole: it is the full placement, not a difference.
//

import Foundation

struct SetupItem: Codable, Hashable, Sendable {

    var objectID: UUID
    var transformOverride: ObjectTransform? = nil
}

extension Setup {

    /// Includes the object: every object when the setup has no items of its own.
    func includes(_ objectID: UUID) -> Bool {
        items.isEmpty || items.contains { $0.objectID == objectID }
    }

    /// This setup's own placement of the object, nil when it uses the global one.
    func transformOverride(for objectID: UUID) -> ObjectTransform? {
        items.first { $0.objectID == objectID }?.transformOverride
    }
}
