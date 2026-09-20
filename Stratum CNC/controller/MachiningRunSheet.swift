//
//  MachiningRunSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import SwiftUI
import StratumCAM

/// Pre-run review sheet presented from `GCodeViewer`'s Play/"Send to
/// Machine" button, before anything is actually uploaded to the machine.
///
/// Mirrors what MakerStudio's "Machining Wizard" spreads across five tabs
/// (Set Stock / Set Origin / Auto Probe / Assist Options / Run) — but as one
/// fixed two-column view instead of a tab flow, since every one of those
/// settings is small enough to review at a glance together, without
/// scrolling. Unlike MakerStudio's "Set Origin" tab, the origin section here
/// is read-only: this app sets the job origin from the canvas's XY offset
/// control (`XYOffsetControlView`), not from this sheet, so it's shown as
/// info text only — change it on the canvas, then reopen this sheet (or just
/// re-check the number here) before starting.
///
/// Sections are split by hand into `leftColumn`/`rightColumn` rather than
/// auto-flowed, so the two columns stay visually balanced (a right column of
/// mostly toggles reads taller per row than the info-only left column). A
/// new section later is just one more call in whichever column has room —
/// or, past a certain point, a third column is a straightforward addition
/// alongside these two.
///
/// Reads `ControllerModel`/`GCodeStore`/`CAMModel` directly rather than
/// taking a narrower set of bindings — same reasoning as `PanelProbe`/
/// `PanelAccessories` elsewhere in this app, which all take the whole model.
struct MachiningRunSheet: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var gCodeModel: GCodeStore
    @ObservedObject var camModel: CAMModel

    @Environment(\.dismiss) private var dismiss

    /// Same gate `GCodeViewer.canStartJob` uses — duplicated rather than
    /// shared because that one is `private` to the view it disables buttons
    /// in; both read the same three properties.
    private var canStartJob: Bool {
        model.connection.isConnected && !model.uploader.isActive && !gCodeModel.document.lines.isEmpty
    }

    private var offset: SIMD2<Float> { model.scene.xyOffset }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    stockSection
                    originSection
                    toolsSection
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 16) {
                    autoProbeSection
                    assistOptionsSection
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(16)

            if let warning = blockingWarning {
                warningBanner(warning)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()

            footer
        }
        .frame(width: 640, height: 460)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review & Start")
                    .font(.headline)
                Text(gCodeModel.document.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                model.uploadJob(
                    fileName: gCodeModel.document.fileName,
                    contents: gCodeModel.document.lines.map { $0.text }.joined(separator: "\n")
                )
                dismiss()
            } label: {
                Label("Start Job", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canStartJob)
        }
        .padding(16)
    }

    // MARK: - Stock

    /// Prefers the loaded file's own header (what the CAM program actually
    /// says it was cut for — `StockSpec`, mm) over the canvas's stock
    /// picker, falling back to the picker only when the header says nothing
    /// (see `GCodeHeader.stock`'s doc comment). Either way this is read-only
    /// here — the picker itself (`MaterialPanelView`) lives on the canvas
    /// toolbar, not in this sheet.
    private var stockSection: some View {
        section("STOCK", systemImage: "cube") {
            if let stock = gCodeModel.document.loadedHeader?.stock {
                infoRow("Size", "\(format(stock.sizeX)) × \(format(stock.sizeY)) × \(format(stock.sizeZ)) mm")
                if let material = stock.material {
                    infoRow("Material", material)
                }
                Text("From the file's header")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                switch camModel.selectedStockMaterial.geometry {
                    case let .rectangular(width, height, depth):
                        infoRow("Size", "\(format(width)) × \(format(height)) × \(format(depth)) mm")
                    case let .cylindrical(diameter, length):
                        infoRow("Size", "Ø\(format(diameter)) × \(format(length)) mm")
                    case let .disk(outer, inner, depth):
                        infoRow("Size", "Ø\(format(outer)) / Ø\(format(inner)) × \(format(depth)) mm")
                }
                infoRow("Material", "\(camModel.selectedStockMaterial.material)")
                Text("From the canvas stock picker")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Origin (info only — see type doc comment)

    private var originSection: some View {
        section("WORK ORIGIN", systemImage: "scope") {
            infoRow("X Offset", "\(format(offset.x)) mm")
            infoRow("Y Offset", "\(format(offset.y)) mm")
            infoRow("Z", "Current work zero (unchanged)")
            Text("Set on the canvas, not here — use the XY Offset control above the 3D view to change it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tools

    @ViewBuilder
    private var toolsSection: some View {
        if !gCodeModel.tools.isEmpty {
            section("TOOLS", systemImage: "wrench.and.screwdriver") {
                ForEach(gCodeModel.tools, id: \.self) { number in
                    HStack {
                        Text("T\(number)")
                            .font(.caption.monospaced())
                            .frame(width: 32, alignment: .leading)
                        if let spec = gCodeModel.toolSpecAssignments[number] {
                            Text(spec.summary)
                                .font(.caption)
                        } else {
                            Text("Not assigned")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Auto Probe

    private var autoProbeSection: some View {
        section("AUTO PROBE", systemImage: "arrow.down.to.line") {
            Toggle("Auto Z Height Probing", isOn: $model.autoZBeforeRun)
                .help("Probe Z and set the work Z zero at the trigger point before the job starts")

            Divider()

            Toggle("Auto Workpiece Leveling", isOn: $model.levelBeforeRun)
                .help("Probe a height-map grid over the program's cutting area before the job starts")

            if model.levelBeforeRun {
                HStack(spacing: 16) {
                    Stepper(
                        "Grid \(model.levelGridPoints)×\(model.levelGridPoints)",
                        value: $model.levelGridPoints,
                        in: 2...10
                    )
                    Stepper(
                        "Margin \(Int(model.levelMargin)) mm",
                        value: $model.levelMargin,
                        in: 0...20,
                        step: 1
                    )
                }
                .font(.caption)
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - Assist options

    private var assistOptionsSection: some View {
        section("ASSIST OPTIONS", systemImage: "wind") {
            Toggle("Auto Vacuum", isOn: Binding(
                get: { model.autoVacuumEnabled },
                set: { model.setAutoVacuum($0) }
            ))
            .help("Ties the vacuum to the spindle: on while the spindle runs, off when it stops (M331/M332)")

            // MakerStudio also offers Auto Blow, Auto Bed Clean, Anti-Static
            // and Auto Time-Lapse. None of those have a modeled command in
            // this app yet (see Roadmap) — shown disabled rather than
            // silently dropped, so the gap is visible instead of hidden.
            unsupportedToggle("Auto Blow")
            unsupportedToggle("Auto Bed Clean")
            unsupportedToggle("Anti-Static")
            unsupportedToggle("Auto Time-Lapse")

            Text("Blow / Bed Clean / Anti-Static / Time-Lapse aren't wired to a machine command yet.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func unsupportedToggle(_ title: String) -> some View {
        Toggle(title, isOn: .constant(false))
            .disabled(true)
            .foregroundStyle(.secondary)
    }

    // MARK: - Warnings

    private var blockingWarning: String? {
        if !model.connection.isConnected {
            return "Not connected to a machine."
        }
        if gCodeModel.document.lines.isEmpty {
            return "No G-code loaded."
        }
        if model.uploader.isActive {
            return "An upload is already in progress."
        }
        return nil
    }

    private func warningBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(6)
    }

    // MARK: - Shared row/section helpers

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    /// Generic over `Double`/`Float`/`CGFloat` so it works whichever numeric
    /// type `StockSpec` and `StockMaterial.geometry`'s associated values
    /// happen to use, without a cast at every call site.
    private func format<T: BinaryFloatingPoint>(_ value: T) -> String {
        let value = Double(value)
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
