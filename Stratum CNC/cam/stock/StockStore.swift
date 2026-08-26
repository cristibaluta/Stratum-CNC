//
//  StockStore.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import Observation

@MainActor
final class StockStore: ObservableObject {

    private(set) var library: StockLibrary

    var stocks: [StockMaterial] {
        library.stocks
    }

    private let fileManager = FileManager.default

    private var applicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var stocksDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Stocks", isDirectory: true)
    }

    private var stocksFileURL: URL {
        stocksDirectoryURL.appendingPathComponent("stocks.json")
    }

    init() {
        self.library = StockLibrary()

        do {
            try load()
        } catch {
            print("Failed to load stocks: \(error)")
        }
    }

    // MARK: - Loading

    func load() throws {
        try createDirectoryIfNeeded()

        if !fileManager.fileExists(atPath: stocksFileURL.path) {
            try copyDefaultStocks()
        } else {
            try fileManager.removeItem(atPath: stocksFileURL.path)
            try copyDefaultStocks()
        }

        let data = try Data(contentsOf: stocksFileURL)
        let decoder = JSONDecoder()

        library = try decoder.decode(StockLibrary.self, from: data)
    }

    // MARK: - Saving

    func save() throws {
        try createDirectoryIfNeeded()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(library)
        try data.write(to: stocksFileURL, options: .atomic)
    }

    // MARK: - CRUD

    func add(_ stock: StockMaterial) throws {
        library.stocks.append(stock)
        try save()
    }

    func update(_ stock: StockMaterial) throws {
        guard let index = library.stocks.firstIndex(
            where: { $0.id == stock.id }
        ) else {
            return
        }

        library.stocks[index] = stock

        try save()
    }

    func delete(_ stock: StockMaterial) throws {
        library.stocks.removeAll {
            $0.id == stock.id
        }

        try save()
    }

    func duplicate(_ stock: StockMaterial) throws {
        let copy = StockMaterial(name: "\(stock.name) Copy", material: stock.material, geometry: stock.geometry)
        try add(copy)
    }

    // MARK: - Defaults

    func resetToDefaults() throws {
        guard let bundledURL = Bundle.main.url(forResource: "default_stocks", withExtension: "json") else {
            throw StockStoreError.defaultStocksNotFound
        }

        let data = try Data(contentsOf: bundledURL)
        let decoder = JSONDecoder()
        library = try decoder.decode(StockLibrary.self, from: data)

        try save()
    }

    // MARK: - File System

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: stocksDirectoryURL, withIntermediateDirectories: true)
    }

    private func copyDefaultStocks() throws {
        guard let bundledURL = Bundle.main.url(forResource: "default_stocks", withExtension: "json") else {
            throw StockStoreError.defaultStocksNotFound
        }
        
        try fileManager.copyItem(at: bundledURL, to: stocksFileURL)
    }
}

enum StockStoreError: LocalizedError {
    case defaultStocksNotFound

    var errorDescription: String? {
        switch self {
        case .defaultStocksNotFound:
            "The bundled default_stocks.json could not be found."
        }
    }
}
