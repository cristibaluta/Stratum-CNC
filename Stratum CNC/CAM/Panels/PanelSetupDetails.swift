//
//  PanelSetupDetails.swift
//  Stratum CNC
//
//  The selected setup, on the right: the object it cuts, picked from the imported ones, the stock
//  it is cut from and its fixtures. The stock is one of the project's stocks, which several setups
//  can share; editing it edits it for all of them. The fixtures (the alignment pins) are defined on
//  the stock, so they are created and edited here, and the Fixtures checkbox says whether this
//  setup uses them.
//

import SwiftUI

struct PanelSetupDetails: View {

    let setup: Setup
    /// The imported objects a setup can cut (not the fixtures).
    let objects: [PanelSetups.ObjectItem]
    /// The project's stocks, and how many setups are cut from each, by stock id.
    let stocks: [ProjectStock]
    var setupCounts: [UUID: Int] = [:]
    /// The stock this setup is cut from: one of `stocks`.
    let projectStock: ProjectStock
    /// The definition of that stock. Writing it changes the stock for every setup that is on it.
    @Binding var stock: StockMaterial
    @Binding var isStockVisible: Bool
    var stocksStore: StocksStore? = nil
    /// Why the setup can't be cut from its stock (a side face needs a rectangular block).
    var warning: String? = nil
    /// The object the setup now cuts; nil for every object.
    var onSelectObject: ((UUID?) -> Void)?
    /// Cuts the setup from another of the project's stocks.
    var onSelectStock: ((UUID) -> Void)?
    /// "New stock": a copy of this one (fixtures included), which the setup is then cut from.
    var onNewStock: (() -> Void)?
    /// A stock picked from the material library.
    var onPickLibraryStock: ((StockMaterial) -> Void)?
    var onRemoveUnusedStocks: (() -> Void)?
    /// The Fixtures checkbox. Returns a message when the fixtures can't be made for this stock.
    var onSetUsesFixtures: ((Bool) -> String?)?
    /// A fixture's Diameter and Offset: (fixture, diameter, offset). Returns a message when they
    /// would not fit the stock; nothing changes then.
    var onFixtureChanged: ((UUID, Double, Double) -> String?)?
    /// Takes the fixtures off the stock (for every setup on it).
    var onRemoveFixtures: (() -> Void)?
    /// Deselects the setup, which closes the panel.
    var onDone: (() -> Void)?

