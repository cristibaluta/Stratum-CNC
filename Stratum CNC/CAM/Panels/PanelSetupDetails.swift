//
//  PanelSetupDetails.swift
//  Stratum CNC
//
//  The selected setup, on the right: the object it cuts, picked from the imported ones, and the
//  stock it is cut from. The stock belongs to the setup; the project has none of its own.
//

import SwiftUI

struct PanelSetupDetails: View {

    let setup: Setup
    /// The imported objects a setup can cut (not the alignment pins).
    let objects: [PanelSetups.ObjectItem]
    @Binding var stock: StockMaterial
    @Binding var isStockVisible: Bool
    var stocksStore: StocksStore? = nil
    /// Why the setup can't be cut from its stock (a side face needs a rectangular block).
    var warning: String? = nil
    /// The object the setup now cuts; nil for every object.
    var onSelectObject: ((UUID?) -> Void)?
    /// Deselects the setup, which closes the panel.
    var onDone: (() -> Void)?

    @State private var showingLibrary = false

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
            if let warning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            StockMaterialForm(stock: $stock)

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
                .help("Pick from the material library")
                .popover(isPresented: $showingLibrary, arrowEdge: .leading) {
                    StocksLib_Sheet(store: stocksStore, onPick: { stock = $0 })
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
}
