//
//  stays.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC {

    /// A single UI-facing field, derived from a `MachiningOperation` and its
    /// nested parameter types (`EntryStrategy`, `ClearingPattern`, `LeadInOut`,
    /// `ChamferParams`, ...).
    ///
    /// This is a *view* over the real model values -- there is no storage here.
    /// Every field's `onChange` / `onSelect` closure reconstructs the owning
    /// value and hands the whole new value back to the caller, so the
    /// `MachiningOperation` enum stays the single source of truth. Nothing here
    /// is `Codable`; it's purely an adapter for building forms.
    public enum ParameterField: Identifiable {
        case double(DoubleField)
        case optionalDouble(OptionalDoubleField)
        case int(IntField)
        case bool(BoolField)
        case choice(ChoiceField)
        case variant(VariantField)
        case group(GroupField)
        case optionalGroup(OptionalGroupField)
        case list(ListField)
        case row(RowField)

        public var id: String {
            switch self {
                case .double(let f): return f.id
                case .optionalDouble(let f): return f.id
                case .int(let f): return f.id
                case .bool(let f): return f.id
                case .choice(let f): return f.id
                case .variant(let f): return f.id
                case .group(let f): return f.id
                case .optionalGroup(let f): return f.id
                case .list(let f): return f.id
                case .row(let f): return f.id
            }
        }
    }
}

extension SC.ParameterField {

    /// A plain numeric value that's always present (e.g. `extensionLength`,
    /// `pitch`, chamfer `width`).
    public struct DoubleField: Identifiable {
        public var id: String
        public var label: String
        public var unit: String?
        public var range: ClosedRange<Double>
        public var value: Double
        public var onChange: (Double) -> Void
    }

    /// A numeric value that can be absent (`nil` == feature disabled), e.g.
    /// `peckDepth`, `dwellTime`, chamfer `depth` override.
    public struct OptionalDoubleField: Identifiable {
        public var id: String
        public var label: String
        public var unit: String?
        public var range: ClosedRange<Double>
        /// Seed value used the moment the field is switched on from `nil`.
        public var defaultValueWhenEnabled: Double
        public var value: Double?
        public var onChange: (Double?) -> Void
    }

    /// A whole-number value, e.g. `radialPasses`.
    public struct IntField: Identifiable {
        public var id: String
        public var label: String
        public var range: ClosedRange<Int>
        public var value: Int
        public var onChange: (Int) -> Void
    }

    /// A plain on/off value, e.g. `isInternal`, `shiftRetract`.
    public struct BoolField: Identifiable {
        public var id: String
        public var label: String
        public var value: Bool
        public var onChange: (Bool) -> Void
    }

    /// A fixed set of mutually exclusive options with no payload of their own
    /// -- `CutDirection`, `CutSide`, `ThreadDirection`, `SpiralDirection`.
    public struct ChoiceField: Identifiable {
        public struct Option: Identifiable, Hashable {
            public var id: String
            public var label: String
        }
        public var id: String
        public var label: String
        public var options: [Option]
        public var selectedId: String
        public var onChange: (String) -> Void
    }

    /// A set of mutually exclusive options that each carry their *own*
    /// fields -- `EntryStrategy`, `PocketClearingPattern`,
    /// `SlotClearingPattern`, `LeadInOut.Style`. The UI shows a picker for
    /// `cases`, then renders the `fields` of whichever `Case` matches
    /// `selectedId`. Picking a different case calls `onSelect`, which swaps
    /// the underlying value to that case with sensible seed defaults.
    public struct VariantField: Identifiable {
        public struct Case: Identifiable {
            public var id: String
            public var label: String
            public var fields: [SC.ParameterField]
        }
        public var id: String
        public var label: String
        public var cases: [Case]
        public var selectedId: String
        public var onSelect: (String) -> Void
    }

    /// A fixed, always-present nested group of fields, e.g. `ChamferParams`.
    public struct GroupField: Identifiable {
        public var id: String
        public var label: String
        public var fields: [SC.ParameterField]
    }

    /// A nested group that can be entirely absent, e.g. `leadIn` / `leadOut`
    /// on `.contour`.
    public struct OptionalGroupField: Identifiable {
        public var id: String
        public var label: String
        public var isPresent: Bool
        public var fields: [SC.ParameterField]
        public var onToggle: (Bool) -> Void
    }

    /// A fixed set of simple fields (`double`/`int`/`bool`/`choice`) that must
    /// always be laid out side by side on one row, unlike the leaf fields
    /// above which are free to wrap onto separate rows when the panel is
    /// narrow -- e.g. thread milling's diameter and pitch.
    public struct RowField: Identifiable {
        public var id: String
        public var fields: [SC.ParameterField]
    }

    /// A homogeneous collection the user can add to / remove from, e.g.
    /// holding `tabs` on `.contour`. Each element renders as its own group
    /// of fields.
    public struct ListField: Identifiable {
        public struct Item: Identifiable {
            public var id: String
            public var fields: [SC.ParameterField]
        }
        public var id: String
        public var label: String
        public var items: [Item]
        public var onAdd: () -> Void
        public var onRemove: (String) -> Void
    }
}
