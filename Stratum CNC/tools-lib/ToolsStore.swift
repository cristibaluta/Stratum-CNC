//
//  ToolStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import Observation
import Combine

@MainActor
final class ToolsStore: ObservableObject {

    private(set) var library: ToolLibrary?
    @Published var tools: [Tool] = []

    /// Snapshot of what is on disk. Edits are live in `tools`; `save()` writes them out.
    @Published private var savedTools: [Tool] = []

    var hasUnsavedChanges: Bool {
        tools != savedTools
    }

    private let fileManager = FileManager.default

    private let toolsFileURL: URL

    init(toolsFileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tools.json")) {
        self.toolsFileURL = toolsFileURL
        do {
            try load()
        } catch {
            print("Failed to load tools: \(error)")
            tools = []
        }
    }

    func load() throws {
        if !fileManager.fileExists(atPath: toolsFileURL.path) {
            try copyDefaultTools()
        }

        let data = try Data(contentsOf: toolsFileURL)

        let decoder = JSONDecoder()
        library = try decoder.decode(ToolLibrary.self, from: data)
        tools = library?.tools ?? []
        savedTools = tools
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Write the whole library (not just the array) so `load()` can read it back.
        guard var library else {
            throw ToolStoreError.libraryNotLoaded
        }
        library.tools = tools
        self.library = library
        let data = try encoder.encode(library)

        try data.write(to: toolsFileURL, options: .atomic)
        savedTools = tools
    }

    /// Discards all edits made since the last save.
    func revertChanges() {
        tools = savedTools
    }

    func update(_ tool: Tool) throws {
        guard let index = tools.firstIndex(where: { $0.id == tool.id }) else {
            return
        }

        tools[index] = tool
        try save()
    }

    func add(_ tool: Tool) throws {
        tools.append(tool)
        try save()
    }

    @discardableResult
    func duplicate(_ tool: Tool) throws -> Tool {
        let copy = Tool(
            name: "\(tool.name) Copy",
            shankDiameter: tool.shankDiameter,
            toolDiameter: tool.toolDiameter,
            length: tool.length,
            type: tool.type,
            group: tool.group,
            quantity: tool.quantity,
            link: tool.link,
            tipAngle: tool.tipAngle,
            presets: tool.presets
        )
        try add(copy)
        return copy
    }

    /// Adds imported tools, then saves once.
    ///
    /// A tool whose id is already in the library is not duplicated; instead any imported
    /// presets it doesn't have yet are added to it. That way re-importing fills in presets
    /// without touching what was edited. The "-" placeholder preset written by an earlier
    /// version of the importer is dropped when real presets arrive.
    @discardableResult
    func importTools(_ imported: [Tool]) throws -> (added: Int, updated: Int, skipped: Int) {
        var indexByID: [UUID: Int] = [:]
        for (index, tool) in tools.enumerated() { indexByID[tool.id] = index }

        var added = 0, updated = 0, skipped = 0
        for var tool in imported {
            var importedIDs = Set<UUID>()
            tool.presets = tool.presets.filter { importedIDs.insert($0.id).inserted }
            guard let index = indexByID[tool.id] else {
                indexByID[tool.id] = tools.count
                tools.append(tool)
                added += 1
                continue
            }

            let known = Set(tools[index].presets.map(\.id))
            let newPresets = tool.presets.filter { !known.contains($0.id) }
            guard !newPresets.isEmpty else {
                skipped += 1
                continue
            }
            tools[index].presets.removeAll { $0.name == "-" }
            tools[index].presets.append(contentsOf: newPresets)
            updated += 1
        }

        if added + updated > 0 { try save() }
        return (added, updated, skipped)
    }

    func delete(_ tool: Tool) throws {
        tools.removeAll { $0.id == tool.id }
        try save()
    }

    private func copyDefaultTools() throws {
        guard let bundledURL = Bundle.main.url(forResource: "default_tools", withExtension: "json") else {
            throw ToolStoreError.defaultToolsNotFound
        }

        try fileManager.copyItem(at: bundledURL, to: toolsFileURL)
    }
}

enum ToolStoreError: LocalizedError {
    case defaultToolsNotFound
    case libraryNotLoaded

    var errorDescription: String? {
        switch self {
        case .defaultToolsNotFound:
            "The bundled default_tools.json could not be found."
        case .libraryNotLoaded:
            "The tool library is not loaded, so it can't be saved."
        }
    }
}
