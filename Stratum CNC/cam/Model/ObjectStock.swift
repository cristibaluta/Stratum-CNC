//
//  ObjectStock.swift
//  Stratum CNC
//
//  A stock for each object. It is kept where the project already saves stocks: on the object's own
//  setups (the ones that include it alone). So an object with its own stock has it on all of them,
//  a new setup for it starts with the same one, and nothing new has to be saved.
//

import Foundation

extension CAMModel {

    /// The setups that include this object alone.
    private func ownSetups(ofObject id: UUID) -> [Setup] {
        setups.filter { $0.items.count == 1 && $0.items[0].objectID == id }
    }

    /// The object's own stock; nil when it is cut from the project's.
    func ownStock(forObject id: UUID) -> StockMaterial? {
        ownSetups(ofObject: id).compactMap(\.stock).first
    }

    /// What the object is cut from: its own stock, or the project's.
    func stock(forObject id: UUID) -> StockMaterial {
        ownStock(forObject: id) ?? selectedStockMaterial
    }

    /// Edits the object's stock. With several objects the edit gives it a stock of its own (the
    /// project's would change every other object); with one object there is nothing to tell apart,
    /// so it stays the project's.
    func setStock(_ stock: StockMaterial, forObject id: UUID) {
        if ownStock(forObject: id) == nil, regularObjectIDs.count <= 1 {
            selectedStockMaterial = stock
            return
        }
        for setup in ownSetups(ofObject: id) {
            setSetupStock(setup.id, to: stock)
        }
    }

    /// The object follows the project's stock again.
    func useProjectStock(forObject id: UUID) {
        for setup in ownSetups(ofObject: id) {
            setSetupStock(setup.id, to: nil)
        }
    }
}
