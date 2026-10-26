//
//  ProjectBookmark.swift
//  Stratum CNC
//
//  Security-scoped bookmarks for projects saved outside Stratum.
//

import Foundation

enum ProjectBookmark {

    struct Resolved {
        let url: URL
        /// The system says the bookmark still works but should be re-created.
        let isStale: Bool
    }

    /// Creates a bookmark to `folder`. The caller must currently have access
    /// to it: either the user just picked it (or its parent), or it was
    /// resolved from an earlier bookmark with access started.
    static func make(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: .withSecurityScope,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil)
    }

    /// Resolves a bookmark without ever showing UI or mounting a volume, so a
    /// missing folder or an unmounted drive throws instead of prompting.
    static func resolve(_ data: Data) throws -> Resolved {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data,
                          options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        return Resolved(url: url, isStale: isStale)
    }
}
