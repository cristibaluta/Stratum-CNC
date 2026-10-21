import Foundation

/// Which wire protocol the connected machine actually speaks.
/// Officially detected, not assumed — see Carvera_Controller's
/// carveracontroller/protocols/detector.py for the reference implementation.
enum MakeraWireProtocol: String {
    case smoothie = "Smoothie (plain text)"
    case makera = "Makera (framed binary)"
}
