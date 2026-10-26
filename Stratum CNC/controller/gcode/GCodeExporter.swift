//
//  GCodeExporter.swift
//  Stratum CNC
//
//  Saves the G-code shown in the Controller to a file the user picks.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum GCodeExporter {

    private static let knownExtensions: Set<String> = ["nc", "ngc", "gcode", "cnc", "tap"]

    /// Asks where to save, then writes the program as plain text — the same text, line for line,
    /// that "Send to Machine" uploads.
    /// - Parameter suggestedName: the name offered in the panel, without extension. When nil, the
    ///   loaded document's own name is used.
    static func export(_ document: NCFileDocument, suggestedName: String? = nil) {
        guard !document.lines.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export G-code"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        // Machines and CAM tools use a handful of extensions; don't force one.
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = [UTType(filenameExtension: "nc") ?? .plainText]
        panel.nameFieldStringValue = fileName(for: document, suggestedName: suggestedName)
        if let folder = document.fileURL?.deletingLastPathComponent() {
            panel.directoryURL = folder
        }

        // Written as the program is now, not as it will be when the panel is dismissed.
        let text = programText(of: document)

        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                document.lastError = "Couldn't export G-code: \(error.localizedDescription)"
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }

    /// The program text, one line per G-code line and a closing newline.
    private static func programText(of document: NCFileDocument) -> String {
        document.lines.map(\.text).joined(separator: "\n") + "\n"
    }

    private static func fileName(for document: NCFileDocument, suggestedName: String?) -> String {
        let base = (suggestedName?.isEmpty == false ? suggestedName : nil) ?? document.fileName
        let ext = (base as NSString).pathExtension.lowercased()
        return knownExtensions.contains(ext) ? base : base + ".nc"
    }
}
