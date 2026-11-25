//
//  SetupItem.swift
//  Stratum CNC
//
//  One object a setup includes, and optionally where it sits in that setup. A setup with no items
//  includes every object of the project (what every setup did before objects were separate, and
//  what a one-object project wants). A setup with items includes only those.
//
//  Placement: a setup can change only an object's position. `positionOverride` nil means the
//  object's global position; scale and rotation always come from the global transform
//  (`ProjectObject.transform`).
//

import Foundation

struct SetupItem: Codable, Hashable, Sendable {

    var objectID: UUID
    var positionOverride: ObjectPosition? = nil

    init(objectID: UUID, positionOverride: ObjectPosition? = nil) {
        self.objectID = objectID
        self.positionOverride = positionOverride
    }

    private enum CodingKeys: String, CodingKey {
        case objectID, positionOverride
        /// Projects saved while a setup could override the whole placement
        case transformOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectID = try c.decode(UUID.self, forKey: .objectID)
        if let position = try c.decodeIfPresent(ObjectPosition.self, forKey: .positionOverride) {
            positionOverride = position
        } else if let legacy = try c.decodeIfPresent(ObjectTransform.self, forKey: .transformOverride) {
            // Only the position of an old override is kept
            positionOverride = legacy.position
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(objectID, forKey: .objectID)
        try c.encodeIfPresent(positionOverride, forKey: .positionOverride)
    }
}

extension Setup {

    /// Includes the object: every object when the setup has no items of its own.
    func includes(_ objectID: UUID) -> Bool {
        items.isEmpty || items.contains { $0.objectID == objectID }
    }

    /// This setup's own position of the object, nil when it uses the global one.
    func positionOverride(for objectID: UUID) -> ObjectPosition? {
        items.first { $0.objectID == objectID }?.positionOverride
    }
}
