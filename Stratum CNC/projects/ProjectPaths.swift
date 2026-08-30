//
//  ProjectPaths.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct ProjectPaths {
    let root: URL

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        root = appSupport.appendingPathComponent("Projects", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var indexFile: URL {
        root.appendingPathComponent("projects.json")
    }

    func directory(for project: ProjectData) -> URL {
        root.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    func projectMetadata(for project: ProjectData) -> URL {
        directory(for: project).appendingPathComponent("project.json")
    }

    func preview(for project: ProjectData) -> URL {
        directory(for: project).appendingPathComponent("preview.png")
    }

    func ncFile(for project: ProjectData) -> URL {
        directory(for: project).appendingPathComponent("job.nc")
    }

    func toolpathsFile(for project: ProjectData) -> URL {
        directory(for: project).appendingPathComponent("toolpaths.json")
    }

    func assetsDirectory(for project: ProjectData) -> URL {
        directory(for: project).appendingPathComponent("assets", isDirectory: true)
    }
}
