//
//  GCodeTimeEstimator.swift
//  Stratum CNC
//
//  Rough machining time of a G-code program, from its moves and feed rates.
//
//  Every move takes its length over the feed in effect (G1/G2/G3) or over a
//  fixed rapid rate (G0, or a move before any F is set). Dwells (G4) add their
//  time. Acceleration, tool changes and spindle ramp-up are not modelled, so a
//  real job runs somewhat longer, most of all one made of many short moves.
//
//  Used for the time shown in CAM (a toolpath's preview), in the exported
//  header (`;@MKR|TIME`) and in the Controller (total and time left).
//

import Foundation

enum GCodeTimeEstimator {

    /// Speed assumed for G0 moves, mm/min. The program doesn't say how fast the machine
    /// rapids, so this is the one made-up number in the estimate.
    static let rapidRate = 3000.0

    /// Seconds for the whole program.
    static func estimateSeconds(of gcode: String) -> Double {
        cumulativeSeconds(of: gcode.split(whereSeparator: \.isNewline)).last ?? 0
    }

    /// Running total per line: element `n` is the time to execute the first `n` lines, so the
    /// array has `lines.count + 1` entries, starts at 0 and never decreases. The Controller
    /// uses it to turn the machine's current line into time done and time left.
    static func cumulativeSeconds<Lines: Collection>(of lines: Lines) -> [Double] where Lines.Element: StringProtocol {
        var totals = [0.0]
        totals.reserveCapacity(lines.count + 1)

        var state = State()
        for line in lines {
            state.run(line)
            totals.append(state.minutes * 60)
        }
        return totals
    }

    // MARK: - Interpreter

    private struct State {
        var x = 0.0, y = 0.0, z = 0.0
        /// Feed as programmed, in the program's units per minute.
        var feed = 0.0
        /// 0 rapid, 1 line, 2 clockwise arc, 3 counter-clockwise arc.
        var mode = 0
        var isRelative = false
        var usesInches = false
        /// G17 (XY), G18 (XZ) or G19 (YZ). Arcs are only measured in G17.
        var plane = 17
        var minutes = 0.0

        mutating func run(_ line: some StringProtocol) {
            var target = (x: x, y: y, z: z)
            var i = 0.0, j = 0.0, r: Double?
            var pWord = 0.0, sWord = 0.0
            var moves = false
            var isDwell = false

            for (letter, value) in Self.words(in: line) {
                switch letter {
                case "G":
                    // `Int(exactly:)` leaves out G91.1, G0.1…, which are not the codes they start with.
                    switch Int(exactly: value) ?? -1 {
                    case 0, 1, 2, 3:
                        mode = Int(value)
                        isDwell = false
                    case 4: isDwell = true
                    case 17, 18, 19: plane = Int(value)
                    case 20: usesInches = true
                    case 21: usesInches = false
                    case 90: isRelative = false
                    case 91: isRelative = true
                    default: break
                    }
                case "F": feed = value
                case "P": pWord = value
                case "S": sWord = value
                // In relative mode the words are offsets from where the tool is.
                case "X":
                    target.x = isRelative ? x + value : value
                    moves = true
                case "Y":
                    target.y = isRelative ? y + value : value
                    moves = true
                case "Z":
                    target.z = isRelative ? z + value : value
                    moves = true
                case "I": i = value
                case "J": j = value
                case "R": r = value
                default: break
                }
            }

            // G4 waits for P seconds (the machine's firmware reads P as seconds, not milliseconds).
            if isDwell {
                minutes += max(0, pWord != 0 ? pWord : sWord) / 60
                return
            }
            guard moves else {
                return
            }

            let dx = target.x - x, dy = target.y - y, dz = target.z - z
            var length = (dx * dx + dy * dy + dz * dz).squareRoot()

            if (mode == 2 || mode == 3), plane == 17,
               let arc = Self.arcLength(from: (x, y), to: (target.x, target.y), i: i, j: j, r: r, clockwise: mode == 2) {
                length = (arc * arc + dz * dz).squareRoot()
            }

            // Lengths are in the program's units; the rates have to be too.
            let unit = usesInches ? 25.4 : 1.0
            let rate = (mode == 0 || feed <= 0) ? GCodeTimeEstimator.rapidRate / unit : feed
            minutes += length / rate

            (x, y, z) = target
        }

        /// Length of the XY arc, or nil when the line gives no usable center or radius
        /// (the move is then measured as a straight line).
        private static func arcLength(from start: (x: Double, y: Double),
                                      to end: (x: Double, y: Double),
                                      i: Double,
                                      j: Double,
                                      r: Double?,
                                      clockwise: Bool) -> Double? {
            let dx = end.x - start.x, dy = end.y - start.y

            if i != 0 || j != 0 {
                let radius = (i * i + j * j).squareRoot()
                let centerX = start.x + i, centerY = start.y + j
                let from = atan2(start.y - centerY, start.x - centerX)
                let to = atan2(end.y - centerY, end.x - centerX)
                var sweep = clockwise ? from - to : to - from
                while sweep <= 0 {
                    sweep += 2 * .pi
                }
                // Same start and end point with a center: a full circle.
                if dx == 0 && dy == 0 {
                    sweep = 2 * .pi
                }
                return radius * sweep
            }

            // Radius format: the sign of R picks the short or the long way round.
            if let r, r != 0 {
                let radius = abs(r)
                let chord = (dx * dx + dy * dy).squareRoot()
                guard chord > 0, chord <= 2 * radius else {
                    return nil
                }
                var sweep = 2 * asin(chord / (2 * radius))
                if r < 0 {
                    sweep = 2 * .pi - sweep
                }
                return radius * sweep
            }
            return nil
        }

        /// The letter-and-number words of a line, without `;` and `(…)` comments.
        /// Read by hand: this runs over every line of programs with hundreds of thousands.
        private static func words(in line: some StringProtocol) -> [(Character, Double)] {
            var result: [(Character, Double)] = []
            var chars = line.makeIterator()
            var current = chars.next()
            var depth = 0

            func advance() {
                current = chars.next()
            }

            while let c = current {
                if depth > 0 {
                    if c == "(" {
                        depth += 1
                    } else if c == ")" {
                        depth -= 1
                    }
                    advance()
                    continue
                }
                if c == ";" {
                    break
                }
                if c == "(" {
                    depth = 1
                    advance()
                    continue
                }
                guard c.isASCII, c.isLetter else {
                    advance()
                    continue
                }

                let letter = Character(c.uppercased())
                advance()
                while current == " " || current == "\t" {
                    advance()
                }

                var number = ""
                if current == "-" || current == "+" {
                    number.append(current!)
                    advance()
                }
                while let d = current, d.isASCII, d.isNumber || d == "." {
                    number.append(d)
                    advance()
                }
                if let value = Double(number) {
                    result.append((letter, value))
                }
            }
            return result
        }
    }
}

// MARK: - Display

extension GCodeTimeEstimator {

    /// "45 s", "12 min", "1 h 05 min". Rounded, since the estimate is rough anyway.
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return "\(total) s"
        }
        let minutes = Int((Double(total) / 60).rounded())
        if minutes < 60 {
            return "\(minutes) min"
        }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }
}
