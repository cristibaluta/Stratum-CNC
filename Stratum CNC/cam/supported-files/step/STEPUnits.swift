import Foundation

struct STEPUnits {
    let file: STEPFile

    func scaleToMM(contextID: Int) throws -> Double {
        let parameters = try file.parameters(contextID, type: "GLOBAL_UNIT_ASSIGNED_CONTEXT")
        let units = try parameters.references(at: 0)
        let lengths = units.filter { file.hasType($0, "LENGTH_UNIT") }
        guard lengths.count == 1, let unit = lengths.first else {
            throw STEPParseError("Context #\(contextID) must specify exactly one length unit")
        }
        return try scale(unit, visited: [])
    }

    private func scale(_ id: Int, visited: Set<Int>) throws -> Double {
        try Task.checkCancellation()
        guard visited.count < 64, !visited.contains(id) else { throw STEPParseError("Cyclic/deep unit reference #\(id)") }
        var visited = visited
        visited.insert(id)
        guard file.hasType(id, "LENGTH_UNIT") else { throw STEPParseError("Unit #\(id) is not a length unit") }
        let components = try file.components(id)
        let result: Double
        if let si = components.first(where: { $0.type == "SI_UNIT" }) {
            guard si.parameters.count == 2, si.parameters[1].enumeration == "METRE" else {
                throw STEPParseError("Unsupported SI length unit #\(id)")
            }
            if si.parameters[0] == .unset {
                result = 1000
            } else {
                let prefixes: [String: Double] = [
                    "EXA": 1e18, "PETA": 1e15, "TERA": 1e12, "GIGA": 1e9,
                    "MEGA": 1e6, "KILO": 1e3, "HECTO": 1e2, "DECA": 1e1,
                    "DECI": 1e-1, "CENTI": 1e-2, "MILLI": 1e-3, "MICRO": 1e-6,
                    "NANO": 1e-9, "PICO": 1e-12, "FEMTO": 1e-15, "ATTO": 1e-18
                ]
                guard let name = si.parameters[0].enumeration, let prefix = prefixes[name] else {
                    throw STEPParseError("Unsupported SI prefix at #\(id)")
                }
                result = 1000 * prefix
            }
        } else if let converted = components.first(where: { $0.type == "CONVERSION_BASED_UNIT" }) {
            let measureID = try converted.parameters.reference(at: 1)
            let measure = try file.components(measureID)
            guard let values = measure.first(where: { $0.type == "MEASURE_WITH_UNIT" || $0.type == "LENGTH_MEASURE_WITH_UNIT" && $0.parameters.count == 2 })?.parameters,
                  let factor = try values.argument(0).number, factor.isFinite, factor > 0 else {
                throw STEPParseError("Invalid conversion measure #\(measureID)")
            }
            result = try factor * scale(values.reference(at: 1), visited: visited)
        } else {
            throw STEPParseError("Unsupported length unit #\(id)")
        }
        guard result.isFinite, result > 0 else { throw STEPParseError("Invalid length scale #\(id)") }
        return result
    }
}
