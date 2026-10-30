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
    /// Security-scoped bookmark to the project folder, for projects saved outside Stratum.
    var bookmark: Data?
    /// Last known path of an external project's folder..
    var path: String?

    var isExternal: Bool {
        bookmark != nil
    }
}
