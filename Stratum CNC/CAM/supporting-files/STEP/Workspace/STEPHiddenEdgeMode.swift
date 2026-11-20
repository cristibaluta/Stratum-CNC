//
//  STEPHiddenEdgeMode.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation

/// How edges behind a face are drawn. Needs the body's surface (`STEPViewerContent.surfaces`);
/// without one every edge is drawn solid.
enum STEPHiddenEdgeMode: String, CaseIterable, Identifiable, Sendable {
    case dotted, hidden, solid

    var id: String { rawValue }

    var label: String {
        switch self {
            case .dotted: return "Dotted"
            case .hidden: return "Hidden"
            case .solid: return "Solid"
        }
    }
}
