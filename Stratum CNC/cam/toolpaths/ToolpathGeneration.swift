//
//  ToolpathGeneration.swift
//  Stratum CNC
//

import Foundation
import CoreGraphics
import StratumCAM

/// The outcome of the last "Generate" for one toolpath. Session-only: the
/// engine output isn't persisted, it's rebuilt from the toolpath settings and
/// the canvas objects.
struct ToolpathGeneration {

    /// The settings the result was generated from, to tell when it's outdated.
    let source: ToolpathData
    let outcome: Result<[SC.OutputToolpath], Error>

    /// The canvas overlay for this result, built off the main thread together
    /// with the engine run so showing it is cheap. Nil on failure.
    let previewPath: CGPath?

    var passCount: Int {
        guard case .success(let outputs) = outcome else { return 0 }
        return outputs.reduce(0) { $0 + $1.passes.count }
    }

    var outputCount: Int {
        guard case .success(let outputs) = outcome else { return 0 }
        return outputs.count
    }

    var errorMessage: String? {
        guard case .failure(let error) = outcome else { return nil }
        return ToolpathGenerator.message(for: error, operation: source.operation.kind)
    }

    /// False once the toolpath's settings or shapes were edited after generating.
    func isCurrent(for toolpath: ToolpathData) -> Bool {
        source == toolpath
    }
}
