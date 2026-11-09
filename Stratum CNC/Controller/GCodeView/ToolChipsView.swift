//
//  ToolChipsView.swift
//  Stratum CNC
//
//  The tools the loaded program calls, as a horizontally scrolling row of
//  chips: a large tool number, then the diameter over the tool type on two
//  lines ("T2  Ø6.35 mm / Ball Nose"). Each chip is a menu that assigns a
//  tool in a popover (Unassigned, the file's own tool, then the tools library).
//  The chip for the tool currently in the spindle at the scrub position is
//  outlined and filled green, marked with
//  a little triangle under it, and scrolled into view. The chips use the whole
//  height of the bar they sit in.
//

import SwiftUI

struct ToolChipsView: View {

    let tools: [Int]
    @Binding var assignments: [Int: Tool]
    /// Tools the loaded file's header declares, by tool number — offered
    /// first, since it's what the CAM actually used.
    var fileTools: [Int: Tool] = [:]
    /// The tools library the chooser lists. A closure, read when the chooser opens, so it is
    /// current even if the library changed since this view was last drawn.
    var library: () -> [Tool] = { [] }
    /// `GCodeStore.activeToolNumber`.
    var activeTool: Int? = nil
    /// Where the chips sit while they all fit. `.trailing` pushes them to the
    /// right edge of the available width; once they overflow they scroll
    /// either way.
    var alignment: Alignment = .leading

    /// The tool to mark as current: the one in the spindle at the scrub
    /// position, or — before the program's first tool change — the first tool
    /// it calls, so there is always one marked.
    private var currentTool: Int? {
        activeTool ?? tools.first
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(tools, id: \.self) { tool in
                            chip(for: tool)
                                .id(tool)
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: alignment)
                }
                .scrollIndicators(.automatic)
                .onChange(of: currentTool) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private func chip(for tool: Int) -> some View {
        ToolChip(tool: tool,
                 assigned: assignments[tool],
                 fileTool: fileTools[tool],
                 library: library,
                 isCurrent: tool == currentTool,
                 select: { assignments[tool] = $0 })
    }
}

/// One chip. Drawn as ordinary views inside a plain `Button` that opens a
/// popover — not as the label of a `Menu`: on macOS a menu flattens a custom
/// label down to its first text, which left only "T1" on screen.
private struct ToolChip: View {

    let tool: Int
    let assigned: Tool?
    let fileTool: Tool?
    let library: () -> [Tool]
    let isCurrent: Bool
    let select: (Tool?) -> Void

    @State private var isChoosing = false

    var body: some View {
        Button {
            isChoosing.toggle()
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 10) {
                    Text("T\(tool)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(isCurrent ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        if let assigned {
                            Text("Ø\(Self.diameter(assigned.toolDiameter)) mm")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(isCurrent ? .primary : .secondary)
                            Text(Self.typeText(for: assigned))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unassigned")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                            Text("Choose tool")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCurrent ? Color.green.opacity(0.2) : Color.primary.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isCurrent ? Color.green : Color.clear, lineWidth: 1.5)
                )

                // Marks the current tool; transparent on the others so every
                // chip keeps the same height.
                DownTriangle()
                    .fill(isCurrent ? Color.green : Color.clear)
                    .frame(width: 12, height: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Choose the tool for T\(tool)")
        .popover(isPresented: $isChoosing, arrowEdge: .bottom) {
            chooser
        }
    }

    private var chooser: some View {
        // By type, then diameter, so similar tools sit together.
        let tools = library().sorted { a, b in
            if a.type != b.type {
                return a.type.displayName < b.type.displayName
            }
            if a.toolDiameter != b.toolDiameter {
                return a.toolDiameter < b.toolDiameter
            }
            return a.name < b.name
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                option("Unassigned", value: nil)
                if let fileTool {
                    Divider().padding(.vertical, 2)
                    option("\(fileTool.name) (from file)", subtitle: fileTool.displayName, value: fileTool)
                }
                Divider().padding(.vertical, 2)
                if tools.isEmpty {
                    Text("The tools library is empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                }
                ForEach(tools) { tool in
                    option(tool.name, subtitle: tool.displayName, value: tool)
                }
            }
            .padding(8)
        }
        .frame(width: 260, height: 300)
    }

    private func option(_ title: String, subtitle: String? = nil, value: Tool?) -> some View {
        Button {
            select(value)
            isChoosing = false
        } label: {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(assigned?.id == value?.id ? 1 : 0)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.callout)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }

    /// "Ball Nose", or "60° V Bit" for cone-tipped tools.
    static func typeText(for tool: Tool) -> String {
        if let angle = tool.geometry.tipAngle, tool.type.shape == .cone {
            return "\(Int(angle))° \(tool.type.displayName)"
        }
        return tool.type.displayName
    }

    static func diameter(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}

private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
