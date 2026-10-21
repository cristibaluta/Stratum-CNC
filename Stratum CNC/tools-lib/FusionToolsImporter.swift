//
//  FusionToolsImporter.swift
//  Stratum CNC
//
//  Imports Fusion 360 tool libraries (`.tools`) and converts them to `Tool`.
//

import Foundation
import Compression

enum FusionImportError: LocalizedError {
    case notAnArchive
    case toolsJSONMissing
    case unsupportedCompression(UInt16)
    case decompressionFailed
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            "The file is not a valid Fusion .tools archive."
        case .toolsJSONMissing:
            "The archive does not contain a tools.json file."
        case .unsupportedCompression(let method):
            "The archive uses an unsupported compression method (\(method))."
        case .decompressionFailed:
            "The archive could not be decompressed."
        case .invalidJSON(let detail):
            "The tool library could not be parsed: \(detail)"
        }
    }
}

struct FusionImportResult {
    var tools: [Tool]
    /// Fusion entries that have no equivalent in our tool types (holders, probes, taps…).
    var unsupportedCount: Int
}

enum FusionToolsImporter {

    /// Reads a `.tools` file (a zip archive holding `tools.json`) and converts its tools.
    static func importTools(from url: URL) throws -> FusionImportResult {
        let fileData = try Data(contentsOf: url)
        let json: Data
        if fileData.starts(with: [0x50, 0x4B]) {            // "PK" — zip archive
            json = try ZipReader.extract(named: "tools.json", from: fileData)
        } else {                                              // some exports are plain JSON
            json = fileData
        }
        return try convert(json: json)
    }

    static func convert(json: Data) throws -> FusionImportResult {
        let library: FusionLibrary
        do {
            library = try JSONDecoder().decode(FusionLibrary.self, from: json)
        } catch {
            throw FusionImportError.invalidJSON(error.localizedDescription)
        }

        var tools: [Tool] = []
        var unsupported = 0
        for entry in library.data {
            if let tool = convert(entry) {
                tools.append(tool)
            } else {
                unsupported += 1
            }
        }
        return FusionImportResult(tools: tools, unsupportedCount: unsupported)
    }

    // MARK: - Mapping

    private static func convert(_ f: FusionTool) -> Tool? {
        guard let g = f.geometry,
              let diameter = g.DC, diameter > 0,
              let type = mapType(f) else { return nil }

        // Our library is in millimetres; Fusion stores values in the tool's own unit.
        let scale = f.unit?.lowercased().hasPrefix("inch") == true ? 25.4 : 1.0
        func mm(_ value: Double?) -> Double? {
            guard let value, value > 0 else { return nil }
            return (value * scale * 1000).rounded() / 1000
        }

        let shank = mm(g.SFDM) ?? mm(diameter)!
        // `length` in our model is the cutting length (flute length).
        let length = mm(g.LCF) ?? mm(g.shoulderLength) ?? mm(g.OAL)

        let productID = (f.productID ?? "").trimmingCharacters(in: .whitespaces)
        var name = (f.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = productID.isEmpty ? f.type : productID
        } else if !productID.isEmpty && !name.hasPrefix(productID) {
            name = "\(productID) \(name)"
        }

        let vendor = (f.vendor ?? "").trimmingCharacters(in: .whitespaces)
        let typeTitle = f.type.capitalized
        let group = vendor.isEmpty ? typeTitle : "\(vendor) \(typeTitle)"

        var link = f.productLink?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some Fusion entries omit the scheme ("amanatool.com/…"); `Tool.linkURL` needs http(s).
        if let value = link, !value.isEmpty, !value.contains("://") {
            link = "https://" + value
        }

        return Tool(
            id: UUID(uuidString: f.guid) ?? UUID(),
            name: name,
            shankDiameter: shank,
            toolDiameter: mm(diameter)!,
            length: length,
            type: type,
            group: group,
            quantity: 0,
            link: (link?.isEmpty ?? true) ? nil : link,
            tipAngle: tipAngle(for: type, geometry: g),
            presets: presets(from: f, scale: scale)
        )
    }

