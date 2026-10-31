//
//  StockMaterialRail.swift
//  Stratum CNC
//
//  Far-left column of the stock library, the counterpart of `ToolTypeRail`. Two sections
//  (All stocks / In stock, Material), each with its own selection: at most one row per
//  section, and the sections combine. Click a selected row again to deselect it.
//  Counts come from `StockFilter.facetCounts(in:)`. The footer holds the Add button.
//

import SwiftUI
import AppKit

extension Color {

    /// One background for the rail and the stock list, so they match the editor column
    /// instead of taking the translucent gray sidebar material.
    static var stockColumnBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

struct StockMaterialRail: View {

    @Binding var filter: StockFilter

    /// Materials that have at least one stock in the library, in the order to show them.
    let materials: [StockMaterialType]

    /// Faceted counts. A missing entry means zero.
    let counts: StockFilter.FacetCounts

    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            footer
        }
        .background(Color.stockColumnBackground)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                row("All stocks", count: counts.all, isSelected: !filter.stockOnly) {
                    filter.stockOnly = false
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
                row("In stock", count: counts.inStock, isSelected: filter.stockOnly) {
                    filter.stockOnly.toggle()
                } icon: {
                    Image(systemName: "shippingbox")
                }

                sectionHeader("Material")
                ForEach(materials, id: \.self) { material in
                    row(
                        material.displayName,
                        count: counts.materials[material, default: 0],
                        isSelected: filter.material == material
                    ) {
                        filter.material = filter.material == material ? nil : material
                    } icon: {
                        MaterialSwatch(material: material)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// Inner left/right padding of a row. The rows themselves run edge to edge.
    private static let rowPadding: CGFloat = 12

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Self.rowPadding)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func row<Icon: View>(
        _ title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                    .frame(width: 18, height: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Self.rowPadding)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A row with nothing under the current filters stays clickable, just quieter.
        .opacity(count == 0 && !isSelected ? 0.5 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Footer

    /// Always visible at the bottom of the rail.
    private var footer: some View {
        Button(action: onAdd) {
            Label("Add", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .help("Add a new stock")
        .padding(10)
    }
}

/// A small rounded chip in the material's own color (the same tone the stock preview uses),
/// so the rail rows can be told apart at a glance.
private struct MaterialSwatch: View {

    let material: StockMaterialType

    var body: some View {
        let palette = material.stockTextureKind.palette
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: Double(palette.mid.x), green: Double(palette.mid.y), blue: Double(palette.mid.z)))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 0.8)
            )
            .padding(2)
            .accessibilityLabel(material.displayName)
    }
}

#Preview {
    StockMaterialRail(
        filter: .constant(StockFilter()),
        materials: [.aluminum, .brass, .copper, .delrin, .epoxy],
        counts: StockFilter.FacetCounts(
            all: 28, inStock: 4,
            materials: [.aluminum: 7, .brass: 3, .copper: 3, .delrin: 6, .epoxy: 2]
        ),
        onAdd: {}
    )
    .frame(width: 170, height: 560)
}
