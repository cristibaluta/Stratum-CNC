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

    enum PathError: Error { case invalidProjectName }

    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\")
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    init(project: Project, documentsDirectory: URL = Self.appDocuments) throws {
        guard Self.isValidName(project.name) else { throw PathError.invalidProjectName }
        self.project = project

        projectsRoot = documentsDirectory.appendingPathComponent("Projects", isDirectory: true)
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
