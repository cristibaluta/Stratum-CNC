//
//  MachiningRunSheet.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//

import SwiftUI
import StratumCAM
import StratumLink

/// Pre-run review sheet presented from `GCodeViewer`'s Play/"Send to
/// Machine" button, before anything is actually uploaded to the machine.
///
/// Mirrors what MakerStudio's "Machining Wizard" spreads across five tabs
/// (Set Stock / Set Origin / Auto Probe / Assist Options / Run) — but as one
/// fixed two-column view instead of a tab flow, since every one of those
/// settings is small enough to review at a glance together, without
/// scrolling. Unlike MakerStudio's "Set Origin" tab, the origin section here
/// is read-only: this app sets the job origin from the canvas's XY offset
/// control (`JobAreaSettingsView`), not from this sheet, so it's shown as
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
    /// Observed directly, not just through `model`, so the warning banner
    /// reacts live if the connection drops while this sheet is already
    /// open — same reasoning as `GCodeViewer`/`MachineConnectSheet` observing
    /// it directly rather than through `ControllerModel`.
    @ObservedObject var connection: SL.Connection

    @Environment(\.dismiss) private var dismiss

    /// Same gate `GCodeViewer.canStartJob` uses — duplicated rather than
    /// shared because that one is `private` to the view it disables buttons
    /// in; both read the same three properties.
    private var canStartJob: Bool {
        !readinessChecks.contains { $0.state == .blocked }
    }

    private enum CheckState { case ok, warning, blocked }

    private struct ReadinessCheck: Identifiable {
        let id: String
        let state: CheckState
        let title: String
        var actionTitle: String? = nil
        var action: (() -> Void)? = nil
        var actionDisabled = false
    }

    /// Real, live checks only — nothing here is assumed to pass. `.blocked`
    /// disables Start Job; `.warning` is shown but doesn't block (e.g. a tool
    /// with no spec only limits the preview, the machine can still run it).
    private var readinessChecks: [ReadinessCheck] {
        var checks: [ReadinessCheck] = []
        let lines = gCodeModel.document.lines

        if connection.isConnected {
            checks.append(.init(id: "connection", state: .ok, title: "Machine connected"))
        } else {
            checks.append(.init(id: "connection", state: .blocked, title: "No machine connected",
                                actionTitle: "Select Machine…", action: {
                // Swaps this sheet for `MachineConnectSheet` rather than stacking
                // a second one; it hands back to a fresh review sheet once connected.
                dismiss()
                model.isShowingMachinePicker = true
            }))
        }

        if lines.isEmpty {
            checks.append(.init(id: "gcode", state: .blocked, title: "No G-code loaded"))
        } else {
            let count = gCodeModel.document.toolpaths.count
            checks.append(.init(id: "gcode", state: .ok,
                                title: "\(lines.count) lines · \(count) toolpath\(count == 1 ? "" : "s")"))
        }

        let machineBusy = connection.isConnected && connection.status?.isBusy == true
        if machineBusy {
            checks.append(.init(id: "busy", state: .blocked, title: "Machine is busy with another job"))
        }

        if !lines.isEmpty {
            checks.append(sentCheck(canSend: connection.isConnected && !machineBusy))
        }

        let unassigned = gCodeModel.tools.filter { gCodeModel.toolSpecAssignments[$0] == nil }
        if !unassigned.isEmpty {
            let list = unassigned.map { "T\($0)" }.joined(separator: ", ")
            checks.append(.init(id: "tools", state: .warning, title: "No tool assigned for \(list)"))
        } else if !gCodeModel.tools.isEmpty {
            checks.append(.init(id: "tools", state: .ok, title: "Tools assigned"))
        }
        return checks
    }

    /// Fingerprint of the program as it is now. The sheet is modal, so the
    /// document can't change while it is open — computed once on appear
    /// rather than per render (hashing a large program isn't free).
    @State private var currentFingerprint: String?

    private var isSent: Bool {
        currentFingerprint != nil && currentFingerprint == model.sentJobFingerprint
    }

    private func sendNow() {
        model.sendJob(
            fileName: gCodeModel.document.fileName,
            contents: gCodeModel.document.lines.map { $0.text }.joined(separator: "\n")
        )
    }

    /// "Sent" is tracked for this app session only, by content: nothing is
    /// read back from the machine's SD card, since a file with the same name
    /// there isn't proof it holds this code.
    private func sentCheck(canSend: Bool) -> ReadinessCheck {
        if model.uploader.isActive {
            var title = "Sending to machine…"
            if case let .transferring(sent, total) = model.uploader.state, total > 0 {
                title = "Sending to machine… \(Int(Double(sent) / Double(total) * 100))%"
            }
            return .init(id: "sent", state: .blocked, title: title)
        }
        if isSent {
            return .init(id: "sent", state: .ok, title: "G-code sent to machine")
        }
        if case let .failed(message) = model.uploader.state {
            return .init(id: "sent", state: .blocked, title: "Send failed: \(message)",
                         actionTitle: "Retry", action: sendNow, actionDisabled: !canSend)
        }
        let wasEdited = model.sentJobFingerprint != nil
        return .init(id: "sent", state: .blocked,
                     title: wasEdited ? "G-code changed since it was sent" : "G-code not sent to machine yet",
                     actionTitle: "Send to Machine", action: sendNow, actionDisabled: !canSend)
    }

    /// What gets sent: where the G-code's own 0,0 goes. Derived from the job
    /// area's position (see `CanvasSceneModel.jobAreaOffset`).
    private var offset: SIMD2<Float> { model.scene.xyOffset }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            readinessStrip
                .padding(.horizontal, 16)
                .padding(.top, 12)

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

            Divider()

            footer
        }
        .frame(width: 640, height: 540)
        .onAppear {
            currentFingerprint = ControllerModel.fingerprint(
                fileName: gCodeModel.document.fileName,
                contents: gCodeModel.document.lines.map { $0.text }.joined(separator: "\n")
            )
        }
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
                model.startSentJob()
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
            infoRow("X Offset", "\(format(offset.x)) mm", emphasized: true)
            infoRow("Y Offset", "\(format(offset.y)) mm", emphasized: true)
            infoRow("Z", model.autoZBeforeRun ? "Set by Auto Z probe" : "Keep current work Z zero",
                    emphasized: true)
            Text("Set on the canvas, not here — change it from the sliders button on the “Job area” row of the objects list. This is the offset sent to the machine; it follows the job area’s position.")
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
            if model.autoZBeforeRun {
                Text("Runs first. Probes the surface and sets work Z zero at the trigger point.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Auto Workpiece Leveling", isOn: $model.levelBeforeRun)
                .help("Probe a height-map grid over the program's cutting area before the job starts")

            if model.levelBeforeRun {
                Text("Then probes a \(model.levelGridPoints)×\(model.levelGridPoints) grid over the cutting area plus a \(Int(model.levelMargin)) mm margin. Does not change work zero.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    // MARK: - Readiness

    private var readinessStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(readinessChecks) { check in
                HStack(spacing: 6) {
                    Image(systemName: icon(for: check.state))
                        .foregroundStyle(color(for: check.state))
                        .frame(width: 14)
                    Text(check.title)
                        .font(.caption)
                        .foregroundStyle(check.state == .ok ? Color.secondary : color(for: check.state))
                    Spacer()
                    if let title = check.actionTitle, let action = check.action {
                        Button(title, action: action)
                            .font(.caption)
                            .buttonStyle(.link)
                            .disabled(check.actionDisabled)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func icon(for state: CheckState) -> String {
        switch state {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .blocked: return "xmark.octagon.fill"
        }
    }

    private func color(for state: CheckState) -> Color {
        switch state {
            case .ok: return .green
            case .warning: return .orange
            case .blocked: return .red
        }
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

    private func infoRow(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasized ? .callout.monospacedDigit().weight(.semibold) : .caption.monospacedDigit())
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