    /// Converts every Fusion preset of a tool, converting units on the way:
    /// lengths and feeds from inches to mm when needed, and surface speed
    /// from ft/min to m/min.
    private static func presets(from f: FusionTool, scale: Double) -> [ToolPreset] {
        let speedScale = scale == 25.4 ? 0.3048 : 1.0

        func scaled(_ value: Double?, scale: Double = 1, decimals: Double = 1) -> Double? {
            guard let value, value > 0 else { return nil }
            let factor = pow(10, decimals)
            return (value * scale * factor).rounded() / factor
        }
        func rpm(_ value: Double?) -> Int? {
            guard let value, value > 0 else { return nil }
            return Int(exactly: value.rounded())
        }

        return (f.startValues?.presets ?? []).map { p in
            ToolPreset(
                id: UUID(uuidString: p.guid ?? "") ?? UUID(),
                name: p.name?.isEmpty == false ? p.name! : "Default",
                notes: p.description?.isEmpty == false ? p.description : nil,
                spindleRPM: rpm(p.n),
                rampSpindleRPM: rpm(p.nRamp),
                surfaceSpeed: scaled(p.vC, scale: speedScale),
                feedPerTooth: scaled(p.fZ, scale: scale, decimals: 4),
                feedPerRevolution: scaled(p.fN, scale: scale, decimals: 4),
                feedRate: scaled(p.vF, scale: scale),
                plungeFeedRate: scaled(p.vFPlunge, scale: scale),
                rampFeedRate: scaled(p.vFRamp, scale: scale),
                leadInFeedRate: scaled(p.vFLeadIn, scale: scale),
                leadOutFeedRate: scaled(p.vFLeadOut, scale: scale),
                transitionFeedRate: scaled(p.vFTransition, scale: scale),
                retractFeedRate: scaled(p.vFRetract, scale: scale),
                // Fusion's stepdown is our depth of cut.
                depthOfCut: scaled(p.stepdown, scale: scale, decimals: 3),
                useDepthOfCut: p.useStepdown,
                stepOver: scaled(p.stepover, scale: scale, decimals: 3),
                useStepOver: p.useStepover,
                rampAngle: scaled(p.rampAngle, decimals: 2),
                coolant: p.toolCoolant
            )
        }
    }

    private static func mapType(_ f: FusionTool) -> ToolType? {
        switch f.type.lowercased() {
        case "flat end mill", "bull nose end mill", "radius mill", "slot mill", "face mill":
            return .endMill
        case "ball end mill":
            return .ballNose
        case "tapered mill":
            return f.taperedType == "tapered_ball" ? .ballNose : .endMill
        case "chamfer mill":
            let text = (f.description ?? "").lowercased()
            return text.contains("engrav") ? .engraving : .chamfer
        case "counter sink":
            return .vBit
        case "drill", "center drill":
            return .drill
        default:
            return nil          // holder, probe, tap, thread mill, …
        }
    }

