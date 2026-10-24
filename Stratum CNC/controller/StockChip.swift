//
//  StockChip.swift
//  Stratum CNC
//
//  The canvas bar's stock summary: icon + "Aluminum · Rectangular · 100 × 60 × 10 mm"
//  on one line. The icon opens the stocks library; the text opens the
//  existing stock editor in a popover. The editor itself is unchanged —
//  `PanelStockMaterial` is reused as-is, it just no longer sits on screen
//  permanently.
//

import SwiftUI

struct StockChip: View {

    @Binding var stock: StockMaterial
    let isStockVisible: Binding<Bool>
    /// Opens the stocks library. When nil (no library available from this
    /// screen) the icon opens the editor popover instead.
    var onOpenLibrary: (() -> Void)?

    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if let onOpenLibrary {
                    onOpenLibrary()
                } else {
                    isEditing = true
                }
            } label: {
                Image(systemName: shapeIcon)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(onOpenLibrary == nil ? "Edit stock" : "Open stocks library")

            Button {
                isEditing.toggle()
            } label: {
                (Text(materialName).fontWeight(.medium)
                 + Text("  ·  \(shapeName)  ·  \(sizeText)").foregroundColor(.secondary))
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Edit stock")
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                PanelStockMaterial(stock: $stock,
                                   isStockVisible: isStockVisible,
                                   isCompact: true,
                                   onOpenStocksLib: nil)
                    .frame(width: 300)
                    .padding(12)
            }
        }
        .fixedSize()
    }

    // MARK: - Summary text

    /// `StockMaterial.material` is rendered the same way `MachiningRunSheet`
    /// does ("\(…)"). If it is an enum whose case names read badly, this is
    /// the one place to map it to a display name.
    private var materialName: String {
        "\(stock.material)".capitalized
    }

    private var shapeName: String {
        switch stock.geometry {
            case .rectangular: return "Rectangular"
            case .cylindrical: return "Cylinder"
            case .disk: return "Disk"
        }
    }

    private var shapeIcon: String {
        switch stock.geometry {
            case .rectangular: return "cube"
            case .cylindrical: return "cylinder"
            case .disk: return "opticaldisc"
        }
    }

    private var sizeText: String {
        switch stock.geometry {
            case let .rectangular(width, height, depth):
                return "\(format(width)) × \(format(height)) × \(format(depth)) mm"
            case let .cylindrical(diameter, length):
                return "Ø\(format(diameter)) × \(format(length)) mm"
            case let .disk(outer, inner, depth):
                return "Ø\(format(outer)) / Ø\(format(inner)) × \(format(depth)) mm"
        }
    }

    private func format<T: BinaryFloatingPoint>(_ value: T) -> String {
        let value = Double(value)
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
