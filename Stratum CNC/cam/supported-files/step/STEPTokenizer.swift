import Foundation

struct STEPTokenizer {
    enum Token: Equatable {
        case word(String), string(String), reference(Int), integer(Int), real(Double), enumeration(String)
        case symbol(UInt8), end
    }

    let data: Data
    private(set) var position: Int
    let end: Int
    static let maximumNesting = 128
    private static let maximumTokenBytes = 1_048_576

    init(data: Data, range: Range<Int>? = nil) {
        self.data = data
        position = range?.lowerBound ?? data.startIndex
        end = range?.upperBound ?? data.endIndex
    }

    private func digit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
    private func letter(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
    }
    private func progress(from start: Int) throws {
        if (position - start) % 4096 == 0 { try Task.checkCancellation() }
        guard position - start <= Self.maximumTokenBytes else {
            throw STEPParseError("Token exceeds size limit at byte \(start)")
        }
    }
    private func text(_ range: Range<Int>) -> String {
        String(decoding: data[range], as: UTF8.self)
    }

    mutating func next() throws -> Token {
        try Task.checkCancellation()
        // Whitespace and comments are recognized only outside strings.
        while position < end {
            let b = data[position]
            if b == 32 || b == 9 || b == 10 || b == 13 {
                position += 1
                if position % 4096 == 0 { try Task.checkCancellation() }
            } else if b == 47 && position + 1 < end && data[position + 1] == 42 {
                position += 2
                var closed = false
                while position + 1 < end {
                    if position % 4096 == 0 { try Task.checkCancellation() }
                    if data[position] == 42 && data[position + 1] == 47 {
                        position += 2
                        closed = true
                        break
                    }
                    position += 1
                }
                guard closed else { throw STEPParseError("Unterminated comment") }
            } else { break }
        }
        guard position < end else { return .end }
        let start = position
        let b = data[position]
        position += 1
        if b == 39 {
            var bytes: [UInt8] = []
            while position < end {
                try progress(from: start)
                let current = data[position]
                position += 1
                if current == 39 {
                    if position < end && data[position] == 39 {
                        bytes.append(39)
                        position += 1
                    } else { return .string(String(decoding: bytes, as: UTF8.self)) }
                } else { bytes.append(current) }
            }
            throw STEPParseError("Unterminated string at byte \(start)")
        }
        if b == 35 {
            let digits = position
            while position < end && digit(data[position]) {
                position += 1
                try progress(from: start)
            }
            guard position > digits, let id = Int(text(digits..<position)), id > 0 else {
                throw STEPParseError("Invalid entity reference at byte \(start)")
            }
            return .reference(id)
        }
        if letter(b) {
            while position < end && (letter(data[position]) || digit(data[position]) || data[position] == 45) {
                position += 1
                try progress(from: start)
            }
            return .word(text(start..<position).uppercased())
        }
        if b == 46 && position < end && letter(data[position]) {
            let nameStart = position
            while position < end && (letter(data[position]) || digit(data[position])) {
                position += 1
                try progress(from: start)
            }
            guard position < end && data[position] == 46 else {
                throw STEPParseError("Unterminated enumeration at byte \(start)")
            }
            let name = text(nameStart..<position).uppercased()
            position += 1
            return .enumeration(name)
        }
        if digit(b) || b == 43 || b == 45 || b == 46 {
            position = start
            if data[position] == 43 || data[position] == 45 { position += 1 }
            var digits = 0
            while position < end && digit(data[position]) {
                digits += 1; position += 1
                try progress(from: start)
            }
            var isReal = false
            if position < end && data[position] == 46 {
                isReal = true; position += 1
                while position < end && digit(data[position]) {
                    digits += 1; position += 1
                    try progress(from: start)
                }
            }
            guard digits > 0 else { throw STEPParseError("Invalid number at byte \(start)") }
            if position < end && (data[position] == 69 || data[position] == 101) {
                isReal = true; position += 1
                if position < end && (data[position] == 43 || data[position] == 45) { position += 1 }
                let exponentStart = position
                while position < end && digit(data[position]) {
                    position += 1
                    try progress(from: start)
                }
                guard position > exponentStart else { throw STEPParseError("Missing exponent digits") }
            }
            let spelling = text(start..<position)
            if !isReal, let value = Int(spelling) { return .integer(value) }
            guard isReal, let value = Double(spelling), value.isFinite else {
                throw STEPParseError("Invalid or overflowing number at byte \(start)")
            }
            return .real(value)
        }
        if [UInt8(40), 41, 44, 59, 61, 36, 42].contains(b) { return .symbol(b) }
        throw STEPParseError("Unexpected byte \(b) at \(start)")
    }

    mutating func expect(_ token: Token) throws {
        guard try next() == token else { throw STEPParseError("Expected \(token) near byte \(position)") }
    }
}
