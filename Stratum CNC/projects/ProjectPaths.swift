//
//  ProjectPaths.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct ProjectPaths {

    let project: Project
    let projectsRoot: URL

    static let appDocuments: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    static var projectsIndexFile: URL { appDocuments.appendingPathComponent("projects.json") }

    init(project: Project) throws {
        self.project = project

        projectsRoot = ProjectPaths.appDocuments.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    var projectDirectory: URL {
        projectsRoot.appendingPathComponent(project.name, isDirectory: true)
    }

    var projectMetadata: URL {
        projectDirectory.appendingPathComponent("project.json")
    }

    var preview: URL {
        projectDirectory.appendingPathComponent("preview.png")
    }

    var ncFile: URL {
        projectDirectory.appendingPathComponent("job.nc")
    }

    var toolpathsFile: URL {
        projectDirectory.appendingPathComponent("toolpaths.json")
    }

    var assetsDirectory: URL {
        projectDirectory.appendingPathComponent("assets", isDirectory: true)
    }
}