    @State private var showingLibrary = false
    @State private var fixtureMessage: String?
    /// Bumped after each edit of the fixture fields, so a field shows what was really applied.
    @State private var fixtureRefresh = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            HStack(spacing: 6) {
                Text("Setup details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(setup.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.bottom, 2)

            objectRow

            Divider()
                .padding(.vertical, 2)

            stockHeader
            stockRow
            if let sharedNote {
                Text(sharedNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            StockMaterialForm(stock: $stock)

            Divider()
                .padding(.vertical, 2)

            fixturesSection

            Divider()
                .padding(.vertical, 2)

            HStack {
                Spacer()
                Button("Done") {
                    onDone?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .help("Close the setup's details")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .canvasChrome()
        .onChange(of: setup.id) { _, _ in
            fixtureMessage = nil
        }
    }

    // MARK: - Object

    /// The object the setup cuts: the only one it includes, or every object when it has no items of
    /// its own (which is the one object of a single-object project).
    private var selectedObjectID: UUID? {
        if setup.items.isEmpty {
            return objects.count == 1 ? objects[0].id : nil
        }
        if setup.items.count == 1, objects.contains(where: { $0.id == setup.items[0].objectID }) {
            return setup.items[0].objectID
        }
        return nil
    }

    private var objectTitle: String {
        if objects.isEmpty {
            return "No object imported"
        }
        if let id = selectedObjectID, let object = objects.first(where: { $0.id == id }) {
            return object.name
        }
        return setup.items.count > 1 ? "\(setup.items.count) objects" : "All objects"
    }

    private var objectRow: some View {
        InspectorRow(label: "Object") {
            Menu {
                ForEach(objects) { object in
                    Button {
                        onSelectObject?(object.id)
                    } label: {
                        if object.id == selectedObjectID {
                            Label(object.name, systemImage: "checkmark")
                        } else {
                            Text(object.name)
                        }
                    }
                }
                if objects.count > 1 {
                    Divider()
                    Button {
                        onSelectObject?(nil)
                    } label: {
                        if setup.items.isEmpty {
                            Label("All objects", systemImage: "checkmark")
                        } else {
                            Text("All objects")
                        }
                    }
                }
            } label: {
                InspectorMenuLabel {
                    Text(objectTitle)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .disabled(objects.isEmpty)
            .help("The imported object this setup cuts")
        }
    }

    // MARK: - Stock

    private var stockLabels: [UUID: String] {
        ProjectStocks.labels(for: stocks)
    }

    /// Other setups are cut from this stock too.
    private var sharedNote: String? {
        let others = setupCounts[projectStock.id, default: 0] - 1
        guard others > 0 else {
            return nil
        }
        return others == 1
            ? "Another setup is cut from this stock: changing it changes both."
            : "\(others) other setups are cut from this stock: changing it changes all of them."
    }

    /// Which of the project's stocks the setup is cut from.
    private var stockRow: some View {
        let labels = stockLabels
        return InspectorRow(label: "Stock") {
            Menu {
                ForEach(stocks) { entry in
                    Button {
                        onSelectStock?(entry.id)
                    } label: {
                        let title = labels[entry.id] ?? entry.stock.setupLabel
                        if entry.id == projectStock.id {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
                Divider()
                Button {
                    onNewStock?()
                } label: {
                    Label("New Stock from This One", systemImage: "plus")
                }
                if stocks.contains(where: { setupCounts[$0.id] == nil }) {
                    Button {
                        onRemoveUnusedStocks?()
                    } label: {
                        Label("Remove Unused Stocks", systemImage: "trash")
                    }
                }
            } label: {
                InspectorMenuLabel {
                    Text(labels[projectStock.id] ?? projectStock.stock.setupLabel)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("The project's stocks: pick the one this setup is cut from")
        }
    }

    /// The title, with the library and the visibility toggle at the right.
    private var stockHeader: some View {
        HStack(spacing: 8) {
            Text("Stock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            if let stocksStore {
                Button {
                    showingLibrary = true
                } label: {
                    Image(systemName: "cube")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Pick from the material library: it replaces this stock, or becomes a new one when other setups use it")
                .popover(isPresented: $showingLibrary, arrowEdge: .leading) {
                    StocksLib_Sheet(store: stocksStore, onPick: { onPickLibraryStock?($0) })
                }
            }

            Button {
                isStockVisible.toggle()
            } label: {
                Image(systemName: isStockVisible ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(isStockVisible ? .primary : .secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(isStockVisible ? "Hide material in 2D" : "Show material in 2D")
        }
    }

    // MARK: - Fixtures

    private var usesFixturesBinding: Binding<Bool> {
        Binding(
            get: {
                setup.usesFixtures
            },
            set: { uses in
                fixtureMessage = onSetUsesFixtures?(uses)
                fixtureRefresh += 1
            }
        )
    }

    /// The Fixtures checkbox (does this setup use the stock's fixtures) and, while it is on, the
    /// definition of the stock's alignment pins.
    private var fixturesSection: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            Toggle(isOn: usesFixturesBinding) {
                Text("Fixtures")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .help("Use the fixtures of this stock in this setup: they are drawn on the canvas and can be cut")

            if let fixtureMessage {
                Text(fixtureMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if setup.usesFixtures {
                ForEach(projectStock.fixtures) { fixture in
                    fixtureFields(fixture)
                }
                Text("The fixtures belong to the stock: every setup cut from it that has Fixtures ticked uses them, and they follow the stock when its size changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !projectStock.fixtures.isEmpty {
                    Button("Remove from Stock") {
                        onRemoveFixtures?()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .help("Takes the fixtures off the stock, for every setup cut from it")
                }
            }
        }
    }

    /// An alignment pins fixture: the two numbers it is built from.
    private func fixtureFields(_ fixture: AlignmentPinsData) -> some View {
        func apply(diameter: Double, offset: Double) {
            fixtureMessage = onFixtureChanged?(fixture.id, diameter, offset)
            fixtureRefresh += 1
        }
        return VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            Text(fixture.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            InspectorNumberField(title: "Diameter",
                                 value: Binding(get: { fixture.diameter },
                                                set: { apply(diameter: $0, offset: fixture.offset) }),
                                 suffix: "mm")
            InspectorNumberField(title: "Offset",
                                 value: Binding(get: { fixture.offset },
                                                set: { apply(diameter: fixture.diameter, offset: $0) }),
                                 suffix: "mm")
            Text("Offset is the distance from the stock's edges to the centre of each pin.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(fixtureRefresh)
    }
}
