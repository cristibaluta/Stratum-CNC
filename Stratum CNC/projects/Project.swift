//
//  Project.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31/08/2026.
//

import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var modifiedAt: Date
    /// Security-scoped bookmark to the project folder, for projects saved
    /// outside Stratum. `nil` means the project lives inside Stratum's own
    /// Documents/Projects folder (and is also what older `projects.json`
    /// files decode to).
    var bookmark: Data?
    /// Last known path of an external project's folder. Informational (shown
    /// to the user, kept in step when the bookmark resolves to a new place);
    /// the bookmark is what actually grants access.
    var path: String?

    var isExternal: Bool { bookmark != nil }

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = .now,
         modifiedAt: Date = .now,
         bookmark: Data? = nil,
         path: String? = nil) {

        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.bookmark = bookmark
        self.path = path
    }
}
