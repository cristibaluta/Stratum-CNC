//
//  MacroStore.swift
//  Stratum CNC
//

import SwiftUI
import simd

/// Which of the two right-hand lists is showing. Only one at a time.
enum GCodePanelMode: String, CaseIterable {
    case gcode
    case macros
}

/// Selection and parameter values for the macro list. Values the person
/// hasn't touched fall back to each parameter's default.
@MainActor
final class MacroStore: ObservableObject {

    let macros: [Macro] = Macro.builtIn

    /// How far the macro's scrubber is, as a line of its G-code (0 = nothing yet). A freshly
    /// generated macro starts at the end, like a loaded program does.
    @Published var scrubLine = 0

    @Published var selectedMacroID: String? {
        didSet {
            refreshDocument()
        }
    }
    @Published private var overrides: [String: [String: Double]] = [:] {
        didSet {
            refreshDocument()
        }
    }

    // MARK: - Hole position

    /// Where the tool is now, in work X/Y. Fed from the machine status (see `updateCurrentXY`).
    @Published private(set) var currentXY: SIMD2<Double> = .zero

    /// X/Y typed in by the person, shared by all macros (drill a hole, then thread it).
    /// `nil`: the fields follow the tool.
    @Published private var manualXY: SIMD2<Double>? {
        didSet {
            refreshDocument()
        }
    }

    /// Where the macro goes first, with a G0: what's typed in, else where the tool is.
    var targetXY: SIMD2<Double> {
        manualXY ?? currentXY
    }

    var isXYManual: Bool {
        manualXY != nil
    }

    /// The tool moved. The fields (and the G-code) follow it until a value is typed in.
    func updateCurrentXY(_ xy: SIMD2<Double>) {
        guard simd_distance(xy, currentXY) > 1e-4 else {
            return
        }
        currentXY = xy
        if manualXY == nil {
            refreshDocument()
        }
    }

    var xBinding: Binding<Double> {
        Binding(
            get: { self.targetXY.x },
            set: { self.manualXY = SIMD2(Self.rounded($0), self.targetXY.y) }
        )
    }

    var yBinding: Binding<Double> {
        Binding(
            get: { self.targetXY.y },
            set: { self.manualXY = SIMD2(self.targetXY.x, Self.rounded($0)) }
        )
    }

    /// Back to following the tool.
    func useCurrentXY() {
        manualXY = nil
    }

    /// G-code carries 3 decimals; so do the fields.
    private static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    /// The selected macro's generated G-code, in the same document type the
    /// G-code tab uses so `GCodeTableView` can show either one. Kept separate
    /// from the loaded program's document.
    let document = NCFileDocument()

    private func refreshDocument() {
        guard let macro = selectedMacro, case .success(let lines) = generate(macro) else {
            document.clear()
            return
        }
        document.load(from: lines.joined(separator: "\n"))
    }

    var selectedMacro: Macro? {
        macros.first { $0.id == selectedMacroID }
    }

    func value(_ parameter: MacroParameter, in macro: Macro) -> Double {
        overrides[macro.id]?[parameter.id] ?? parameter.defaultValue
    }

    func binding(_ parameter: MacroParameter, in macro: Macro) -> Binding<Double> {
        Binding(
            get: { self.value(parameter, in: macro) },
            set: { self.overrides[macro.id, default: [:]][parameter.id] = $0 }
        )
    }

    func values(for macro: Macro) -> [String: Double] {
        var values = Dictionary(uniqueKeysWithValues: macro.parameters.map { ($0.id, value($0, in: macro)) })
        values[Macro.xKey] = targetXY.x
        values[Macro.yKey] = targetXY.y
        return values
    }

    func generate(_ macro: Macro) -> Result<[String], MacroError> {
        macro.generate(values(for: macro))
    }

    func reset(_ macro: Macro) {
        overrides[macro.id] = nil
    }
}
