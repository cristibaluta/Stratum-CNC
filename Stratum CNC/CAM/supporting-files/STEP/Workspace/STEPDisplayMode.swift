//
//  STEPDisplayMode.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation

/// What the part is drawn as. Shaded modes need the body's surface (`STEPViewerContent.surfaces`);
/// a body without one keeps its wireframe in every mode.
enum STEPDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// Edges only; hidden edges follow `STEPHiddenEdgeMode`.
    case wireframe
    /// Lit faces, no edges (and so nothing to pick until face picking exists).
    case shaded
    /// Lit faces with the edges on top; hidden edges follow `STEPHiddenEdgeMode`.
    case shadedEdges

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
            case .wireframe: return "Wireframe"
            case .shaded: return "Shaded"
            case .shadedEdges: return "Shaded + edges"
        }
    }
}
