//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import StratumCAM

/// A setup's toolpaths as the rows under it in the Setups panel: select, reorder by dragging,
/// tick for sending, and the row's menu. The setup row owns the chevron and the +.
struct SetupToolpaths: View {

    @ObservedObject var projectModel: ProjectModel
    /// The toolpaths of this setup, in order
    let toolpaths: [ToolpathData]
    let selectedID: UUID?

    var onSelect: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    /// "Duplicate" in a row's menu
    var onDuplicate: ((UUID) -> Void)?
    /// Called once when a drag ends. The index is within the toolpath's own setup.
    var onMove: ((UUID, Int) -> Void)?

    @StateObject private var reorder = ToolpathReorderModel()

    var body: some View {
        if toolpaths.isEmpty {
            Text("No toolpaths")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        } else {
            rows(toolpaths)
        }
    }

    // MARK: - Sending

    private var isSending: Bool {
        projectModel.isChoosingToolpathsToSend
    }

    private func toggleChecked(_ id: UUID) {
        if projectModel.uncheckedToolpathIDs.contains(id) {
            projectModel.uncheckedToolpathIDs.remove(id)
        } else {
            projectModel.uncheckedToolpathIDs.insert(id)
        }
    }

    private func send(_ toolpaths: [ToolpathData]) {
        projectModel.isChoosingToolpathsToSend = false
        projectModel.saveIfNeeded()
        projectModel.previewInController(toolpaths: toolpaths)
    }

    // MARK: - Rows

