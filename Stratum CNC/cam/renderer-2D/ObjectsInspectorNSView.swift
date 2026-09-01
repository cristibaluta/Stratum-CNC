//
//  SVGObjectInspectorView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit

final class ObjectsInspectorNSView: NSVisualEffectView {

    // MARK: Property

    enum Property: String {
        case x
        case y
        case width
        case height
        case rotation
    }

    // MARK: Callbacks

    var onSelectionChanged: ((UUID) -> Void)?
    var onValueChanged: ((UUID, Property, CGFloat) -> Void)?
    var onNudge: ((UUID, Property, CGFloat) -> Void)?
    var onScale: ((UUID, Int) -> Void)?
    var onRotate: ((UUID, CGFloat) -> Void)?
    var onAddNew: (() -> Void)?
    var onDelete: ((UUID) -> Void)?

    // MARK: UI

    private let objectsStack = NSStackView()
    private let propertiesStack = NSStackView()
    private let objectsTitle = NSTextField(labelWithString: "Objects")
    private let propertiesTitle = NSTextField(labelWithString: "Properties")

    // MARK: State

    private var elements: [D2_Object] = []
    private var selectedID: UUID?

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: Setup

    private func setup() {
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let addObjectButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Object")!,
            target: self,
            action: #selector(addButtonPressed)
        )

        addObjectButton.bezelStyle = .recessed
        addObjectButton.isBordered = false
        addObjectButton.contentTintColor = .secondaryLabelColor
        addObjectButton.setButtonType(.momentaryPushIn)

        let objectsHeader = NSStackView()
        objectsHeader.orientation = .horizontal
        objectsHeader.alignment = .centerY
        objectsHeader.spacing = 4
        objectsHeader.addArrangedSubview(objectsTitle)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        objectsHeader.addArrangedSubview(spacer)
        objectsHeader.addArrangedSubview(addObjectButton)
        objectsHeader.translatesAutoresizingMaskIntoConstraints = false

        objectsTitle.font = .boldSystemFont(ofSize: 13)
        propertiesTitle.font = .boldSystemFont(ofSize: 13)
        container.addArrangedSubview(objectsHeader)
        objectsStack.orientation = .vertical
        objectsStack.alignment = .leading
        objectsStack.spacing = 2
        container.addArrangedSubview(objectsStack)

        let separator = NSBox()
        separator.boxType = .separator
        container.addArrangedSubview(separator)

