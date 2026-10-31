//
//  Tool.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct Tool: Identifiable, Codable, Hashable {
    let id: UUID

    var name: String

    // Geometry
    var shankDiameter: Double
    var toolDiameter: Double
    /// Length of the cutting part
    var length: Double?

    var type: ToolType
    var group: String? = nil

    /// Number of this tool currently in stock.
    var quantity: Int

    /// Where to buy this tool.
    var link: String? = nil

    // Optional geometry specific to certain tools
    var tipAngle: Double? = nil

    /// Which `ToolSourceInfo` this tool came from: bundled, an import batch, or custom.
    var sourceID: UUID

    /// Cutting presets (speeds and feeds). Usually one per material, named after it.
    /// Shown alphabetically by name in the UI.
    var presets: [ToolPreset]

    init(
        id: UUID = UUID(),
        name: String,
        shankDiameter: Double,
        toolDiameter: Double,
        length: Double?,
        type: ToolType,
        group: String? = nil,
        quantity: Int = 0,
        link: String? = nil,
        tipAngle: Double? = nil,
        presets: [ToolPreset] = [],
        sourceID: UUID = ToolSourceInfo.customID
    ) {
        self.id = id
        self.name = name
        self.shankDiameter = shankDiameter
        self.toolDiameter = toolDiameter
        self.length = length
        self.type = type
        self.group = group
        self.quantity = quantity
        self.link = link
        self.tipAngle = tipAngle
        self.presets = presets
        self.sourceID = sourceID
    }

    enum CodingKeys: String, CodingKey {
        case id, name, shankDiameter, toolDiameter, length, type, group
        case quantity, link, tipAngle, presets, sourceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shankDiameter = try c.decode(Double.self, forKey: .shankDiameter)
        toolDiameter = try c.decode(Double.self, forKey: .toolDiameter)
        length = try c.decodeIfPresent(Double.self, forKey: .length)
        type = try c.decode(ToolType.self, forKey: .type)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 0
        link = try c.decodeIfPresent(String.self, forKey: .link)
        tipAngle = try c.decodeIfPresent(Double.self, forKey: .tipAngle)
        presets = try c.decodeIfPresent([ToolPreset].self, forKey: .presets) ?? []
        sourceID = try c.decode(UUID.self, forKey: .sourceID)
    }

    /// The link as a URL, if it is a valid http(s) address.
    var linkURL: URL? {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty,
              let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// How the tool is named in the app's pickers: what it is rather than what it was called
    /// in a library. Diameter, the tip angle for the tools that have one, the length when
    /// known, then the type: "Ø6 · 38 mm · End Mill", "Ø3.175 · 60° · 38 mm · V Bit".
    var displayName: String {
        var parts = ["Ø\(Self.format(toolDiameter))"]
        if let tipAngle, tipAngle > 0 {
            parts.append("\(Self.format(tipAngle))°")
        }
        if let length, length > 0 {
            parts.append("\(Self.format(length)) mm")
        }
        parts.append(type.displayName)
        return parts.joined(separator: " · ")
    }

    /// "Shank Ø6", for the second line of a tool in a list; nil when the shank isn't known.
    var shankDescription: String? {
        shankDiameter > 0 ? "Shank Ø\(Self.format(shankDiameter))" : nil
    }

    /// Up to 3 decimals, without trailing zeros: 6, 3.175, 0.1.
    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US")))
    }

    /// Best-effort guess whether the tool is meant for cutting metal.
    ///
    /// There is no "workpiece material" field on a tool (Fusion's `BMC` is the tool's own
    /// material, e.g. carbide), so this looks for hints in what the tool says about itself:
    /// - a preset named after a metal (aluminum, brass, steel). Copper is left out on purpose:
    ///   it is also the PCB board material, so a copper preset doesn't imply a metal tool;
    /// - the name or group mentioning metal, but not "non metal" / "non-metal";
    /// - the name mentioning aluminum, brass or non-ferrous, as in "Aluminum Cutting".
    var isForMetal: Bool {
        let metalPresets: Set<String> = ["aluminum", "aluminium", "brass", "steel"]
        if presets.contains(where: { metalPresets.contains($0.name.lowercased()) }) {
            return true
        }

        func mentionsMetal(_ text: String) -> Bool {
            var text = text.lowercased()
            for negated in ["non metal", "non-metal", "nonmetal"] {
                text = text.replacingOccurrences(of: negated, with: "")
            }
            return text.contains("metal")
        }
        if mentionsMetal(name) || mentionsMetal(group ?? "") {
            return true
        }

        let lowerName = name.lowercased()
        return ["aluminum", "aluminium", "brass", "non-ferrous", "nonferrous"]
            .contains { lowerName.contains($0) }
    }

    /// The preset to use for this stock: the one named after the material (or the closest
    /// family, e.g. "Plastic" for acrylic). A tool with a single preset, such as Fusion's
    /// "Default Preset", uses it whatever it is called. Otherwise `nil`, rather than a guess.
    func preset(for stock: StockMaterialType) -> ToolPreset? {
        func key(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        for candidate in stock.presetNameCandidates {
            if let match = presets.first(where: { key($0.name) == candidate }) {
                return match
            }
        }
        return presets.count == 1 ? presets.first : nil
    }
}

enum ToolType: String, Codable, CaseIterable, Hashable {
    case endMill
    case ballNose
    case engraving
    case drill
    case vBit
    case corn
    case chamfer
    case solderMaskRemover
    case threadMill

    var displayName: String {
        switch self {
            case .endMill: "End Mill"
            case .ballNose: "Ball Nose"
            case .engraving: "Engraving"
            case .drill: "Drill"
            case .vBit: "V Bit"
            case .corn: "Corn"
            case .chamfer: "Chamfer"
            case .solderMaskRemover: "Solder Mask Remover"
            case .threadMill: "Thread Mill"
        }
    }
}
