//
//  ProjectStock.swift
//  Stratum CNC
//
//  The project's stocks: a list at the project level, each one a workpiece definition with the
//  fixtures attached to it. A setup points at one of them by id (`Setup.stockID`), and several
//  setups can use the same one: flipping a part over keeps the same stock, so it keeps the same
//  alignment pins in the same place.
//
//  Fixtures are part of the stock, not of the objects: they are defined here (today only the
//  alignment pins, see `AlignmentPins`), created and edited in the setup's details, and a setup
//  decides whether it uses them (`Setup.usesFixtures`). The canvas objects that draw and cut them
//  are rebuilt from these definitions by `CAMModel.syncFixtureObjects`.
//

import Foundation

struct ProjectStock: Identifiable, Codable, Hashable, @unchecked Sendable {

    var id = UUID()
    var stock: StockMaterial
    /// What is attached to this stock: the alignment pins. One entry per set of pins; the id is the
    /// id of the canvas object built from it, kept across rebuilds so toolpaths that cut the pins
    /// keep pointing at them.
    var fixtures: [AlignmentPinsData] = []

    init(id: UUID = UUID(), stock: StockMaterial, fixtures: [AlignmentPinsData] = []) {
        self.id = id
        self.stock = stock
        self.fixtures = fixtures
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ProjectStocks {

    /// What `migrate` returns: the setups and stocks to run with, and whether anything had to be
    /// converted (so the caller knows the file should be saved in the new shape).
    struct Result {
        var setups: [Setup]
        var stocks: [ProjectStock]
        var didMigrate: Bool
    }

    /// Brings a project saved before stocks were a project-level list up to date:
    /// - a setup that carried its own stock gets a place in the list (setups with an equal stock
    ///   share one entry);
    /// - the alignment pins, which were objects of the project and in every setup, become fixtures
    ///   of the stocks they fit, and the setups on those stocks use them.
    /// Without any stock at all (a new project) the list starts with `legacyStock`, or the default
    /// workpiece. Never returns an empty list.
    static func migrate(setups original: [Setup],
                        stocks saved: [ProjectStock],
                        legacyStock: StockMaterial?,
                        legacyPins: [AlignmentPinsData]) -> Result {

        var setups = original
        var stocks = saved
        var didMigrate = false

        for index in setups.indices {
            guard let legacy = setups[index].legacyStock else {
                continue
            }
            if let existing = stocks.first(where: { $0.stock == legacy }) {
                setups[index].stockID = existing.id
            } else {
                // The setup's id for it, made when it was read, becomes the stock's own
                stocks.append(ProjectStock(id: setups[index].stockID, stock: legacy))
            }
            setups[index].legacyStock = nil
            didMigrate = true
        }
        if stocks.isEmpty {
            stocks = [ProjectStock(stock: legacyStock ?? .defaultWorkpiece)]
            didMigrate = true
        }
        // A setup that points at a stock that is not there falls back on the first one
        for index in setups.indices where !stocks.contains(where: { $0.id == setups[index].stockID }) {
            setups[index].stockID = stocks[0].id
            didMigrate = true
        }

        if !legacyPins.isEmpty {
            for (n, index) in stocks.indices.enumerated() {
                let material = stocks[index].stock
                // The first stock keeps the pins' ids, because toolpaths point at them; the others
                // get their own copies, as every fixture needs an id of its own
                stocks[index].fixtures = legacyPins.compactMap { pins in
                    guard let spec = AlignmentPins.fitted(pins.spec, on: material) else {
                        return nil
                    }
                    return AlignmentPinsData(id: n == 0 ? pins.id : UUID(),
                                             name: pins.name,
                                             diameter: spec.diameter,
                                             offset: spec.offset)
                }
            }
            // The pins used to be in every setup
            for index in setups.indices {
                let hasFixtures = stocks.first { $0.id == setups[index].stockID }?.fixtures.isEmpty == false
                setups[index].usesFixtures = hasFixtures
            }
            didMigrate = true
        }
        return Result(setups: setups, stocks: stocks, didMigrate: didMigrate)
    }

    /// The names the stocks go by in a menu: "Acrylic 3 mm", and "Acrylic 3 mm (2)" for the second
    /// one that reads the same.
    static func labels(for stocks: [ProjectStock]) -> [UUID: String] {
        var seen: [String: Int] = [:]
        var result: [UUID: String] = [:]
        for projectStock in stocks {
            let base = projectStock.stock.setupLabel
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            result[projectStock.id] = n == 1 ? base : "\(base) (\(n))"
        }
        return result
    }
}
