//
//  OpenHistory.swift
//  Stratum CNC
//
//  Every G-code file and project the user has opened, with when, kept in
//  `history.json` next to `projects.json`. The splash page's history buttons
//  and File > Open Recent show the latest ten of each kind.
//
//  Each entry carries a security-scoped bookmark, so a file or folder picked
//  once can be reopened after a relaunch without asking again (the sandbox
//  forgets the access otherwise).
//

import SwiftUI

struct OpenHistoryEntry: Codable, Identifiable, Hashable {

    enum Kind: String, Codable {
        case gcode
        case project
    }

    var id: UUID = UUID()
    var kind: Kind
    /// Last known path. Shown in the menus, and the fallback when there is no bookmark.
    var path: String
    /// Security-scoped bookmark to the file or project folder.
    var bookmark: Data?
    /// For projects: the id inside `project.json` / `projects.json`, so a project
    /// that is still in the list reopens through the list instead of being re-added.
    var projectID: UUID?
    var openedAt: Date
}

@MainActor
final class OpenHistory: ObservableObject {

    static let shared = OpenHistory()

    /// How many items of each kind the menus show.
    static let menuLimit = 10
    /// History is kept well past what the menus show, but not forever.
    private static let storageLimit = 500

    /// Newest first.
    @Published private(set) var entries: [OpenHistoryEntry] = []

    private let file: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL = ProjectPaths.appDocuments) {
        file = directory.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    // MARK: - Reading

    /// The latest items of one kind, newest first.
    func recent(_ kind: OpenHistoryEntry.Kind, limit: Int = OpenHistory.menuLimit) -> [OpenHistoryEntry] {
        Array(entries.lazy.filter { $0.kind == kind }.prefix(limit))
    }

    // MARK: - Recording

    /// Call right after a G-code file was picked or opened. Access to `url` must be
    /// available, since the bookmark is made from it.
    func recordGCode(url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let path = url.standardizedFileURL.path
        let bookmark = try? ProjectBookmark.make(for: url)
        upsert(kind: .gcode, path: path, bookmark: bookmark, projectID: nil) {
            $0.path == path
        }
    }

    /// Call when a project was opened. External projects pass their own bookmark.
    func recordProject(_ project: Project, path: String) {
        upsert(kind: .project, path: path, bookmark: project.bookmark, projectID: project.id) {
            $0.projectID == project.id
        }
    }

    private func upsert(kind: OpenHistoryEntry.Kind,
                        path: String,
                        bookmark: Data?,
                        projectID: UUID?,
                        isSame: (OpenHistoryEntry) -> Bool) {
        var entry: OpenHistoryEntry
        if let index = entries.firstIndex(where: { $0.kind == kind && isSame($0) }) {
            entry = entries.remove(at: index)
        } else {
            entry = OpenHistoryEntry(kind: kind, path: path, bookmark: bookmark, projectID: projectID, openedAt: .now)
        }
        entry.path = path
        // A bookmark that couldn't be made this time doesn't wipe a working one.
        entry.bookmark = bookmark ?? entry.bookmark
        entry.projectID = projectID ?? entry.projectID
        entry.openedAt = .now

        entries.insert(entry, at: 0)
        if entries.count > Self.storageLimit {
            entries.removeLast(entries.count - Self.storageLimit)
        }
        save()
    }

    // MARK: - Resolving

    /// The file or folder an entry points to, through its bookmark. A bookmark that
    /// followed a move, or went stale, is refreshed in the history. Entries without a
    /// bookmark fall back to their path. The caller still has to start access on the URL.
    func resolveURL(for entry: OpenHistoryEntry) throws -> URL {
        guard let data = entry.bookmark else {
            return URL(fileURLWithPath: entry.path)
        }
        let resolved = try ProjectBookmark.resolve(data)
        let url = resolved.url

        if resolved.isStale || url.standardizedFileURL.path != entry.path,
           let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if resolved.isStale, let fresh = try? ProjectBookmark.make(for: url) {
                entries[index].bookmark = fresh
            }
            entries[index].path = url.standardizedFileURL.path
            save()
        }
        return url
    }

    // MARK: - Removing

    func remove(_ entry: OpenHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// "Clear Menu": forgets one kind of entries.
    func clear(_ kind: OpenHistoryEntry.Kind) {
        entries.removeAll { $0.kind == kind }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: file) else {
            return
        }
        do {
            entries = try decoder.decode([OpenHistoryEntry].self, from: data)
                .sorted { $0.openedAt > $1.openedAt }
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func save() {
        do {
            try encoder.encode(entries).write(to: file, options: .atomic)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}

// MARK: - Display

extension OpenHistoryEntry {

    /// The path as shown in a menu: home as `~`, and cut in the middle when long.
    func menuTitle(maxLength: Int = 52) -> String {
        Self.abbreviatedHome(path).trimmedInMiddle(maxLength: maxLength)
    }

    private static func abbreviatedHome(_ path: String) -> String {
        #if os(macOS)
        // `NSHomeDirectory()` is the sandbox container; the real home comes from the user database.
        if let pw = getpwuid(getuid()) {
            let home = String(cString: pw.pointee.pw_dir)
            if path == home || path.hasPrefix(home + "/") {
                return "~" + path.dropFirst(home.count)
            }
        }
        #endif
        return path
    }
}

extension String {

    /// Shortens to `maxLength` characters by replacing the middle with "…". A path keeps
    /// its last component (the file or folder name) whole whenever it fits, since
    /// that is what tells entries apart.
    func trimmedInMiddle(maxLength: Int) -> String {
        guard count > maxLength, maxLength > 3 else {
            return self
        }
        let lastComponent = split(separator: "/", omittingEmptySubsequences: true).last.map { $0.count + 1 } ?? 0
        let tail = min(max(lastComponent, maxLength / 2), maxLength - 8)
        let head = maxLength - 1 - tail
        return String(prefix(head)) + "…" + String(suffix(tail))
    }
}

// MARK: - Menus

/// The items of one history menu. Shared by the splash page buttons and the File menu.
struct RecentItemsMenuContent: View {

    @ObservedObject var history: OpenHistory
    let kind: OpenHistoryEntry.Kind
    let onOpen: (OpenHistoryEntry) -> Void

    var body: some View {
        let items = history.recent(kind)
        if items.isEmpty {
            Button("No Recent Items") {}
                .disabled(true)
        } else {
            ForEach(items) { entry in
                Button(entry.menuTitle()) {
                    onOpen(entry)
                }
            }
            Divider()
            Button("Clear Menu") {
                history.clear(kind)
            }
        }
    }
}

/// The small button on the right of a Quick Start row that opens its history.
struct RecentHistoryButton: View {

    @ObservedObject var history: OpenHistory
    let kind: OpenHistoryEntry.Kind
    let onOpen: (OpenHistoryEntry) -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            RecentItemsMenuContent(history: history, kind: kind, onOpen: onOpen)
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: Self.width, height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: Self.width)
        .help(kind == .gcode ? "Recent G-code files" : "Recent projects")
        .onHover { isHovered = $0 }
    }

    static let width: CGFloat = 30
}
