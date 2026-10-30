//
//  InspectorStyle.swift
//  Stratum CNC
//
//  The building blocks of the toolpath inspector, modelled on Xcode's right sidebar:
//  a section is a muted bold header with a hairline above it, and every setting is a row
//  with a right-aligned label on the left and its control on the right, all controls
//  starting on the same vertical edge.
//

import SwiftUI

enum Inspector {
    /// Width of the right-aligned label column.
    static let labelWidth: CGFloat = 92
    /// Gap between the label column and the control.
    static let columnSpacing: CGFloat = 10
    static let fieldHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 8
}

// MARK: - Section

private struct ExpandInspectorSectionKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Opens the collapsible section this view is the compact form of. Set by `InspectorSection`.
    var expandInspectorSection: () -> Void {
        get { self[ExpandInspectorSectionKey.self] }
        set { self[ExpandInspectorSectionKey.self] = newValue }
    }
}

/// The orange triangle of a compact row. The message is its help; clicking it opens the
/// full section, where the same problem is spelled out next to the setting it is about.
struct InspectorWarningButton: View {
    let message: String

    @Environment(\.expandInspectorSection) private var expand

    var body: some View {
        Button {
            expand()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .frame(width: 20, height: Inspector.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(message)\nClick to see the details.")
    }
}

/// A titled group of rows, separated from the previous one by a hairline.
///
/// With `collapsible` the header is a button with a chevron at its top right that hides
/// the rows. The state is remembered per title, so the sections stay as the user left
/// them when another toolpath is opened. A section without a title has no header to
/// click and is always open.
///
/// While collapsed the section shows its `compact` layout, if it has one: the same
/// settings squeezed into a row or two, without labels or notes (their text goes to help
/// tooltips). Without a compact layout, collapsing hides the section's rows.
struct InspectorSection<Content: View, Compact: View>: View {
    let title: String?
    let showsDivider: Bool
    let collapsible: Bool
    let content: Content
    let compact: Compact?

    @AppStorage private var isCollapsed: Bool

    init(title: String? = nil,
         showsDivider: Bool = true,
         collapsible: Bool = false,
         @ViewBuilder compact: () -> Compact,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsDivider = showsDivider
        self.collapsible = collapsible && title != nil
        self.content = content()
        self.compact = compact()
        _isCollapsed = AppStorage(wrappedValue: false, "inspector.sectionCollapsed.\(title ?? "")")
    }

    private var isOpen: Bool {
        !(collapsible && isCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Divider()
            }
            if let title {
                header(title)
            } else {
                Spacer().frame(height: 10)
            }

            if isOpen {
                VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            } else if let compact {
                compact
                    .environment(\.expandInspectorSection, {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isCollapsed = false
                        }
                    })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 2)
            }
        }
    }

    /// Only the chevron toggles the section; the title is plain text.
    @ViewBuilder
    private func header(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)

            Spacer(minLength: 0)

            if collapsible {
                InspectorDisclosureButton(title: title, isExpanded: isOpen) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCollapsed.toggle()
                    }
                }
            }
        }
    }
}

// MARK: - Disclosure chevron

/// The chevron that shows whether something is open: pointing down while it is collapsed,
/// up while it is open. Every expandable panel (the stock, each toolpath section) uses this
/// one glyph so they all turn the same way.
struct InspectorChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 0 : 180))// Expanded - down; Collapset - up
            .opacity(isExpanded ? 0.65 : 0.25)
    }
}

/// `InspectorChevron` as a button with a target as tall as a section header, for the top
/// right corner of a section.
struct InspectorDisclosureButton: View {
    let title: String
    let isExpanded: Bool
    /// The target's height: as tall as a section header by default.
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            InspectorChevron(isExpanded: isExpanded)
                // A target as tall as the header and wide enough to hit easily
                .frame(width: 28, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The target is wider than the glyph; keep the glyph at the edge
        .padding(.trailing, -9)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")
    }
}

extension InspectorSection where Compact == EmptyView {

