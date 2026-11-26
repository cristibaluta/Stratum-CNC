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
    /// The objects the setup now includes (at least one).
    var onSetObjects: (([UUID]) -> Void)?
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

    /// Renames the setup.
    var onRename: ((String) -> Void)?

    @State private var nameText = ""
    @FocusState private var isNameFocused: Bool
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
            }
            .padding(.bottom, 2)

            nameRow
            objectRow

            Divider()
                .padding(.vertical, 2)

            stockHeader

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
            stockRow
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
        .onAppear {
            nameText = setup.name
        }
        .onChange(of: setup.id) { _, _ in
            fixtureMessage = nil
            nameText = setup.name
        }
        .onChange(of: setup.name) { _, name in
            if !isNameFocused {
                nameText = name
            }
        }
    }

    // MARK: - Object

    /// The objects the setup includes, in order. A setup without items of its own includes every object.
    private var includedObjects: [PanelSetups.ObjectItem] {
        if setup.items.isEmpty {
            return objects
        }
        return setup.items.compactMap { item in
            objects.first { $0.id == item.objectID }
        }
    }

    private var nameRow: some View {
        InspectorRow(label: "Name") {
            TextField("", text: $nameText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($isNameFocused)
                .onSubmit {
                    commitName()
                }
                .onChange(of: isNameFocused) { _, focused in
                    if !focused {
                        commitName()
                    }
                }
        }
    }

    /// An empty name is not accepted: the field goes back to the setup's name.
    private func commitName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nameText = setup.name
        } else if trimmed != setup.name {
            onRename?(trimmed)
        }
    }

    private var objectRow: some View {
        let included = includedObjects
        let includedIDs = included.map(\.id)
        let available = objects.filter { !includedIDs.contains($0.id) }

        return InspectorRow(label: "Objects", labelVerticalAlignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if included.isEmpty {
                    Text(objects.isEmpty ? "No object imported" : "No objects")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                ForEach(included) { object in
                    HStack(spacing: 6) {
                        Text(object.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        // A setup keeps at least one object (none would mean all of them)
                        if included.count > 1 {
                            Button {
                                onSetObjects?(includedIDs.filter { $0 != object.id })
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(2)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove \(object.name) from this setup")
                        }
                    }
                }
                Menu {
                    ForEach(available) { object in
                        Button(object.name) {
                            onSetObjects?(includedIDs + [object.id])
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(2)
                }
                .stBorderlessMenuStyle()
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .disabled(available.isEmpty)
                .help("Add an object to this setup")
            }
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
        return InspectorRow(label: "Stock") {
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
        }
    }

    /// The title, with the library and the visibility toggle at the right.
    private var stockHeader: some View {
        HStack(spacing: 8) {
            Text("Stock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)
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
            // Only a refused value needs the fields rebuilt (to show what is really applied again).
            // Rebuilding after every edit would also throw away the focus of the field clicked next.
            if fixtureMessage != nil {
                fixtureRefresh += 1
            }
        }
        /// A new diameter moves the offset's limits (it can't be under the pin's radius), so the
        /// offset follows into what fits instead of the whole edit being refused.
        func applyDiameter(_ diameter: Double) {
            let fitted = AlignmentPins.fitted(AlignmentPinsSpec(diameter: diameter, offset: fixture.offset),
                                              on: projectStock.stock)
            apply(diameter: diameter, offset: fitted?.offset ?? fixture.offset)
        }
        return VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            Text(fixture.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            InspectorNumberField(title: "Diameter",
                                 value: Binding(get: { fixture.diameter },
                                                set: { applyDiameter($0) }),
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
