//
//  GCodeModalState.swift
//  Stratum CNC
//
//  What the machine's modal state would be just before a given line of a
//  G-code program, found by reading the program from the top. Resuming in the
//  middle of a program means replaying this state first (units, plane, work
//  offset, tool, spindle, feed, position); otherwise the machine would run the
//  remaining lines with whatever state it happens to have.
//

import Foundation

struct GCodeModalState: Equatable, Sendable {

    enum Units: Equatable, Sendable {
        case millimeters
        case inches

        var scaleToMillimeters: Double { self == .inches ? 25.4 : 1 }
    }

    enum Spindle: Equatable, Sendable {
        case off
        case clockwise
        case counterClockwise
    }

    var units: Units = .millimeters
    /// G90 (true) / G91 (false).
    var absolute = true
    /// 17 (XY), 18 (XZ) or 19 (YZ).
    var plane = 17
    /// 54...59 once the program has selected a work coordinate system.
    var workspace: Int?
    /// Modal motion: 0, 1, 2 or 3. Nil before the first one, and after a
    /// canned cycle (G81...G89), which this does not replay.
    var motion: Int?
    /// Last F word, in the program's own units per minute.
    var feed: Double?
    var spindle: Spindle = .off
    /// Last S word. Kept while the spindle is off, as the machine does.
    var spindleSpeed: Double?
    /// M7 / M8 airflow or coolant is on.
    var airflow = false
    /// Tool selected by the last `M6`.
    var tool: Int?

    /// Work position in millimeters. Nil on an axis that is not known yet,
    /// e.g. before the first absolute move, or after `G28`.
    var x: Double?
    var y: Double?
    var z: Double?

    /// Things the program does that this scan cannot follow exactly.
    var warnings: [String] = []

    var hasKnownPosition: Bool { x != nil && y != nil && z != nil }
}

/// Reads a program line by line and keeps a `GCodeModalState`.
struct GCodeModalScanner {

    private(set) var state = GCodeModalState()
    /// Highest Z the program ever moves to, in millimeters: its retract /
    /// clearance height.
    private(set) var maxZ: Double?
    private var pendingTool: Int?

    mutating func apply(_ text: String) {
        let words = Self.words(in: text)
        guard !words.isEmpty else { return }

        var axes: [Character: Double] = [:]
        var machineCoordinates = false
        var positionLost = false

        // A tool word counts for an M6 on the same line whichever comes first.
        let lineTool = words.first(where: { $0.letter == "T" }).map { Int($0.value) }
        if let lineTool { pendingTool = lineTool }

        for word in words {
            switch word.letter {
            case "G":
                applyG(word.value, machineCoordinates: &machineCoordinates, positionLost: &positionLost)
            case "M":
                applyM(word.value)
            case "F":
                state.feed = word.value
            case "S":
                state.spindleSpeed = word.value
            case "X", "Y", "Z":
                axes[word.letter] = word.value
            default:
                break
            }
        }

        if positionLost {
            state.x = nil
            state.y = nil
            state.z = nil
            return
        }
        // `G53` moves in machine coordinates and says nothing about work position.
        guard !machineCoordinates else { return }

        let scale = state.units.scaleToMillimeters
        for (axis, value) in axes {
            let scaled = value * scale
            guard scaled.isFinite else { continue }
            switch axis {
            case "X": state.x = Self.moved(state.x, to: scaled, absolute: state.absolute)
            case "Y": state.y = Self.moved(state.y, to: scaled, absolute: state.absolute)
            default:
                state.z = Self.moved(state.z, to: scaled, absolute: state.absolute)
                if let z = state.z { maxZ = max(maxZ ?? z, z) }
            }
        }
    }

    private static func moved(_ current: Double?, to value: Double, absolute: Bool) -> Double? {
        if absolute { return value }
        // A relative move from an unknown position is still unknown.
        return current.map { $0 + value }
    }

    private mutating func applyG(_ value: Double,
                                 machineCoordinates: inout Bool,
                                 positionLost: inout Bool) {
        guard value == value.rounded() else { return }   // G54.1, G92.1, ...
        switch Int(value) {
        case 0, 1, 2, 3: state.motion = Int(value)
        case 17, 18, 19: state.plane = Int(value)
        case 20: state.units = .inches
        case 21: state.units = .millimeters
        case 53: machineCoordinates = true
        case 54...59: state.workspace = Int(value)
        case 80: state.motion = nil
        case 81...89:
            state.motion = nil
            addWarning("The program uses a canned cycle (G\(Int(value))); it is not replayed on resume.")
        case 90: state.absolute = true
        case 91: state.absolute = false
        case 28, 30:
            positionLost = true
        case 92:
            positionLost = true
            addWarning("The program shifts the coordinate system with G92.")
        default: break
        }
    }

    private mutating func applyM(_ value: Double) {
        guard value == value.rounded() else { return }
        switch Int(value) {
        case 3: state.spindle = .clockwise
        case 4: state.spindle = .counterClockwise
        case 5: state.spindle = .off
        case 6: if let pendingTool { state.tool = pendingTool }
        case 7, 8: state.airflow = true
        case 9: state.airflow = false
        default: break
        }
    }

    private mutating func addWarning(_ message: String) {
        if !state.warnings.contains(message) { state.warnings.append(message) }
    }

    // MARK: - Reading words

    struct Word: Equatable {
        let letter: Character
        let value: Double
    }

    /// Letter + number pairs of a line, comments removed. Words need no
    /// separator between them ("T1M6", "G0X10Y5").
    static func words(in text: String) -> [Word] {
        let characters = Array(stripComments(text).uppercased())
        var result: [Word] = []
        var i = 0
        while i < characters.count {
            let letter = characters[i]
            guard letter.isLetter else { i += 1; continue }
            i += 1
            while i < characters.count, characters[i] == " " || characters[i] == "\t" { i += 1 }

            var number = ""
            if i < characters.count, characters[i] == "-" || characters[i] == "+" {
                number.append(characters[i])
                i += 1
            }
            while i < characters.count, characters[i].isNumber || characters[i] == "." {
                number.append(characters[i])
                i += 1
            }
            if let value = Double(number), value.isFinite {
                result.append(Word(letter: letter, value: value))
            }
        }
        return result
    }

    static func stripComments(_ text: String) -> String {
        var output = ""
        var depth = 0
        for character in text {
            if depth == 0, character == ";" { break }
            if character == "(" { depth += 1; continue }
            if character == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { output.append(character) }
        }
        return output
    }
}

extension GCodeModalState {

    /// The modal state just before `line` (1-based) runs: everything the
    /// program did on lines 1..<line. Also returns the program's highest Z.
    static func scan(lines: [String], beforeLine line: Int) -> (state: GCodeModalState, maxZ: Double?) {
        var scanner = GCodeModalScanner()
        var snapshot: GCodeModalState?
        let target = max(1, line)

        for (index, text) in lines.enumerated() {
            if index + 1 == target { snapshot = scanner.state }
            scanner.apply(text)
        }
        return (snapshot ?? scanner.state, scanner.maxZ)
    }
}
