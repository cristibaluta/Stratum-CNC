//
//  ToolTypeRail.swift
//  Stratum CNC
//
//  Far-left column of the tool library: All tools, In stock, then one row per tool type,
//  each with a count. The counts come from `ToolFilter.counts(in:)`, so they already
//  reflect search, material and source.
//

import SwiftUI
import AppKit

extension Color {

    /// One background for the rail and the tool list, so they match the editor column
    /// instead of taking the translucent gray sidebar material. If the editor's white ever
    /// differs from this, change it here and both columns follow.
    static var toolColumnBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

struct ToolTypeRail: View {

    @Binding var scope: ToolScope

    /// Types that exist in the library, in the order to show them.
    let types: [ToolType]

    /// Faceted counts. A missing entry means zero.
    let counts: [ToolScope: Int]

    var body: some View {
        List(selection: selection) {
            row("All tools", count: counts[.all, default: 0], scope: .all) {
                Image(systemName: "square.grid.2x2")
            }
            row("In stock", count: counts[.inStock, default: 0], scope: .inStock) {
                Image(systemName: "shippingbox")
            }

            Section("Type") {
                ForEach(types, id: \.self) { type in
                    row(type.displayName, count: counts[.type(type), default: 0], scope: .type(type)) {
                        ToolTypeIcon(type: type, size: 18)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.toolColumnBackground)
    }

    /// `List` selection is optional; the rail always has a scope, so a deselect is ignored.
    private var selection: Binding<ToolScope?> {
        Binding(
            get: { scope },
            set: { if let newValue = $0 { scope = newValue } }
        )
    }

    private func row<Icon: View>(
        _ title: String,
        count: Int,
        scope: ToolScope,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
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
        // A type with nothing under the current filters stays selectable, just quieter.
        .opacity(count == 0 ? 0.5 : 1)
        .tag(scope)
    }
}

#Preview {
    ToolTypeRail(
        scope: .constant(.all),
        types: [.endMill, .ballNose, .engraving, .drill, .corn, .chamfer],
        counts: [
            .all: 69, .inStock: 4,
            .type(.endMill): 13, .type(.ballNose): 8, .type(.engraving): 11,
            .type(.drill): 25, .type(.corn): 11
        ]
    )
    .frame(width: 170, height: 400)
}
