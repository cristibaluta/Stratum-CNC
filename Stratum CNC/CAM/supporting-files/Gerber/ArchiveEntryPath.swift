import Foundation

enum ArchiveEntryPath {
    /// Resolve dot components before testing containment; a textual prefix alone
    /// accepts paths such as "../outside" beneath the extraction directory.
    static func destination(for entry: String, in directory: URL) -> URL? {
        let root = directory.standardizedFileURL
        let destination = root.appendingPathComponent(entry).standardizedFileURL
        guard destination.path.hasPrefix(root.path + "/") else { return nil }
        return destination
    }
}
