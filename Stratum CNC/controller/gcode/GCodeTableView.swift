//
//  GCodeTableView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import AppKit

extension NSUserInterfaceItemIdentifier {
    static let lineNumberColumn = NSUserInterfaceItemIdentifier("lineNumberColumn")
    static let lineTextColumn = NSUserInterfaceItemIdentifier("lineTextColumn")
}

/// Wraps a real NSTableView in an NSScrollView. Rows are addressed by integer
/// index and cell views are reused, keeping the G-code viewer suitable for
/// very large files.
struct GCodeTableView: NSViewRepresentable {
    @ObservedObject var document: NCFileDocument
    var highlightedLine: Int?
    var requestedLine: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.rowHeight = 20
        tableView.usesAutomaticRowHeights = false

        let lineNumberColumn = NSTableColumn(identifier: .lineNumberColumn)
        lineNumberColumn.width = 56
        lineNumberColumn.minWidth = 40
        lineNumberColumn.maxWidth = 90
        lineNumberColumn.resizingMask = []
        tableView.addTableColumn(lineNumberColumn)

        let textColumn = NSTableColumn(identifier: .lineTextColumn)
        textColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(textColumn)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.document = document

        if coordinator.lastRowCount != document.lines.count {
            coordinator.lastRowCount = document.lines.count
            coordinator.tableView?.reloadData()
        }

        if coordinator.lastHighlightedLine != highlightedLine {
            let previous = coordinator.lastHighlightedLine
            coordinator.lastHighlightedLine = highlightedLine

            var rowsToReload = IndexSet()
            if let previous, previous >= 1, previous <= document.lines.count {
                rowsToReload.insert(previous - 1)
            }
            if let current = highlightedLine, current >= 1, current <= document.lines.count {
                rowsToReload.insert(current - 1)
                coordinator.tableView?.scrollRowToVisible(current - 1)
            }
            if !rowsToReload.isEmpty, let tableView = coordinator.tableView {
                tableView.reloadData(
                    forRowIndexes: rowsToReload,
                    columnIndexes: IndexSet(integersIn: 0..<tableView.tableColumns.count)
                )
            }
        }

        // A toolpath selection requests a one-time jump to the toolpath's
        // first G-code line. This is deliberately separate from
        // highlightedLine, which may be driven by a running CNC job.
        if coordinator.lastRequestedLine != requestedLine {
            coordinator.lastRequestedLine = requestedLine
            if let line = requestedLine, line >= 1, line <= document.lines.count {
                coordinator.tableView?.scrollRowToVisible(line - 1)
                coordinator.selectRow(line - 1)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var document: NCFileDocument
        weak var tableView: NSTableView?
        var lastRowCount = -1
        var lastHighlightedLine: Int?
        var lastRequestedLine: Int?

        init(document: NCFileDocument) {
            self.document = document
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.lines.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < document.lines.count, let columnID = tableColumn?.identifier else {
                return nil
            }

            let line = document.lines[row]
            let cellID = NSUserInterfaceItemIdentifier("cell-\(columnID.rawValue)")

            let textField: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                textField = reused
            } else {
                textField = NSTextField(string: "")
                textField.identifier = cellID
                textField.isBordered = false
                textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                textField.lineBreakMode = .byTruncatingTail
                textField.focusRingType = .none
            }

            let isHighlighted = (line.id == lastHighlightedLine)

            if columnID == .lineNumberColumn {
                textField.stringValue = "\(line.id)"
                textField.alignment = .right
                textField.textColor = .tertiaryLabelColor
                textField.isEditable = false
                textField.isSelectable = false
                textField.delegate = nil
                textField.tag = -1
            } else {
                textField.stringValue = line.text
                textField.alignment = .left
                textField.textColor = .labelColor
                textField.isEditable = false
                textField.isSelectable = true
                textField.delegate = self
                textField.tag = row
            }

            textField.drawsBackground = isHighlighted
            textField.backgroundColor = isHighlighted
                ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                : .clear

            return textField
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField, textField.tag >= 0 else {
                return
            }
            document.updateLine(at: textField.tag, text: textField.stringValue)
        }

        func selectRow(_ row: Int) {
            guard let tableView, row >= 0, row < tableView.numberOfRows else {
                return
            }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
}
