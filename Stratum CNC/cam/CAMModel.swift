//
//  CAMModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation

@MainActor
class CAMModel: ObservableObject {

    @Published var toolStore = ToolStore()
    @Published var showingToolsSheet: Bool = false

    @Published var stockStore = StockStore()
    @Published var showingStockSheet: Bool = false

    // Insert new files. temporary vars to use
    @Published var showingFilePicker = false
    @Published var svgFile: SVGFile?
}