        container.addArrangedSubview(propertiesTitle)
        propertiesStack.orientation = .vertical
        propertiesStack.alignment = .leading
        propertiesStack.spacing = 5
        container.addArrangedSubview(propertiesStack)
    }

    // MARK: Update

    func update(elements: [D2_Object], selectedID: UUID?) {
        self.elements = elements
        self.selectedID = selectedID
        rebuildObjectList()
        rebuildProperties()
    }

    // MARK: Object List

    private func rebuildObjectList() {
        clearStack(objectsStack)
        guard !elements.isEmpty else {
            let label = NSTextField(labelWithString: "No SVG objects")
            label.textColor = .secondaryLabelColor
            objectsStack.addArrangedSubview(label)
            return
        }
        for (index, object) in elements.enumerated() {
            let button = NSButton(title: object.name, target: self, action: #selector(objectButtonPressed(_:)))
            button.bezelStyle = .recessed
            button.alignment = .left
            button.tag = index
            button.state = object.id == selectedID ? .on : .off
            button.translatesAutoresizingMaskIntoConstraints = false
            objectsStack.addArrangedSubview(button)
        }
    }

    @objc private func objectButtonPressed(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < elements.count else {
            return
        }
        onSelectionChanged?(elements[sender.tag].id)
    }

    @objc private func addButtonPressed(_ sender: NSButton) {
        onAddNew?()
    }

    // MARK: Properties

    private func rebuildProperties() {
        clearStack(propertiesStack)
        guard let selectedID, let object = elements.first(where: { $0.id == selectedID }) else {
            let label = NSTextField(labelWithString: "Select an object")
            label.textColor = .secondaryLabelColor
            propertiesStack.addArrangedSubview(label)
            return
        }
        addPositionRow(title: "X", value: object.position.x, property: .x, id: object.id)
        addPositionRow(title: "Y", value: object.position.y, property: .y, id: object.id)
        addScaleRow(title: "Width", value: object.width, id: object.id)
        addHeightRow(title: "Height", value: object.height, id: object.id)
        addRotationRow(value: object.rotationDegrees, id: object.id)
    }

    // MARK: Position

    private func addPositionRow(title: String, value: CGFloat, property: Property, id: UUID) {
        let row = makeRow()
        let label = makeLabel(title)
        let field = makeNumberField(value: value, property: property, id: id)
        let minusButton = makeButton(title: "−1", action: #selector(nudgeMinusPressed(_:)))
        minusButton.identifier = makeIdentifier(id: id, property: property)
        let plusButton = makeButton(title: "+1", action: #selector(nudgePlusPressed(_:)))
        plusButton.identifier = makeIdentifier(id: id, property: property)
        let suffix = NSTextField(labelWithString: "mm")
        suffix.textColor = .secondaryLabelColor
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(suffix)
        row.addArrangedSubview(minusButton)
        row.addArrangedSubview(plusButton)
        propertiesStack.addArrangedSubview(row)
    }

    // MARK: Width

    private func addScaleRow(title: String, value: CGFloat, id: UUID) {
        let row = makeRow()
        let label = makeLabel(title)
        let field = makeNumberField(value: value, property: .width, id: id)
        let scaleDownButton = makeButton(title: "÷2", action: #selector(scaleDownPressed(_:)))
        scaleDownButton.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        let scaleUpButton = makeButton(title: "×2", action: #selector(scaleUpPressed(_:)))
        scaleUpButton.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        let suffix = NSTextField(labelWithString: "mm")
        suffix.textColor = .secondaryLabelColor
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(suffix)
        row.addArrangedSubview(scaleDownButton)
        row.addArrangedSubview(scaleUpButton)
        propertiesStack.addArrangedSubview(row)
    }

    // MARK: Height

    private func addHeightRow(title: String, value: CGFloat, id: UUID) {
        let row = makeRow()
        let label = makeLabel(title)
        let field = makeNumberField(value: value, property: .height, id: id)
        let lock = NSTextField(labelWithString: "🔒")
        lock.textColor = .secondaryLabelColor
        let suffix = NSTextField(labelWithString: "mm")
        suffix.textColor = .secondaryLabelColor
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(suffix)
        row.addArrangedSubview(lock)
        propertiesStack.addArrangedSubview(row)
    }

    // MARK: Rotation

    private func addRotationRow(value: CGFloat, id: UUID) {
        let row = makeRow()
        let label = makeLabel("Rotation")
        let field = makeNumberField(value: value, property: .rotation, id: id)
        let minusButton = makeButton(title: "−90°", action: #selector(rotationMinusPressed(_:)))
        minusButton.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        let plusButton = makeButton(title: "+90°", action: #selector(rotationPlusPressed(_:)))
        plusButton.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(minusButton)
        row.addArrangedSubview(plusButton)
        propertiesStack.addArrangedSubview(row)
    }

    // MARK: Controls

    private func makeRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        return row
    }

    private func makeLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 50).isActive = true
        return label
    }

    private func makeNumberField(value: CGFloat, property: Property, id: UUID) -> NumberTextField {
        let field = NumberTextField()
        field.doubleValue = Double(value)
        field.formatter = makeNumberFormatter()
        field.identifier = makeIdentifier(id: id, property: property)
        field.target = self
        field.action = #selector(propertyChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        return field
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    // MARK: Identifiers

    private func makeIdentifier(id: UUID, property: Property) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("\(id.uuidString)|\(property.rawValue)")
    }

    private func decodeIdentifier(_ identifier: NSUserInterfaceItemIdentifier?) -> (UUID, Property)? {
        guard let rawValue = identifier?.rawValue else { return nil }
        let components = rawValue.split(separator: "|")
        guard components.count == 2,
              let id = UUID(uuidString: String(components[0])),
              let property = Property(rawValue: String(components[1])) else { return nil }
        return (id, property)
    }

    private func makeNumberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter
    }

    // MARK: Actions

    @objc private func propertyChanged(_ sender: NSTextField) {
        guard let (id, property) = decodeIdentifier(sender.identifier) else { return }
        onValueChanged?(id, property, CGFloat(sender.doubleValue))
    }

    @objc private func nudgeMinusPressed(_ sender: NSButton) {
        guard let (id, property) = decodeIdentifier(sender.identifier) else { return }
        onNudge?(id, property, -1)
    }

    @objc private func nudgePlusPressed(_ sender: NSButton) {
        guard let (id, property) = decodeIdentifier(sender.identifier) else { return }
        onNudge?(id, property, 1)
    }

    @objc private func scaleDownPressed(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let id = UUID(uuidString: rawValue) else {
            return
        }
        onScale?(id, -2)
    }

    @objc private func scaleUpPressed(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let id = UUID(uuidString: rawValue) else {
            return
        }
        onScale?(id, 2)
    }

    @objc private func rotationMinusPressed(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let id = UUID(uuidString: rawValue) else {
            return
        }
        onRotate?(id, 90)// Not sure why the rotation in canvas is opposite
    }

    @objc private func rotationPlusPressed(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let id = UUID(uuidString: rawValue) else {
            return
        }
        onRotate?(id, -90)
    }

    // MARK: Helpers

    private func clearStack(_ stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}
