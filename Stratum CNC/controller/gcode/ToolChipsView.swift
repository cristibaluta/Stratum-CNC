//
//  ToolChipsView.swift
//  Stratum CNC
//
//  The tools the loaded program calls, as a horizontally scrolling row of
//  chips: "● T2  1/4" Ball Nose  Ø6.35". Each chip is a menu that assigns a
//  `ToolSpec` (same options `ToolsPickerView` offered: Unassigned, the
//  file's own spec, then the library). The chip for the tool currently in
//  the spindle at the scrub position is tinted green and scrolled into view.
//

import SwiftUI

struct ToolChipsView: View {

    let tools: [Int]
    @Binding var assignments: [Int: ToolSpec]
    /// Specs the loaded file's header declares, by tool number — offered
    /// first, since it's what the CAM actually used.
    var fileSpecs: [Int: ToolSpec] = [:]
    /// `GCodeStore.activeToolNumber`.
    var activeTool: Int? = nil
    /// Where the chips sit while they all fit. `.trailing` pushes them to the
    /// right edge of the available width; once they overflow they scroll
    /// either way.
    var alignment: Alignment = .leading

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(tools, id: \.self) { tool in
                            chip(for: tool)
                                .id(tool)
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(minWidth: geo.size.width, alignment: alignment)
                }
                .scrollIndicators(.automatic)
                .onChange(of: activeTool) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private func chip(for tool: Int) -> some View {
        let spec = assignments[tool]
        let isActive = tool == activeTool

        return Menu {
            Picker("", selection: binding(for: tool)) {
                Text("Unassigned").tag(ToolSpec?.none)
                if let fileSpec = fileSpecs[tool] {
                    Divider()
                    Text("\(fileSpec.name) (from file)").tag(ToolSpec?.some(fileSpec))
                }
                Divider()
                ForEach(ToolSpec.library) { library in
                    Text(library.name).tag(ToolSpec?.some(library))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isActive ? Color.green : Color.clear)
                    .frame(width: 6, height: 6)

                Text("T\(tool)")
                    .font(.caption.bold())
                    .foregroundColor(isActive ? .primary : .secondary)

                if let spec {
                    Text(spec.name)
                        .font(.caption)
                    Text("Ø\(diameter(spec.diameterMM))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Unassigned")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.green.opacity(0.16) : Color.primary.opacity(0.07))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose the tool for T\(tool)")
    }

    private func binding(for tool: Int) -> Binding<ToolSpec?> {
        Binding(
            get: { assignments[tool] },
            set: { assignments[tool] = $0 }
        )
    }

    private func diameter(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