    /// A section without a compact layout: collapsing hides its rows.
    init(title: String? = nil,
         showsDivider: Bool = true,
         collapsible: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsDivider = showsDivider
        self.collapsible = collapsible && title != nil
        self.content = content()
        self.compact = nil
        _isCollapsed = AppStorage(wrappedValue: false, "inspector.sectionCollapsed.\(title ?? "")")
    }
}

// MARK: - Row

/// A label on the left, the control on the right.
struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: Inspector.columnSpacing) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: Inspector.labelWidth, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Inspector.fieldHeight)
    }
}

/// A small caption under a control, aligned with the control column.
struct InspectorNote: View {
    let text: String
    /// Orange with a warning icon, for something the user should look at.
    var isWarning: Bool = false
    /// Lined up with the control column (past the label column). Turn off for a note that
    /// belongs to the whole section rather than to one control, so it starts at the left edge.
    var isIndented: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: Inspector.columnSpacing) {
            if isIndented {
                Color.clear
                    .frame(width: Inspector.labelWidth, height: 0)
            }
            Group {
                if isWarning {
                    Label(text, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text(text)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Field chrome

extension View {
    /// The soft gray rounded field every text field and pop-up button sits in.
    func inspectorField() -> some View {
        self
            .padding(.horizontal, 8)
            .frame(height: Inspector.fieldHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The face of a pop-up button: its content, then the up/down arrows.
struct InspectorMenuLabel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .inspectorField()
        .contentShape(Rectangle())
    }
}

// MARK: - Number fields

/// Where a number field remembers whether it takes only the decimals. One setting per field
/// name, so a field's compact form (which has no checkbox) follows what its full form was
/// last set to.
enum InspectorDecimalEntry {
    static func key(for name: String) -> String {
        "inspector.decimalEntry.\(name)"
    }
}

/// The text of a number field. Normally a plain number; with `decimalKey` set and the
/// "decimals only" setting on, a value below 1 shows a fixed "0." and the user types just
/// the digits after it ("3" for 0.3). A value of 1 or more stays a plain number to edit.
struct InspectorValueTextField: View {
    @Binding var value: Double
    @AppStorage private var decimalsOnly: Bool
    private let canUseDecimalsOnly: Bool
    /// What is typed after the "0.", kept as text so "05" and "30" survive being typed.
    @State private var digits: String

    private static let maxDigits = 2

    init(value: Binding<Double>, decimalKey: String?) {
        self._value = value
        self.canUseDecimalsOnly = decimalKey != nil
        _decimalsOnly = AppStorage(wrappedValue: false, InspectorDecimalEntry.key(for: decimalKey ?? ""))
        _digits = State(initialValue: Self.digits(of: value.wrappedValue))
    }

    private var showsDecimalsOnly: Bool {
        canUseDecimalsOnly && decimalsOnly && value >= 0 && value < 1
    }

    var body: some View {
        Group {
            if showsDecimalsOnly {
                HStack(spacing: 1) {
                    Text("0.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("", text: digitsBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
            } else {
                TextField("", value: $value,
                          format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
        }
        .frame(minWidth: 26)
        .onChange(of: value) { _, newValue in
            // The value was changed from outside (a button, another field): follow it.
            if abs(Self.number(from: digits) - newValue) > 1e-9 {
                digits = Self.digits(of: newValue)
            }
        }
    }

    private var digitsBinding: Binding<String> {
        Binding(get: { digits },
                set: { typed in
                    let cleaned = String(typed.filter { $0.isASCII && $0.isNumber }.prefix(Self.maxDigits))
                    digits = cleaned
                    value = Self.number(from: cleaned)
                })
    }

    private static func number(from digits: String) -> Double {
        digits.isEmpty ? 0 : (Double("0." + digits) ?? 0)
    }

    /// The digits after the "0." for a value in 0..<1 ("" for 0, "3" for 0.3, "05" for 0.05).
    private static func digits(of value: Double) -> String {
        guard value > 0, value < 1 else { return "" }
        let hundredths = min(Int((value * 100).rounded()), 99)
        guard hundredths > 0 else { return "" }
        var text = String(format: "%02d", hundredths)
        if text.hasSuffix("0") {
            text.removeLast()
        }
        return text
    }
}

/// The small "0." checkbox at the right end of a number field.
struct InspectorDecimalToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("0.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
        .controlSize(.mini)
        .fixedSize()
        .help("Type only the decimals: the \"0.\" is filled in, so 3 means 0.3. Applies to this field's compact form too.")
    }
}

struct InspectorNumberField<Accessory: View>: View {
    let title: String
    @Binding var value: Double
    let suffix: String
    /// Fixed text before the value, inside the gray field (e.g. a "−" for a depth that is
    /// typed as a positive number). Not editable.
    let prefix: String
    /// Optional control on the right of the field, on the same row (e.g. a helper button).
    let accessory: Accessory
    /// Lengths (mm) can be typed as just their decimals; the checkbox for it sits at the right
    /// end of the field.
    private let offersDecimalsOnly: Bool
    @AppStorage private var decimalsOnly: Bool

    init(title: String, value: Binding<Double>, suffix: String, prefix: String = "",
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self._value = value
        self.suffix = suffix
        self.prefix = prefix
        self.accessory = accessory()
        self.offersDecimalsOnly = suffix == "mm"
        _decimalsOnly = AppStorage(wrappedValue: false, InspectorDecimalEntry.key(for: title))
    }

    var body: some View {
        InspectorRow(label: title) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    if !prefix.isEmpty {
                        Text(prefix)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, -5)
                    }

                    InspectorValueTextField(value: $value, decimalKey: offersDecimalsOnly ? title : nil)

                    if !suffix.isEmpty {
                        Text(suffix)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if offersDecimalsOnly {
                        InspectorDecimalToggle(isOn: $decimalsOnly)
                    }
                }
                .inspectorField()

                accessory
            }
        }
    }
}

extension InspectorNumberField where Accessory == EmptyView {

    init(title: String, value: Binding<Double>, suffix: String, prefix: String = "") {
        self.init(title: title, value: value, suffix: suffix, prefix: prefix) {
            EmptyView()
        }
    }
}

/// A number field for a compact row: no label column, a short tag inside the gray field
/// instead ("Feed", "Start"), and the full name and unit in the help. Shares the row with
/// its siblings, so it takes whatever width is left.
struct InspectorCompactNumberField: View {
    let tag: String
    @Binding var value: Double
    var prefix: String = ""
    var suffix: String = ""
    /// The full form's title, when this field can take just the decimals: it follows that
    /// field's checkbox (the compact form has none of its own).
    var decimalKey: String? = nil
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            if !prefix.isEmpty {
                Text(prefix)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, -3)
            }

            InspectorValueTextField(value: $value, decimalKey: decimalKey)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .inspectorField()
        .help(help)
    }
}

struct InspectorIntField: View {
    let title: String
    @Binding var value: Int
    let suffix: String
    /// Just the field, at a fixed width and without the label column, for a compact row.
    /// The title becomes its help text.
    var isCompact: Bool = false
    /// A short tag inside the field before the value, for a compact one ("Passes").
    var tag: String? = nil

    var body: some View {
        if isCompact {
            field
                .frame(width: tag == nil ? 92 : 104)
                .help(title)
        } else {
            InspectorRow(label: title) {
                field
            }
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            if isCompact, let tag {
                Text(tag)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            TextField("", value: $value, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .inspectorField()
    }
}

// MARK: - Panel header and list rows

/// A panel's title in the same muted bold as a section header, with an optional add button.
struct InspectorHeader: View {
    let title: String
    var addHelp: String = "Add"
    var onAdd: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(addHelp)
            }
        }
    }
}

extension View {
    /// The look of a row in a list: tight padding, accent wash while selected.
    func inspectorListRow(isSelected: Bool) -> some View {
        self
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The eye button at the start of a list row.
struct InspectorVisibilityButton: View {
    let isVisible: Bool
    let showHelp: String
    let hideHelp: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(.system(size: 12))
                .frame(width: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isVisible ? Color.secondary : Color.secondary.opacity(0.5))
        .help(isVisible ? hideHelp : showHelp)
    }
}