    /// Full included angle in degrees, where it applies.
    private static func tipAngle(for type: ToolType, geometry g: FusionGeometry) -> Double? {
        switch type {
        case .chamfer, .engraving:
            guard let ta = g.TA, ta > 0 else { return nil }
            return ta * 2                       // Fusion stores the half angle
        case .vBit, .drill:
            if let sig = g.SIG, sig > 0 { return sig }
            if let ta = g.TA, ta > 0 { return ta * 2 }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Fusion JSON

private struct FusionLibrary: Decodable {
    let data: [FusionTool]
}

private struct FusionTool: Decodable {
    let guid: String
    let description: String?
    let productID: String?
    let productLink: String?
    let type: String
    let unit: String?
    let vendor: String?
    let taperedType: String?
    let geometry: FusionGeometry?
    let startValues: FusionStartValues?

    enum CodingKeys: String, CodingKey {
        case guid, description, type, unit, vendor, geometry
        case startValues = "start-values"
        case productID = "product-id"
        case productLink = "product-link"
        case taperedType = "tapered-type"
    }
}

private struct FusionStartValues: Decodable {
    let presets: [FusionPreset]?
}

/// One entry of `start-values.presets`. Fusion uses short names; what they mean:
///
/// - `guid`            unique id of the preset
/// - `name`            preset label, usually the material ("Aluminum")
/// - `description`     free-text note
/// - `n`               spindle speed, RPM
/// - `n_ramp`          spindle speed while ramping, RPM
/// - `v_c`             cutting (surface) speed at the tool edge, = π·D·n; m/min, or ft/min for inch tools
/// - `f_z`             feed per tooth (chip load), in the tool's length unit
/// - `f_n`             feed per revolution, in the tool's length unit (equals plunge feed ÷ n)
/// - `v_f`             main cutting feed rate per minute (= f_z · flutes · n)
/// - `v_f_plunge`      feed rate when plunging straight down
/// - `v_f_ramp`        feed rate while ramping down at an angle
/// - `v_f_leadIn`      feed on the lead-in arc at the start of a cut
/// - `v_f_leadOut`     feed on the lead-out arc at the end of a cut
/// - `v_f_transition`  feed when moving between cuts at the same depth
/// - `v_f_retract`     feed for retract moves
/// - `ramp-angle`      entry angle when ramping, degrees
/// - `stepdown`        depth per pass, in the tool's length unit (imported as `depthOfCut`)
/// - `use-stepdown`    whether the preset's stepdown is applied (imported as `useDepthOfCut`)
/// - `stepover`        sideways distance between passes, in the tool's length unit
/// - `use-stepover`    whether the preset's stepover is applied
/// - `tool-coolant`    coolant mode: "flood", "mist", "disabled", …
/// - `material`        optional material filter (category/query); not imported
private struct FusionPreset: Decodable {
    let guid: String?
    let name: String?
    let description: String?
    let n: Double?
    let nRamp: Double?
    let vC: Double?
    let fZ: Double?
    let fN: Double?
    let vF: Double?
    let vFPlunge: Double?
    let vFRamp: Double?
    let vFLeadIn: Double?
    let vFLeadOut: Double?
    let vFTransition: Double?
    let vFRetract: Double?
    let rampAngle: Double?
    let stepdown: Double?
    let useStepdown: Bool?
    let stepover: Double?
    let useStepover: Bool?
    let toolCoolant: String?

    enum CodingKeys: String, CodingKey {
        case guid, name, description, n, stepdown, stepover
        case nRamp = "n_ramp"
        case vC = "v_c"
        case fZ = "f_z"
        case fN = "f_n"
        case vF = "v_f"
        case vFPlunge = "v_f_plunge"
        case vFRamp = "v_f_ramp"
        case vFLeadIn = "v_f_leadIn"
        case vFLeadOut = "v_f_leadOut"
        case vFTransition = "v_f_transition"
        case vFRetract = "v_f_retract"
        case rampAngle = "ramp-angle"
        case useStepdown = "use-stepdown"
        case useStepover = "use-stepover"
        case toolCoolant = "tool-coolant"
    }
}

/// The `geometry` block of a Fusion tool. Short names:
///
/// - `DC`               cutting diameter
/// - `SFDM`             shank diameter
/// - `OAL`              overall length
/// - `LCF`              length of cutting flutes
/// - `TA`               taper half angle, degrees
/// - `SIG`              point / tip angle, degrees
/// - `shoulder-length`  length from the tip to the end of the shoulder
private struct FusionGeometry: Decodable {
    let DC: Double?
    let SFDM: Double?
    let OAL: Double?
    let LCF: Double?
    let TA: Double?
    let SIG: Double?
    let shoulderLength: Double?

    enum CodingKeys: String, CodingKey {
        case DC, SFDM, OAL, LCF, TA, SIG
        case shoulderLength = "shoulder-length"
    }
}

// MARK: - Minimal zip reader

/// Just enough of the zip format (stored + deflate) to read a `.tools` archive,
/// so we don't need a third-party dependency or to launch `/usr/bin/unzip`
/// (which the app sandbox would not allow).
private enum ZipReader {

    static func extract(named wanted: String, from data: Data) throws -> Data {
        let b = [UInt8](data)

        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        // End of central directory record, searched from the end of the file.
        guard b.count >= 22 else { throw FusionImportError.notAnArchive }
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 22 - 65_535) {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw FusionImportError.notAnArchive }

        let entryCount = u16(eocd + 10)
        var offset = u32(eocd + 16)

        for _ in 0..<entryCount {
            guard offset + 46 <= b.count, u32(offset) == 0x0201_4B50 else {
                throw FusionImportError.notAnArchive
            }
            let method = UInt16(u16(offset + 10))
            let compressedSize = u32(offset + 20)
            let nameLength = u16(offset + 28)
            let extraLength = u16(offset + 30)
            let commentLength = u16(offset + 32)
            let localOffset = u32(offset + 42)
            let entryEnd = offset + 46 + nameLength + extraLength + commentLength
            guard entryEnd <= b.count else { throw FusionImportError.notAnArchive }
            let nameBytes = b[(offset + 46)..<(offset + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            offset = entryEnd

            guard (name as NSString).lastPathComponent.lowercased() == wanted else { continue }

            guard localOffset + 30 <= b.count, u32(localOffset) == 0x0403_4B50 else {
                throw FusionImportError.notAnArchive
            }
            let start = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard start + compressedSize <= b.count else { throw FusionImportError.notAnArchive }
            let payload = Data(b[start..<(start + compressedSize)])

            switch method {
            case 0:
                return payload
            case 8:
                do {
                    // Apple's .zlib algorithm is raw deflate, which is what zip stores.
                    return try (payload as NSData).decompressed(using: .zlib) as Data
                } catch {
                    throw FusionImportError.decompressionFailed
                }
            default:
                throw FusionImportError.unsupportedCompression(method)
            }
        }
        throw FusionImportError.toolsJSONMissing
    }
}
