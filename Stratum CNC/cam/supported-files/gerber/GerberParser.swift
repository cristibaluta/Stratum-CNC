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

        // Create a unique temporary directory for this import.
        let extractionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("GerberImport-\(UUID().uuidString)",
                                    isDirectory: true)

        try fileManager.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true
        )

        defer {
            try? fileManager.removeItem(at: extractionDirectory)
        }

        // Extract the archive.
        //
        // Use the exact unzip method exposed by your installed
        // version of tomasf/Zip here.
        try unzip(url, to: extractionDirectory)

        // Recursively find all extracted files.
        let extractedFiles = fileManager.enumerator(
            at: extractionDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

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
            let layer = file.deletingPathExtension().lastPathComponent
            let extensionName = file.pathExtension.lowercased()

            // Copper is special: a Gerber line is a centerline plus an aperture
            // width, not a hairline. Convert copper into physical filled polygons
            // and union all overlapping geometry before exposing it as DXF.
            let entities: [DXF.Entity]
            if extensionName == "gtl" || extensionName == "gbl" {
                entities = CopperGerberParser(source: text, layer: layer).parse()
            } else {
                entities = SingleGerberParser(source: text, layer: layer).parse()
            }

            parsedFiles.append(ParsedFile(name: layer, entities: entities))
        }

        return Result(files: parsedFiles)
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

    private static func unzip(
        _ url: URL,
        to directory: URL
    ) throws {

        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let archive = try ZipArchive(url: url, mode: .readOnly)

        for entry in try archive.entries {

            let entryPath = entry.path

            // Prevent ZIP path traversal.
            let destination = directory.appendingPathComponent(entryPath)

            guard destination.path.hasPrefix(directory.path + "/") else {
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
