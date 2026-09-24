//
//  NCFileDocument.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation
import Combine
import simd

@MainActor
final class NCFileDocument: ObservableObject {

    @Published private(set) var fileURL: URL?
    @Published private(set) var fileName: String = "No file loaded"
    @Published private(set) var lines: [GCodeLine] = []
    @Published private(set) var toolpathSegments: [ToolpathSegment] = []
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    /// Distinct tool numbers referenced by `T…`/`M6` tool-change pairs in
    /// the loaded program, in the order each first appears. Cached and
    /// recomputed only when `lines` actually changes (see `recomputeTools`
    /// below) rather than being a computed property — `GCodeToolpathAnalyzer`
    /// is two `NSRegularExpression` passes over every line, and this is read
    /// from the canvas overlay, whose containing view re-evaluates on every
    /// `GCodeStore` publish, `scrubLine` included. `GCodeViewer` hit the same
    /// issue for its own toolpath list; same fix here.
    @Published private(set) var tools: [Int] = []

    /// Every tool/operation section `GCodeToolpathAnalyzer` found in the
    /// current `lines`, in file order — the same analysis `tools` is
    /// derived from, kept here in full so the canvas can highlight whichever
    /// section owns the line currently being scrubbed or executed (see
    /// `toolpath(containingLine:)`). Recomputed alongside `tools`, never on
    /// scrub.
    @Published private(set) var toolpaths: [GCodeToolpath] = []

    /// Header metadata (tool specs, ...) from the most recent *load*. Set
    /// only when a file/program is loaded — not on `rebuildToolpath` — so
    /// editing a line doesn't re-emit it and wipe tool choices the person
    /// has made since. `nil` when the file has no recognised header.
    @Published private(set) var loadedHeader: GCodeHeader?

    var isLoaded: Bool {
        fileURL != nil
    }

    var lineCount: Int {
        lines.count
    }

    var toolpathCount: Int {
        toolpathSegments.count
    }

    /// Running vertex counts per toolpath role, indexed by segment index:
    /// `rapidVertexPrefix[i]` / `cuttingVertexPrefix[i]` is how many
    /// vertices `RenderObject.toolpath(from:)` would put in the rapid /
    /// cutting buffer for the first `i` entries of `toolpathSegments` (each
    /// segment becomes 2 vertices — start, end — in whichever bucket its
    /// `ToolpathFlags` puts it in). Both arrays have `toolpathSegments.count
    /// + 1` entries, one prefix sum per possible slice boundary, index 0
    /// always `0`.
    ///
    /// Rebuilt once alongside `toolpathSegments` — not on every scrub tick —
    /// so `toolpathVertexCounts(upTo:)` is an O(1) lookup instead of a
    /// linear rescan of everything scrubbed past so far.
    private var rapidVertexPrefix: [Int] = [0]
    private var cuttingVertexPrefix: [Int] = [0]

    private func rebuildVertexPrefixSums() {
        var rapid = [0]
        var cutting = [0]
        rapid.reserveCapacity(toolpathSegments.count + 1)
        cutting.reserveCapacity(toolpathSegments.count + 1)

        var rapidTotal = 0
        var cuttingTotal = 0
        for segment in toolpathSegments {
            // Same rapid/cutting split `RenderObject.toolpath(from:)` uses —
            // keep these in sync if that classification ever changes.
            if segment.flags & ToolpathFlags.rapid != 0 {
                rapidTotal += 2
            } else {
                cuttingTotal += 2
            }
            rapid.append(rapidTotal)
            cutting.append(cuttingTotal)
        }

        rapidVertexPrefix = rapid
        cuttingVertexPrefix = cutting
    }

    /// Rebuilds `tools` from the current `lines`. Called alongside
    /// `rebuildVertexPrefixSums` — everywhere `lines` is (re)assigned — never
    /// on scrub.
    private func recomputeTools() {
        let analyzed = GCodeToolpathAnalyzer.analyze(lines.map { (id: $0.id, text: $0.text) })
        toolpaths = analyzed

        var seen = Set<Int>()
        var ordered: [Int] = []
        for toolpath in analyzed {
            guard let tool = toolpath.toolNumber, seen.insert(tool).inserted else { continue }
            ordered.append(tool)
        }
        tools = ordered
    }

    // MARK: Load

    private var loadTask: Task<Void, Never>?

