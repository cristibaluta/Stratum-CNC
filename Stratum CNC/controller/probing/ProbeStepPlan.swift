//
//  ProbeStepPlan.swift
//  Stratum CNC
//
//  What a probing cycle is made of. A cycle is a list of steps. Each step
//  sends some lines to the machine and may then read where the machine
//  stopped (a "contact"). Later steps can use earlier contacts: the move to
//  the center of a rectangle needs the four sides that were just touched.
//
//  Contacts are positions in MACHINE coordinates (MCS), because the work
//  offset is only written once, at the end.
//

import Foundation

enum ProbeAxis: String, Equatable {
    case x
    case y

    var letter: String { rawValue.uppercased() }
}

/// Names of the positions a cycle reads.
enum ProbeKey {
    /// Where the tip was when the cycle began.
    static let start = "start"
    /// Where the probe touched the top of the stock.
    static let zTop = "zTop"

    /// Where the probe stopped when it touched a side. `direction` is the way
    /// the probe was moving: +1 toward +X or +Y, −1 toward −X or −Y.
    static func side(_ axis: ProbeAxis, _ direction: Int, pass: Int = 0) -> String {
        "side-\(axis.rawValue)\(direction > 0 ? "+" : "-")-\(pass)"
    }

    /// Where the probe stopped after being lowered beside the stock.
    static func lowered(_ axis: ProbeAxis, _ direction: Int, pass: Int = 0) -> String {
        "lowered-\(axis.rawValue)\(direction > 0 ? "+" : "-")-\(pass)"
    }
}

/// The machine positions read so far in a cycle.
struct ProbeContacts: Equatable, Sendable {
    var points: [String: SIMD3<Double>] = [:]

    subscript(key: String) -> SIMD3<Double>? {
        get { points[key] }
        set { points[key] = newValue }
    }

    var isEmpty: Bool { points.isEmpty }
}

struct ProbeStepPlan {

    /// Shown in the progress list.
    let title: String

    /// The lines to send. Built when the step runs, so it can use contacts
    /// from earlier steps. With no contacts yet (a preview) it returns
    /// comment lines in place of anything it can't compute.
    let lines: (ProbeContacts) -> [String]

    /// If set, the machine's position is read after the lines finish and
    /// stored under this key.
    var measure: String?

    /// Looks at the contacts after this step. A returned message stops the
    /// cycle and is shown to the person.
    var check: ((ProbeContacts) -> String?)?

    /// Lines to try if this step fails or its check fails (raise the probe).
    var recovery: [String] = []

    init(_ title: String,
         measure: String? = nil,
         recovery: [String] = [],
         check: ((ProbeContacts) -> String?)? = nil,
         lines: @escaping (ProbeContacts) -> [String]) {
        self.title = title
        self.measure = measure
        self.recovery = recovery
        self.check = check
        self.lines = lines
    }

    /// A step whose lines don't depend on earlier contacts.
    init(_ title: String,
         measure: String? = nil,
         recovery: [String] = [],
         check: ((ProbeContacts) -> String?)? = nil,
         fixed: [String]) {
        self.init(title, measure: measure, recovery: recovery, check: check) { _ in fixed }
    }
}
