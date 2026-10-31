//
//  SourceChip.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//


//
//  SourceChip.swift
//  Stratum CNC
//
//  The pill that says where a tool came from: bundled neutral, imported warm, custom green.
//  It always carries the source name, so colour is never the only signal.
//

import SwiftUI

struct SourceChip: View {

    let source: ToolSourceInfo

    private var color: Color {
        switch source.kind {
            case .bundled: .secondary
            case .imported: .orange
            case .custom: .green
        }
    }

    /// "shop.tools · imported 31 Oct 2026" for an import, just the name otherwise.
    private var help: String {
        guard source.kind == .imported, let date = source.date else { return source.name }
        return "\(source.name) · imported \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        Text(source.name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .help(help)
    }
}

#Preview {
    HStack {
        SourceChip(source: .bundled)
        SourceChip(source: .custom)
        SourceChip(source: ToolSourceInfo(name: "shop.tools", kind: .imported, date: .now))
    }
    .padding()
}