    /// One draggable list: the toolpaths of one setup (or all of them when there is a single one).
    private func rows(_ items: [ToolpathData]) -> some View {
        // The shared drag state only moves rows of the list the dragged row is in
        let ownsDrag = reorder.draggingID.map { dragging in items.contains { $0.id == dragging } } ?? false

        return VStack(alignment: .leading, spacing: ToolpathReorderModel.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, toolpath in
                let isLifted = reorder.isLifted(toolpath.id)

                toolpathRow(toolpath, at: index, count: items.count)
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
                    .offset(y: ownsDrag ? reorder.yOffset(for: toolpath.id, at: index) : 0)
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

    private func toolpathRow(_ toolpath: ToolpathData, at index: Int, count: Int) -> some View {
        let isSelected = toolpath.id == selectedID

        let isChecked = !projectModel.uncheckedToolpathIDs.contains(toolpath.id)

        return HStack(spacing: 6) {
            if isSending {
                Button {
                    toggleChecked(toolpath.id)
                } label: {
                    checkboxImage(state: isChecked ? .all : .none)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isChecked ? "Untick" : "Tick")
            }

            OperationIcon(kind: toolpath.operation.kind, isRest: toolpath.operation.isRest, size: 12)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(toolpath.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The tool's diameter and where the toolpath ends, as one muted, right-aligned
            // label: "Ø6 · Z−0.35". The name gives way when narrow.
            Text("Ø\(Self.diameterText(of: toolpath)) · Z\(Self.endZText(of: toolpath))")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .help("Tool: \(toolpath.tool.name) · final Z \(Self.endZText(of: toolpath))")
        }
        .font(.system(size: 11))
        .lineLimit(1)
        // An unticked toolpath is left out of what gets sent
        .opacity(isSending && !isChecked ? 0.45 : 1)
        .inspectorListRow(isSelected: isSelected)
        // The whole cell is the drag target and the select target. A tap and a drag on the
        // same view don't fight: the drag only starts after a few points of movement.
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(toolpath.id)
        }
        .gesture(dragGesture(for: toolpath, at: index, count: count))
        .contextMenu {
            Button {
                onDuplicate?(toolpath.id)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                send([toolpath])
            } label: {
                Label("Send to controller", systemImage: "paperplane")
            }
            Divider()
            Button(role: .destructive) {
                onDelete?(toolpath.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private static func diameterText(of toolpath: ToolpathData) -> String {
        Double(toolpath.tool.toolDiameter).formatted(
            .number
            .precision(.fractionLength(0...3))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    /// A counterbore keeps its depth apart from `endZ`, as a positive number below the top.
    private static func endZText(of toolpath: ToolpathData) -> String {
        let z = toolpath.operation.kind == .counterbore
            ? -toolpath.operation.counterboreDepth
            : toolpath.endZ
        // Depth below the top, so shown without the sign: "1.5"
        return number(z)
    }

    /// A real minus sign (U+2212) for negatives, so "−0.35" reads as a number next to "Z".
    private static func number(_ value: Double) -> String {
        value.formatted(
            .number
            .precision(.fractionLength(0...2))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX"))
        )
        .replacingOccurrences(of: "-", with: "\u{2212}")
    }

    // MARK: - Reordering

    private func dragGesture(for toolpath: ToolpathData, at index: Int, count: Int) -> some Gesture {
        // Measured in the list's own space: the row moves under the pointer while it is
        // dragged, so a translation in the row's space would feed back into itself.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ToolpathReorderModel.listSpace))
            .onChanged { value in
                reorder.dragChanged(id: toolpath.id,
                                    index: index,
                                    translation: value.translation.height,
                                    count: count)
            }
            .onEnded { value in
                reorder.dragEnded(id: toolpath.id,
                                  translation: value.translation.height,
                                  count: count) { id, target in
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

/// A setup's orientation as a small picture: the stock seen from the machine's right (front of
/// the machine on the left, back on the right), with a bar on the side that faces up. It is drawn
/// from the angle, so a rotary index lands between the faces without a new asset.
struct SetupGlyph: View {

    /// Rotation of the stock about X (or Y: seen from the front), degrees (see `Setup.angle`).
    let angle: Double

    var body: some View {
        Canvas { context, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            context.stroke(Path(roundedRect: box, cornerRadius: 2), with: .color(.secondary), lineWidth: 1)

            // Where the up direction leaves the stock: Rx(θ)·ẑ = (0, −sin θ, cos θ) in (Y, Z), and Y is
            // to the right and Z up on screen.
            let radians = angle.inRadians
            let direction = CGPoint(x: -sin(radians), y: -cos(radians))   // screen y points down
            let half = box.width / 2
            let center = CGPoint(x: box.midX, y: box.midY)
            let rim = CGPoint(x: center.x + direction.x * half, y: center.y + direction.y * half)
            let along = CGPoint(x: -direction.y, y: direction.x)          // along the marked side
            var bar = Path()
            bar.move(to: CGPoint(x: rim.x - along.x * half * 0.7, y: rim.y - along.y * half * 0.7))
            bar.addLine(to: CGPoint(x: rim.x + along.x * half * 0.7, y: rim.y + along.y * half * 0.7))
            context.stroke(bar, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

/// Same look as the Controller's "Refresh from CAM" button: prominent, with the refresh
/// icon, and a spinner while the program is being generated.
private struct PreviewInControllerButton: View {

    @ObservedObject var gCodeStore: GCodeStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if gCodeStore.isGeneratingFromCAM {
                ProgressView().controlSize(.small)
            } else {
                Label("Send to controller", systemImage: "paperplane")
                    .font(.system(size: 12))
            }
        }
        // Borderless and muted: it is a footer action, not the focus of the panel
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .disabled(gCodeStore.isGeneratingFromCAM)
        .help("Generate all toolpaths and open them in the Controller")
    }
}


fileprivate enum CheckState {
    case none, some, all
}

fileprivate func checkboxImage(state: CheckState) -> some View {
    Image(systemName: state == .all ? "checkmark.square.fill"
                      : state == .some ? "minus.square.fill" : "square")
        .font(.system(size: 14))
        .foregroundStyle(state == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
}

/// The bottom of the Setups panel: the send-to-controller button; in send mode the select-all
/// checkbox, with Cancel and Send at the right. `toolpaths` is every toolpath of the project.
struct ToolpathSendBar: View {

    @ObservedObject var projectModel: ProjectModel
    let toolpaths: [ToolpathData]
    /// A muted line at the right of the button, e.g. "3 setups · 6 toolpaths"
    var summary: String?

    private var isSending: Bool {
        projectModel.isChoosingToolpathsToSend
    }

    /// The toolpaths that are ticked. Everything is, until the user unticks it.
    private var checkedIDs: Set<UUID> {
        Set(toolpaths.map(\.id)).subtracting(projectModel.uncheckedToolpathIDs)
    }

    private var allCheckedState: CheckState {
        switch checkedIDs.count {
            case 0: return .none
            case toolpaths.count: return .all
            default: return .some
        }
    }

    private func setAll(checked: Bool) {
        let ids = Set(toolpaths.map(\.id))
        if checked {
            projectModel.uncheckedToolpathIDs.subtract(ids)
        } else {
            projectModel.uncheckedToolpathIDs.formUnion(ids)
        }
    }

    private func send(_ toolpaths: [ToolpathData]) {
        projectModel.isChoosingToolpathsToSend = false
        projectModel.saveIfNeeded()
        projectModel.previewInController(toolpaths: toolpaths)
    }

    var body: some View {
        HStack(spacing: 6) {
            if isSending {
                Button {
                    setAll(checked: checkedIDs.count != toolpaths.count)
                } label: {
                    HStack(spacing: 6) {
                        checkboxImage(state: allCheckedState)
                        Text("All")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(checkedIDs.count == toolpaths.count ? "Untick all" : "Tick all")

                Spacer(minLength: 4)

                Button("Cancel") {
                    projectModel.isChoosingToolpathsToSend = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button("Send") {
                    send(toolpaths.filter { checkedIDs.contains($0.id) })
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .disabled(checkedIDs.isEmpty)
                .help(checkedIDs.isEmpty ? "Tick at least one toolpath" : "Send the ticked toolpaths to the Controller")
            } else {
                PreviewInControllerButton(gCodeStore: projectModel.gCodeStore) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        projectModel.isChoosingToolpathsToSend = true
                    }
                }

                Spacer(minLength: 4)

                if let summary {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}
