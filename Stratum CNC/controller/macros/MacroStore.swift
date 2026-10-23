//
//  MacroStore.swift
//  Stratum CNC
//

import SwiftUI

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

    @Published var selectedMacroID: String? {
        didSet { refreshDocument() }
    }
    @Published private var overrides: [String: [String: Double]] = [:] {
        didSet { refreshDocument() }
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
        Dictionary(uniqueKeysWithValues: macro.parameters.map { ($0.id, value($0, in: macro)) })
    }

    func generate(_ macro: Macro) -> Result<[String], MacroError> {
        macro.generate(values(for: macro))
    }

    func reset(_ macro: Macro) {
        overrides[macro.id] = nil
    }
}
