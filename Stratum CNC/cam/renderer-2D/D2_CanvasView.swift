import AppKit

final class D2_CanvasView: NSView {

    var files: [CAM_File] = []

    private let state = SVGCanvasState()
    private let factory = CAM_ObjectFactory()
    private let renderer = D2_CanvasRenderer()
    private let hitTester = PathHitTester(tolerance: 6)
    private let inspectorView = CAM_ObjectsInspectorView()

    private var lastDragLocation: CGPoint?
    private var panOffset = CGPoint.zero
    private var zoomScale: CGFloat = 3.0
    /// Currently unused intentionally. This is rotating the whole world, not sure it's useful
    private var rotationAngle: CGFloat = 0

    var currentPathCount: Int {
        state.objects.reduce(0) { $0 + $1.paths.count }
    }

    var onAddNew: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool {
        false
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = STColor.textBackgroundColor.cgColor
        layer?.addSublayer(renderer.worldLayer)
        setupInspector()
    }

    private func setupInspector() {
        inspectorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inspectorView)
        NSLayoutConstraint.activate([
            inspectorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            inspectorView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            inspectorView.widthAnchor.constraint(equalToConstant: 270)
        ])
        inspectorView.onSelectionChanged = { [weak self] id in
            self?.selectObject(id)
        }
        inspectorView.onValueChanged = { [weak self] id, property, value in
            self?.updateObject(id: id, property: property, value: value)
        }
        inspectorView.onNudge = { [weak self] id, property, amount in
            self?.nudgeObject(id: id, property: property, amount: amount)
        }
        inspectorView.onScale = { [weak self] id, scaleFactor in
            self?.scaleObject(id: id, scaleFactor: scaleFactor)
        }
        inspectorView.onRotate = { [weak self] id, amount in
            self?.rotateObject(id: id, degrees: amount)
        }
        inspectorView.onAddNew = { [weak self] in
            self?.onAddNew?()
        }
    }
    override func layout() {
        super.layout()
        renderer.worldLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateWorldTransform()
    }

    func insertSvgFile(_ svgFile: CAM_File) {
        guard !svgFile.paths.isEmpty else {
            updateInspector()
            return
        }
        addSVG(name: svgFile.url.lastPathComponent, paths: svgFile.paths, selectAfterAdding: false)
        centerOnContent()
    }

    func addSVG(name: String, paths: [NSBezierPath]) {
        addSVG(name: name, paths: paths, selectAfterAdding: true)
    }

    private func addSVG(name: String, paths: [STBezierPath], selectAfterAdding: Bool) {
        guard let object = factory.makeObject(name: name, paths: paths) else {
            return
        }
        state.add(object, select: selectAfterAdding)
        renderer.add(object: object)
        render()
        updateInspector()
    }

    private func render() {
        renderer.render(objects: state.objects,
                        zoomScale: zoomScale,
                        selectedObjectIDs: state.selectedObjectIDs,
                        selectedPath: state.selectedPath)
    }

    private func updateWorldTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: panOffset.x, y: panOffset.y)
        transform = transform.rotated(by: rotationAngle)
        transform = transform.scaledBy(x: zoomScale, y: zoomScale)
        renderer.worldLayer.setAffineTransform(transform)

        CATransaction.commit()
    }

    private func centerOnContent() {
        guard !state.objects.isEmpty else {
            return
        }
        var unionRect: CGRect?
        for object in state.objects {
            unionRect = unionRect?.union(object.rotatedBounds) ?? object.rotatedBounds
        }
        guard let contentBounds = unionRect else {
            return
        }
        let center = CGPoint(x: contentBounds.midX, y: contentBounds.midY)
        panOffset = CGPoint(x: -center.x * zoomScale, y: -center.y * zoomScale)
        updateWorldTransform()
    }

    override func scrollWheel(with event: NSEvent) {
        panOffset.x += event.scrollingDeltaX// Scrolling right should move the canvas left
        panOffset.y -= event.scrollingDeltaY// Scrolling up should move the canvas down
        updateWorldTransform()
    }

    override func magnify(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        let oldScale = zoomScale
        let newScale = min(max(oldScale * (1 + event.magnification), 0.1), 200)
        guard newScale != oldScale else {
            return
        }
        let mouseFromCenter = CGPoint(x: mouse.x - bounds.midX, y: mouse.y - bounds.midY)
        let ratio = newScale / oldScale
        panOffset.x = mouseFromCenter.x - (mouseFromCenter.x - panOffset.x) * ratio
        panOffset.y = mouseFromCenter.y - (mouseFromCenter.y - panOffset.y) * ratio
        zoomScale = newScale
        updateWorldTransform()
        render()
    }

    override func rotate(with event: NSEvent) {
        /* Intentionally disabled. */
    }

    override func mouseDown(with event: NSEvent) {

        let viewPoint = convert(event.locationInWindow, from: nil)
        lastDragLocation = viewPoint

        guard let worldPoint = layer?.convert(viewPoint, to: renderer.worldLayer) else {
            return
        }
        if let hit = hitTester.hitTest(worldPoint: worldPoint,
                                       objects: state.objects,
                                       nodes: renderer.nodes,
                                       worldLayer: renderer.worldLayer,
                                       zoomScale: zoomScale) {
            state.selectPath(objectID: hit.objectID, pathIndex: hit.pathIndex)
        } else {
            state.clearSelection()
        }
        render()
        updateInspector()
    }

    override func mouseDragged(with event: NSEvent) {

        let location = convert(event.locationInWindow, from: nil)

        guard let last = lastDragLocation else {
            lastDragLocation = location
            return
        }
        panOffset.x += location.x - last.x
        panOffset.y += location.y - last.y
        lastDragLocation = location
        updateWorldTransform()
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    private func selectObject(_ id: UUID) {
        state.selectObject(id)
        render()
        updateInspector()
    }

    private func updateObject(id: UUID, property: CAM_ObjectsInspectorView.Property, value: CGFloat) {
        guard state.selectedObjectIDs.contains(id), let object = object(withID: id) else {
            return
        }
        switch property {
            case .x: object.position.x = value
            case .y: object.position.y = value
            case .width: object.width = max(value, 0.001)
            case .height: object.setHeight(value)
            case .rotation: object.setRotation(value)
        }
        render()
        updateInspector()
    }

    private func nudgeObject(id: UUID, property: CAM_ObjectsInspectorView.Property, amount: CGFloat) {
        guard state.selectedObjectIDs.contains(id), let object = object(withID: id) else {
            return
        }
        switch property {
            case .x: object.position.x += amount
            case .y: object.position.y += amount
            default: return
        }
        render()
        updateInspector()
    }

    private func scaleObject(id: UUID, scaleFactor: Int) {
        guard state.selectedObjectIDs.contains(id), let object = object(withID: id) else {
            return
        }
        object.width = scaleFactor > 0
            ? max(object.width * CGFloat(scaleFactor), 0.001)
            : max(object.width / CGFloat(-scaleFactor), 0.001)

        render()
        updateInspector()
    }

    private func rotateObject(id: UUID, degrees: CGFloat) {
        guard state.selectedObjectIDs.contains(id), let object = object(withID: id) else {
            return
        }
        object.rotate(by: degrees)
        render()
        updateInspector()
    }

    private func object(withID id: UUID) -> CAM_Object? {
        state.objects.first { $0.id == id }
    }

    private func updateInspector() {
        inspectorView.update(elements: state.objects,
                             selectedID: state.selectedObjectIDs.first)
    }
}
