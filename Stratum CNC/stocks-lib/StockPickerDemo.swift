//
//  StockPickerDemo.swift
//  Stratum CNC
//
//  Demo of opening the stock library from a button and getting the picked
//  stock back. Picked values are printed to the debugger and used to fill
//  the fields below.
//

import SwiftUI

struct StockPickerDemo: View {

    @StateObject private var store = StocksStore()
    @State private var isPickerPresented = false

    // Fields populated from the picked stock.
    @State private var name = ""
    @State private var material = ""
    @State private var dimensions = ""
    @State private var link = ""

    var body: some View {
        Form {
            Section("Stock") {
                TextField("Name", text: $name)
                TextField("Material", text: $material)
                TextField("Dimensions", text: $dimensions)
                TextField("Link", text: $link)

                Button("Pick Stock…") {
                    isPickerPresented = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isPickerPresented) {
            // Passing `onPick` is what makes the "Pick" button appear.
            StocksLib_Sheet(store: store, onPick: { stock in
                print("Picked stock:")
                print("  id:         \(stock.id)")
                print("  name:       \(stock.name)")
                print("  material:   \(stock.material.displayName)")
                print("  geometry:   \(stock.geometry.displayName) \(stock.geometry.dimensionsDescription)")
                print("  quantity:   \(stock.quantity)")
                print("  link:       \(stock.link ?? "-")")

                name = stock.name
                material = stock.material.displayName
                dimensions = stock.geometry.dimensionsDescription
                link = stock.link ?? ""
            })
        }
    }
}

#Preview {
    StockPickerDemo()
        .frame(width: 500, height: 320)
}
