import Foundation

/// Task-confined mutable cache: never share this object between parsing tasks.
final class STEPFile {
    struct ComponentRange {
        let type: String
        let range: Range<Int>
    }
    let data: Data
    private(set) var index: [Int: [ComponentRange]] = [:]
    private var cache: [Int: [STEPComponent]] = [:]

    init(data: Data) throws {
        self.data = data
        var lexer = STEPTokenizer(data: data)
        try lexer.expect(.word("ISO-10303-21"))
        try lexer.expect(.symbol(59))
        try lexer.expect(.word("HEADER"))
        try lexer.expect(.symbol(59))
        while true {
            let token = try lexer.next()
            if token == .word("ENDSEC") { break }
            guard case .word = token else { throw STEPParseError("Invalid HEADER record") }
            _ = try Self.componentRange(in: &lexer)
            try lexer.expect(.symbol(59))
        }
        try lexer.expect(.symbol(59))
        try lexer.expect(.word("DATA"))
        // Parameterized/multiple DATA sections are deliberately not supported yet.
        try lexer.expect(.symbol(59))
        while true {
            let token = try lexer.next()
            if token == .word("ENDSEC") { break }
            guard case .reference(let id) = token else { throw STEPParseError("Expected entity record") }
            guard index[id] == nil else { throw STEPParseError("Duplicate entity #\(id)") }
            guard index.count < 2_000_000 else { throw STEPParseError("Entity count limit exceeded") }
            try lexer.expect(.symbol(61))
            let first = try lexer.next()
            var components: [ComponentRange] = []
            if case .word(let type) = first {
                components.append(ComponentRange(type: type, range: try Self.componentRange(in: &lexer)))
            } else if first == .symbol(40) {
                while true {
                    let part = try lexer.next()
                    if part == .symbol(41) { break }
                    guard case .word(let type) = part, !components.contains(where: { $0.type == type }) else {
                        throw STEPParseError("Invalid complex entity #\(id)")
                    }
                    components.append(ComponentRange(type: type, range: try Self.componentRange(in: &lexer)))
                    guard components.count <= 128 else { throw STEPParseError("Too many complex components") }
                }
                guard !components.isEmpty else { throw STEPParseError("Empty complex entity #\(id)") }
            } else { throw STEPParseError("Missing type for #\(id)") }
            try lexer.expect(.symbol(59))
            index[id] = components
        }
        try lexer.expect(.symbol(59))
        try lexer.expect(.word("END-ISO-10303-21"))
        try lexer.expect(.symbol(59))
        try lexer.expect(.end)
    }

    /// Keep the parentheses in the range so the lazy parser can check list grammar.
    private static func componentRange(in lexer: inout STEPTokenizer) throws -> Range<Int> {
        let start = lexer.position
        try lexer.expect(.symbol(40))
        var depth = 1
        while depth > 0 {
            switch try lexer.next() {
                case .symbol(40): depth += 1
                case .symbol(41): depth -= 1
                case .end, .symbol(59), .symbol(61): throw STEPParseError("Unterminated entity parameters")
                default: break
            }
            guard depth <= STEPTokenizer.maximumNesting else { throw STEPParseError("Parameter nesting limit exceeded") }
        }
        return start..<lexer.position
    }

    func hasType(_ id: Int, _ type: String) -> Bool {
        index[id]?.contains { $0.type == type } ?? false
    }

    func entities(ofTypes types: Set<String>) -> [Int] {
        index.keys.filter { id in index[id]!.contains { types.contains($0.type) } }.sorted()
    }

    func components(_ id: Int) throws -> [STEPComponent] {
        try Task.checkCancellation()
        if let cached = cache[id] { return cached }
        guard let ranges = index[id] else { throw STEPParseError("Missing entity #\(id)") }
        let parsed = try ranges.map { component in
            var parser = STEPParameterParser(lexer: STEPTokenizer(data: data, range: component.range))
            try parser.lexer.expect(.symbol(40))
            let values = try parser.list(depth: 1)
            try parser.lexer.expect(.end)
            return STEPComponent(type: component.type, parameters: values)
        }
        cache[id] = parsed
        return parsed
    }

    func parameters(_ id: Int, type: String) throws -> [STEPValue] {
        guard let component = try components(id).first(where: { $0.type == type }) else {
            throw STEPParseError("Expected \(type) at #\(id)")
        }
        return component.parameters
    }
}

private struct STEPParameterParser {
    var lexer: STEPTokenizer

    mutating func list(depth: Int) throws -> [STEPValue] {
        guard depth <= STEPTokenizer.maximumNesting else { throw STEPParseError("Parameter nesting limit exceeded") }
        var values: [STEPValue] = []
        var token = try lexer.next()
        if token == .symbol(41) { return values }
        while true {
            values.append(try value(token, depth: depth))
            token = try lexer.next()
            if token == .symbol(41) { return values }
            guard token == .symbol(44) else { throw STEPParseError("Expected parameter comma") }
            token = try lexer.next()
        }
    }

    mutating func value(_ token: STEPTokenizer.Token, depth: Int) throws -> STEPValue {
        switch token {
            case .integer(let value): return .integer(value)
            case .real(let value): return .real(value)
            case .reference(let id): return .reference(id)
            case .string(let value): return .string(value)
            case .enumeration(let value): return .enumeration(value)
            case .symbol(36): return .unset
            case .symbol(42): return .derived
            case .symbol(40): return .list(try list(depth: depth + 1))
            case .word(let type):
                try lexer.expect(.symbol(40))
                return .typed(type, try list(depth: depth + 1))
            default: throw STEPParseError("Invalid parameter near byte \(lexer.position)")
        }
    }
}

extension Array where Element == STEPValue {
    func argument(_ index: Int) throws -> STEPValue {
        guard indices.contains(index) else { throw STEPParseError("Missing parameter \(index)") }
        return self[index]
    }
    func reference(at index: Int) throws -> Int {
        guard let id = try argument(index).reference else { throw STEPParseError("Expected reference at parameter \(index)") }
        return id
    }
    func references(at index: Int) throws -> [Int] {
        guard let values = try argument(index).list else { throw STEPParseError("Expected reference list at parameter \(index)") }
        return try values.map {
            guard let id = $0.reference else { throw STEPParseError("Expected reference in list") }
            return id
        }
    }
}
