//
//  ToolSourceKind.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//
//  Where a tool came from. Independent of the tool's type: the type is how you find a tool,
//  the source is only a tag and a filter. A tool points at its source with `Tool.sourceID`;
//  the sources themselves are listed in `ToolLibrary.sources`.
//

import Foundation

enum ToolSourceKind: String, Codable, Hashable {
    /// Shipped with the app (default_tools.json).
    case bundled
    /// One batch per import: a file, on a date.
    case imported
    /// Created or duplicated by the user.
    case custom
}

struct ToolSourceInfo: Identifiable, Codable, Hashable {
    let id: UUID

    /// Shown in the Source filter and on the row chip: "Makera defaults", "shop.tools", "My tools".
    var name: String
    var kind: ToolSourceKind

    /// When an import happened. `nil` for the bundled and custom sources.
    var date: Date?
    /// The file an import came from, if any.
    var fileName: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: ToolSourceKind,
        date: Date? = nil,
        fileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.date = date
        self.fileName = fileName
    }
}

extension ToolSourceInfo {

    /// Fixed ids: there is exactly one bundled and one custom source, in every library.
    static let bundledID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
    static let customID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!

    static let bundled = ToolSourceInfo(id: bundledID, name: "Makera defaults", kind: .bundled)
    static let custom = ToolSourceInfo(id: customID, name: "My tools", kind: .custom)
}
