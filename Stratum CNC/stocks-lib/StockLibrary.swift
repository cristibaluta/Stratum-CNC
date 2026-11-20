//
//  StockLibrary.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

struct StockLibrary: Codable {
    var stocks: [StockMaterial]
}

struct StockGroup: Identifiable {
    let material: StockMaterialType
    let stocks: [StockMaterial]
    var id: StockMaterialType {
        material
    }
}

extension Array where Element == StockMaterial {

    /// Groups stocks by material, following the order of `StockMaterialType.allCases`.
    /// Materials without stocks are omitted; each group is sorted largest first by width × height, then by depth.
    var groupedByMaterial: [StockGroup] {
        StockMaterialType.allCases.compactMap { material in
            let items = filter { $0.material == material }
                .sorted {
                    if $0.geometry.sortArea != $1.geometry.sortArea {
                        return $0.geometry.sortArea > $1.geometry.sortArea
                    }
                    return $0.geometry.sortDepth > $1.geometry.sortDepth
                }
            return items.isEmpty ? nil : StockGroup(material: material, stocks: items)
        }
    }
}
