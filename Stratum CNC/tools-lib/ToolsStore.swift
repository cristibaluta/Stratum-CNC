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

    /// Bundled, custom, then one per import.
    @Published private(set) var sources: [ToolSourceInfo] = []

    /// Snapshot of what is on disk. Edits are live in `tools`; `save()` writes them out.
    @Published private var savedTools: [Tool] = []
    @Published private var savedSources: [ToolSourceInfo] = []

    var hasUnsavedChanges: Bool {
        tools != savedTools || sources != savedSources
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

        let library = try Self.makeDecoder().decode(ToolLibrary.self, from: data)

        self.library = library
        tools = library.tools
        sources = library.sources
        savedTools = tools
        savedSources = sources
    }

    /// The source a tool belongs to.
    func source(for tool: Tool) -> ToolSourceInfo {
        sources.first { $0.id == tool.sourceID } ?? .bundled
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func save() throws {
        // Write the whole library (not just the array) so `load()` can read it back.
        guard var library else {
            throw ToolStoreError.libraryNotLoaded
        }
        library.tools = tools
        library.sources = sources
        self.library = library
        let data = try Self.makeEncoder().encode(library)

        try data.write(to: toolsFileURL, options: .atomic)
        savedTools = tools
        savedSources = sources
    }

    /// Discards all edits made since the last save.
    func revertChanges() {
        tools = savedTools
        sources = savedSources
    }

    func update(_ tool: Tool) throws {
        guard let index = tools.firstIndex(where: { $0.id == tool.id }) else {
            return
        }

        tools[index] = tool
        try save()
    }

    /// Adds a tool made by the user: it always belongs to the custom source ("My tools").
    func add(_ tool: Tool) throws {
        var tool = tool
        tool.sourceID = ToolSourceInfo.customID
        tools.append(tool)
        try save()
    }

    /// Duplicating forks a tool into "My tools", whatever the original's source was,
    /// so bundled and imported tools stay as they came.
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
            presets: tool.presets,
            sourceID: ToolSourceInfo.customID
        )
        try add(copy)
        return copy
    }

    /// Adds imported tools, then saves once.
    ///
    /// A tool whose id is already in the library is not duplicated; instead any imported
    /// presets it doesn't have yet are added to it. That way re-importing fills in presets
    /// without touching what was edited.
    ///
    /// Tools that are added get a new source for this import, named after the file.
    @discardableResult
    func importTools(_ imported: [Tool], fileName: String) throws -> ImportCounts {
        var indexByID: [UUID: Int] = [:]
        for (index, tool) in tools.enumerated() { indexByID[tool.id] = index }

        // One batch per import. It is only kept if the import adds tools.
        let batch = ToolSourceInfo(name: fileName, kind: .imported, date: Date(), fileName: fileName)

        var added = 0, updated = 0, skipped = 0
        for var tool in imported {
            var importedIDs = Set<UUID>()
            tool.presets = tool.presets.filter { importedIDs.insert($0.id).inserted }
            guard let index = indexByID[tool.id] else {
                tool.sourceID = batch.id
                indexByID[tool.id] = tools.count
                tools.append(tool)
                added += 1
                continue
            }

            // Already in the library: it keeps its source, and only gains the presets it lacks.
            let known = Set(tools[index].presets.map(\.id))
            let newPresets = tool.presets.filter { !known.contains($0.id) }
            guard !newPresets.isEmpty else {
                skipped += 1
                continue
            }
            tools[index].presets.append(contentsOf: newPresets)
            updated += 1
        }

        if added > 0 {
            sources.append(batch)
        }
        if added + updated > 0 { try save() }
        return ImportCounts(added: added, updated: updated, skipped: skipped, batch: added > 0 ? batch : nil)
    }

    // MARK: Import batches

    /// The import batches, newest last (the order they were imported in).
    var importSources: [ToolSourceInfo] {
        sources.filter { $0.kind == .imported }
    }

    /// How many tools currently belong to a source.
    func toolCount(in source: ToolSourceInfo) -> Int {
        tools.filter { $0.sourceID == source.id }.count
    }

    /// Removes an import batch and every tool that came with it.
    ///
    /// Unlike `delete(_:)` this does not save: the removal is a live edit, so the unsaved-changes
    /// bar appears and `revertChanges()` brings the batch back. Only imports can be removed;
    /// the bundled and custom sources are ignored.
    @discardableResult
    func removeImport(_ source: ToolSourceInfo) -> Int {
        guard source.kind == .imported else { return 0 }
        let before = tools.count
        tools.removeAll { $0.sourceID == source.id }
        sources.removeAll { $0.id == source.id }
        return before - tools.count
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

struct ImportCounts {
    var added: Int
    var updated: Int
    var skipped: Int
    /// The new source created for this import, or `nil` if it added no tools.
    var batch: ToolSourceInfo?
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
