import AppKit
import QuartzCore

final class SVGCanvasRenderer {
    let worldLayer = CALayer()
    let rulerLayer = CAShapeLayer()
    let objectsLayer = CALayer()
    private(set) var nodes: [UUID: SVGObjectNode] = [:]
    private let baseStrokeWidth: CGFloat = 1.0
    private let rulerLength: CGFloat = 200

    init() {
        configureLayers()
        buildRuler()
    }

    // MARK: Objects
    func add(object: SVGObject) {
        let node = SVGObjectNode(object: object, baseStrokeWidth: baseStrokeWidth)
        nodes[object.id] = node
        objectsLayer.addSublayer(node.layer)
    }

    func removeAll() {
        objectsLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        nodes.removeAll()
    }

    // MARK: Rendering
    func render(
        objects: [SVGObject],
        zoomScale: CGFloat,
        selectedObjectIDs: Set<UUID>,
        selectedPath: SVGPathSelection?
    ) {
        for object in objects {
            guard let node = nodes[object.id] else { continue }
            let selected = selectedObjectIDs.contains(object.id)
            let selectedPathIndex: Int? = (selectedPath?.objectID == object.id) ? selectedPath?.pathIndex : nil
            node.update(
                object: object,
                zoomScale: zoomScale,
                objectSelected: selected,
                selectedPathIndex: selectedPathIndex
            )
        }
        updateRulerStrokeWidth(zoomScale: zoomScale)
    }

    // MARK: Setup
    private func configureLayers() {
        worldLayer.anchorPoint = .zero
        worldLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        worldLayer.addSublayer(rulerLayer)
        worldLayer.addSublayer(objectsLayer)
    }

    // MARK: Ruler
    private func buildRuler() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rulerLength, y: 0))
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rulerLength))
        addTicks(to: path, alongX: true)
        addTicks(to: path, alongX: false)
        rulerLayer.path = path
        rulerLayer.strokeColor = NSColor.secondaryLabelColor.cgColor
        rulerLayer.fillColor = nil
        rulerLayer.lineWidth = baseStrokeWidth
        rulerLayer.zPosition = -1
        rulerLayer.actions = ["lineWidth": NSNull()]
    }

    private func addTicks(to path: CGMutablePath, alongX: Bool) {
        let millimeters = Int(rulerLength)
        for value in 0...millimeters {
            let tickLength: CGFloat = value % 10 == 0 ? 4 : value % 5 == 0 ? 2.5 : 1
            if alongX {
                let x = CGFloat(value)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: -tickLength))
            } else {
                let y = CGFloat(value)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: -tickLength, y: y))
            }
        }
    }

    private func updateRulerStrokeWidth(zoomScale: CGFloat) {
        rulerLayer.lineWidth = baseStrokeWidth / max(zoomScale, 0.000001)
    }
}