    func load(from url: URL) {

        loadTask?.cancel()

        lastError = nil
        isLoading = true

        let fileName = url.lastPathComponent

        // `Task.detached`, not `Task { }`: `Task { }` inherits the actor
        // context of the code that creates it, and this method is
        // `@MainActor`-isolated — so the old `Task { }` here started life on
        // the main actor. `loadAndParseFile` below being `nonisolated`
        // doesn't change that: a `nonisolated` function has no actor of its
        // own, so it just keeps running on whatever executor its caller was
        // already on. Net effect: the file read and the parse (both
        // synchronous, blocking work) were quietly running on the main
        // thread the whole time, freezing the UI on anything but a small
        // file. `Task.detached` isn't bound to any actor, so this now
        // genuinely runs on the background concurrent pool; only the final
        // state update below hops back to the main actor.
        loadTask = Task.detached { [weak self] in
            do {
                let parsed = try await Self.loadAndParseFile(url: url)

                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }

                await self.finishLoad(parsed: parsed, url: url, fileName: fileName)

            } catch {

                guard !Task.isCancelled else {
                    return
                }
                guard let self else {
                    return
                }

                await self.failLoad(error)
            }
        }
    }

    /// Applies a successful parse. Runs on the main actor (implicit — this
    /// is a member of `NCFileDocument`, which is `@MainActor`) so it's safe
    /// to touch every `@Published` property directly; called with `await`
    /// from the background `Task.detached` in `load(from:)`.
    private func finishLoad(parsed: ParsedGCode, url: URL, fileName: String) {
        self.lines = parsed.lines
        self.toolpathSegments = parsed.toolpathSegments
        self.rebuildVertexPrefixSums()
        self.recomputeTools()
        self.loadedHeader = parsed.header
        self.fileURL = url
        self.fileName = fileName
        self.isLoading = false
    }

    private func failLoad(_ error: Error) {
        self.isLoading = false
        self.lastError = "Couldn't read file: \(error.localizedDescription)"
    }

    func load(from string: String) {
        let parser = GCodeParser()
        let code: ParsedGCode = parser.parse(string)

        self.lines = code.lines
        self.toolpathSegments = code.toolpathSegments
        rebuildVertexPrefixSums()
        recomputeTools()
        self.loadedHeader = code.header
        // A program built in memory isn't backed by a file: drop whatever was loaded before.
        self.fileURL = nil
        self.lastError = nil
        self.fileName = "From CAM"
    }

    // MARK: Background parsing

    private nonisolated static func loadAndParseFile(url: URL) async throws -> ParsedGCode {

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let parser = GCodeParser()

        return parser.parse(contents)
    }

    // MARK: Line editing

    func updateLine(at index: Int, text: String) {

        guard index >= 0, index < lines.count else {
            return
        }
        guard lines[index].text != text else {
            return
        }
        lines[index].text = text
        rebuildToolpath()
    }

    // TODO: this is not efficient at all
    func rebuildToolpath() {
        let source = lines.map(\.text).joined(separator: "\n")

        let parser = GCodeParser()
        let parsed = parser.parse(source)

        lines = parsed.lines
        toolpathSegments = parsed.toolpathSegments
        rebuildVertexPrefixSums()
        recomputeTools()
    }

    // MARK: Geometry lookup

    func geometry(forLine lineNumber: Int) -> ArraySlice<ToolpathSegment> {

        let index = lineNumber - 1

        guard index >= 0, index < lines.count else {
            return toolpathSegments[0..<0]
        }

        let line = lines[index]

        let start = line.geometryStart
        let end = start + line.geometryCount

        guard start >= 0, end <= toolpathSegments.count, start <= end else {
            return toolpathSegments[0..<0]
        }

        return toolpathSegments[start..<end]
    }

    /// All toolpath segments generated by lines `1...line` (inclusive) — the
    /// prefix a scrubber should hand to `RenderObject.toolpath(from:)` so the
    /// canvas only draws what's been "cut" up to that point in the file.
    /// O(1): segments are appended in ascending line order while parsing, so
    /// a single line's own `geometryStart + geometryCount` (the same
    /// bookkeeping `geometry(forLine:)` uses) already marks where the prefix
    /// ends — no need to filter every segment by `lineNumber`.
    func toolpathSegments(upTo line: Int) -> ArraySlice<ToolpathSegment> {

        guard line >= 1 else {
            return toolpathSegments[0..<0]
        }
        guard !lines.isEmpty else {
            return toolpathSegments[0..<0]
        }

        let index = min(line, lines.count) - 1
        let end = lines[index].geometryStart + lines[index].geometryCount

        guard end >= 0, end <= toolpathSegments.count else {
            return toolpathSegments[0..<0]
        }

        return toolpathSegments[0..<end]
    }

    /// O(1) counterpart to `toolpathSegments(upTo:)` for callers that only
    /// need to know *how much* of the rapid/cutting toolpath is visible at
    /// `line`, not which segments — the scrub slider, which wants to narrow
    /// an already-uploaded GPU buffer rather than re-tessellate a prefix on
    /// every tick. Same line→segment-index bookkeeping as
    /// `toolpathSegments(upTo:)`, just a prefix-sum lookup instead of a slice.
    func toolpathVertexCounts(upTo line: Int) -> (rapid: Int, cutting: Int) {

        guard line >= 1, !lines.isEmpty else {
            return (0, 0)
        }

        let index = min(line, lines.count) - 1
        let end = lines[index].geometryStart + lines[index].geometryCount

        guard end >= 0, end < rapidVertexPrefix.count else {
            return (0, 0)
        }

        return (rapidVertexPrefix[end], cuttingVertexPrefix[end])
    }

    /// The tool/operation section (see `toolpaths`) that line `line` falls
    /// inside, if any — used to figure out which `T` number is actually
    /// running for whatever line is currently scrubbed to or being executed.
    /// `toolpaths` is only ever dozens of entries even for a large program,
    /// so a linear scan is simpler than maintaining another index and no
    /// slower in practice.
    func toolpath(containingLine line: Int) -> GCodeToolpath? {
        toolpaths.first { line >= $0.startLine && line <= $0.endLine }
    }

    // MARK: Machine line lookup

    /// Returns the table row corresponding to a machine P: line number.
    ///
    /// P: values are 1-based, so this simply converts to a zero-based array
    /// index.
    func tableIndex(forMachineLine lineNumber: Int) -> Int? {

        let index = lineNumber - 1

        guard index >= 0, index < lines.count else {
            return nil
        }

        return index
    }

    // MARK: Clear

    func clear() {

        loadTask?.cancel()
        loadTask = nil

        fileURL = nil
        fileName = "No file loaded"

        lines.removeAll()
        toolpathSegments.removeAll()
        rapidVertexPrefix = [0]
        cuttingVertexPrefix = [0]
        tools.removeAll()
        toolpaths.removeAll()
        loadedHeader = nil

        lastError = nil
        isLoading = false
    }
}
