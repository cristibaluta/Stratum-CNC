//
//  GerberParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import Foundation
import Zip
import SwiftDXF

enum GerberParser {

    struct ParsedFile {
        let name: String
        let entities: [DXF.Entity]
    }

    struct Result {
        let files: [ParsedFile]
    }

    enum ParserError: Error {
        case archiveNotFound(URL)
        case noGerberFiles(URL)
    }

    static func parseArchive(url: URL) throws -> Result {

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw ParserError.archiveNotFound(url)
        }

        // TODO: unzip in memory instead of saving to a temporary dir
        // Create a unique temporary directory for this import.
        let extractionDirectory = fileManager.temporaryDirectory.appendingPathComponent("GerberImport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: extractionDirectory)
        }
        try unzip(url, to: extractionDirectory)

        // Recursively find all extracted files.
        let extractedFiles = fileManager.enumerator(at: extractionDirectory,
                                                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                                    options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []

        let gerberFiles = extractedFiles.filter {
            isGerberFile($0)
        }

        guard !gerberFiles.isEmpty else {
            throw ParserError.noGerberFiles(extractionDirectory)
        }

        var parsedFiles: [ParsedFile] = []

        for file in gerberFiles {
            let data = try Data(contentsOf: file)

            guard let text = String(data: data, encoding: .utf8) else {
                continue
            }
            parsedFiles.append(parseFile(text, name: file.lastPathComponent))
        }

        return Result(files: parsedFiles)
    }

    static func parseFile(_ text: String, name: String) -> ParsedFile {
        let ext = (name as NSString).pathExtension.lowercased()
        let entities: [DXF.Entity]
        switch ext {
        case "drl":
            entities = ExcellonParser(source: text, layer: name).parse()
        case "gtl", "gbl":
            entities = CopperGerberParser(source: text, layer: name).parse()
        default:
            entities = SingleGerberParser(source: text, layer: name).parse()
        }
        return ParsedFile(name: name, entities: entities)
    }

    private static func isGerberFile(_ url: URL) -> Bool {

        let ext = url.pathExtension.lowercased()

        return [
            "gbr",
            "gtl", "gbl",
            "gto", "gbo",
            "gtp", "gbp",
            "gts", "gbs",
            "gm1", "gm2", "gm3",
            "drl"
        ].contains(ext)
    }

    private static func unzip(_ url: URL, to directory: URL) throws {

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let archive = try ZipArchive(url: url, mode: .readOnly)
        for entry in try archive.entries {
            let entryPath = entry.path
            // Prevent ZIP path traversal.
            guard let destination = ArchiveEntryPath.destination(for: entryPath, in: directory) else {
                continue
            }

            if entry.kind == .directory {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }

            let parent = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

            let data = try archive.fileContents(at: entry.path)
            try data.write(to: destination)
        }
    }
}
