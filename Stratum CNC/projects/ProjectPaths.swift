//
//  ProjectPaths.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct ProjectPaths {

    let appDocuments: URL
    let projectsRoot: URL

    init() throws {
        appDocuments = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        projectsRoot = appDocuments.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    var projectsIndexFile: URL {
        appDocuments.appendingPathComponent("projects.json")
    }

    func projectDirectory(for project: Project) -> URL {
        projectsRoot.appendingPathComponent(project.name, isDirectory: true)
    }

    func projectMetadata(for project: Project) -> URL {
        projectDirectory(for: project).appendingPathComponent("project.json")
    }

    func preview(for project: Project) -> URL {
        projectDirectory(for: project).appendingPathComponent("preview.png")
    }

    func ncFile(for project: Project) -> URL {
        projectDirectory(for: project).appendingPathComponent("job.nc")
    }

    func toolpathsFile(for project: Project) -> URL {
        projectDirectory(for: project).appendingPathComponent("toolpaths.json")
    }

    func assetsDirectory(for project: Project) -> URL {
        projectDirectory(for: project).appendingPathComponent("assets", isDirectory: true)
    }
}
