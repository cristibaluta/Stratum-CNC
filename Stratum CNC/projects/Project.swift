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

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = .now,
         modifiedAt: Date = .now) {

        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
