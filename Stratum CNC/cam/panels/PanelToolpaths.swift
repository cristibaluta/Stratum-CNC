//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

struct PanelToolpaths: View {

    let toolpaths: [ToolpathData]
    let selectedID: UUID?
    var hiddenIDs: Set<UUID> = []

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    /// Called once when a drag ends:
    var onMove: ((UUID, Int) -> Void)?

    @StateObject private var reorder = ToolpathReorderModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorHeader(title: "Toolpaths", addHelp: "Add a toolpath") {
                onAdd?()
            }

            Divider()

            if toolpaths.isEmpty {
                Text("No toolpaths")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: ToolpathReorderModel.rowSpacing) {
                    ForEach(Array(toolpaths.enumerated()), id: \.element.id) { index, toolpath in
                        let isLifted = reorder.isLifted(toolpath.id)

                        toolpathRow(toolpath, at: index)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: ToolpathRowHeightKey.self,
                                                           value: proxy.size.height)
                                }
                            )
                            .background {
                                if isLifted {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.thickMaterial)
                                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                                }
                            }
                            .offset(y: reorder.yOffset(for: toolpath.id, at: index))
                            .zIndex(toolpath.id == reorder.draggingID ? 1 : 0)
                            // The lifted row follows the pointer, so it must not animate
                            .transaction { transaction in
                                if isLifted {
                                    transaction.animation = nil
                                }
                            }
                    }
                }
                .coordinateSpace(name: ToolpathReorderModel.listSpace)
                .onPreferenceChange(ToolpathRowHeightKey.self) { height in
                    if height > 0 {
                        reorder.rowHeight = height
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Row

    private func toolpathRow(_ toolpath: ToolpathData, at index: Int) -> some View {
        let isSelected = toolpath.id == selectedID
        let isHidden = hiddenIDs.contains(toolpath.id)

        return HStack(spacing: 6) {
            OperationIcon(kind: toolpath.operation.kind, size: 13)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .opacity(isHidden ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(toolpath.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                subtitle(for: toolpath)
            }
            .opacity(isHidden ? 0.5 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)

            InspectorVisibilityButton(isVisible: !isHidden,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(toolpath.id)
            }
        }
        .inspectorListRow(isSelected: isSelected)
        // The whole cell is the drag target and the select target. A tap and a drag on the
        // same view don't fight: the drag only starts after a few points of movement.
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(toolpath.id)
        }
        .gesture(dragGesture(for: toolpath, at: index))
        .contextMenu {
            Button(role: .destructive) {
                onDelete?(toolpath.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Subtitle

    /// What the toolpath does, without the operation's name (the title already says it): the
    /// tool, how it enters, how a pocket is cleared and where it ends.
    private func subtitle(for toolpath: ToolpathData) -> some View {
        let requirements = toolpath.machiningOperation.requirements
        let entryType: RampType = toolpath.ramping.enabled ? toolpath.ramping.type : .none
        let toolText = "Ø\(Self.number(Double(toolpath.tool.toolDiameter))) \(Self.title(of: toolpath.tool.type))"

        return HStack(spacing: 6) {
            // The one that gives way when the row is narrow; the icons and the depth keep their size
            Text(toolText)
                .lineLimit(1)
                .help("Tool: \(toolpath.tool.name)")

            if let side = Self.cutSide(of: toolpath) {
                ContourTypeGlyph(position: side, tint: .secondary)
                    .frame(width: 20, height: 13)
                    .help("Side: \(side.label)")
            }

            if requirements.usesEntry {
                // The glyph is drawn in absolute points (18x14), so it is scaled down, not resized
                RampTypeGlyph(type: entryType, tint: .secondary)
                    .frame(width: 18, height: 14)
                    .scaleEffect(0.65)
                    .frame(width: 12, height: 9)
                    .help("Entry: \(entryType.title)")
            }

            if !requirements.pocketPatterns.isEmpty {
                PatternGlyph(pattern: toolpath.operation.pocketPattern, tint: .secondary)
                    .frame(width: 18, height: 14)
                    .help("Pocketing: \(toolpath.operation.pocketPattern.rawValue)")
            }

            if toolpath.operation.kind == .restMachining {
                // Linked to a pocket instead of shapes
                let source = toolpaths.first { $0.id == toolpath.operation.restSourceID }
                Label(source?.name ?? "Source missing", systemImage: "link")
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(source == nil ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .help(source.map { "Cuts the corners of \($0.name)" } ?? "The pocket this belongs to was deleted")
            } else if !toolpath.cutsWholeStock {
                // The same hint as in the details panel: orange while nothing is selected yet
                Label("\(toolpath.targets.count)", systemImage: "cursorarrow.click")
                    .labelStyle(CompactLabelStyle())
                    .foregroundStyle(toolpath.hasGeometry ? Color.secondary : Color.orange)
                    .fixedSize()
                    .help(toolpath.targets.count == 1 ? "1 shape selected" : "\(toolpath.targets.count) shapes selected")
            }

            Text(Self.endZText(of: toolpath))
                .lineLimit(1)
                .fixedSize()
                .help("End Z")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    /// The side of the shape the tool follows, for the operations that have one.
    private static func cutSide(of toolpath: ToolpathData) -> SC.CutSide? {
        switch toolpath.operation.kind {
            case .contour: return toolpath.contour
            case .chamfer: return toolpath.operation.chamferSide.position
            default:       return nil
        }
    }

    /// A counterbore keeps its depth apart from `endZ`, as a positive number below the top.
    private static func endZText(of toolpath: ToolpathData) -> String {
        let z = toolpath.operation.kind == .counterbore
            ? -toolpath.operation.counterboreDepth
            : toolpath.endZ
        // Depth below the top, so shown without the sign: "Z1.5"
        return "Z\(number(abs(z)))"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func title(of type: ToolType) -> String {
        switch type {
            case .endMill:           return "End mill"
            case .ballNose:          return "Ball nose"
            case .engraving:         return "Engraving"
            case .drill:             return "Drill"
            case .vBit:              return "V-bit"
            case .corn:              return "Corn"
            case .chamfer:           return "Chamfer"
            case .solderMaskRemover: return "Solder mask"
            case .threadMill:        return "Thread mill"
        }
    }

    // MARK: - Reordering

    private func dragGesture(for toolpath: ToolpathData, at index: Int) -> some Gesture {
        // Measured in the list's own space: the row moves under the pointer while it is
        // dragged, so a translation in the row's space would feed back into itself.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ToolpathReorderModel.listSpace))
            .onChanged { value in
                reorder.dragChanged(id: toolpath.id,
                                    index: index,
                                    translation: value.translation.height,
                                    count: toolpaths.count)
            }
            .onEnded { value in
                reorder.dragEnded(id: toolpath.id,
                                  translation: value.translation.height,
                                  count: toolpaths.count) { id, target in
                    onMove?(id, target)
                }
            }
    }
}

/// The height of a toolpath row, so the drag knows how far a slot is.
private struct ToolpathRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Icon and text close together, for the row's subtitle.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
