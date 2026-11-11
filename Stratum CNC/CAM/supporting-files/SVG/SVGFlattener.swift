import Foundation
import CoreGraphics
#if canImport(FoundationXML)
import FoundationXML   // XMLParser lives here on Linux; on Apple platforms it's in Foundation
#endif

/// Flattens `<use>` / `<defs>` in an SVG into plain drawable elements with baked-in transforms.
/// Uses XMLParser (available on macOS and iOS) instead of XMLDocument (macOS only).
enum SVGFlattener {

    /// Returns a URL to import: the original when it needs no work,
    /// otherwise a temporary flattened copy.
    static func flattenedURLIfNeeded(for url: URL) -> URL {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              text.contains("<use") || text.contains("<defs"),
              let root = parseTree(from: data) else {
            return url
        }

        var defs: [String: Node] = [:]
        collectIDs(in: root, into: &defs)

        var flatPaths: [Node] = []
        walk(root, transform: .identity, defs: defs, out: &flatPaths, depth: 0)
        guard !flatPaths.isEmpty else {
            return url
        }

        // Keep root attributes (viewBox, width, height, xmlns...) except prefixed namespace declarations.
        let newRoot = Node(name: "svg",
                           attributes: root.attributes.filter { !$0.key.hasPrefix("xmlns:") })
        newRoot.children = flatPaths

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        newRoot.write(to: &xml)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("flat-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try Data(xml.utf8).write(to: tmp)
            return tmp
        } catch {
            return url
        }
    }

    // MARK: - Minimal XML tree

    private final class Node {
        let name: String
        var attributes: [String: String]
        var children: [Node] = []

        init(name: String, attributes: [String: String]) {
            self.name = name
            self.attributes = attributes
        }

        func deepCopy() -> Node {
            let copy = Node(name: name, attributes: attributes)
            copy.children = children.map { $0.deepCopy() }
            return copy
        }

        func write(to out: inout String) {
            out += "<\(name)"
            for key in attributes.keys.sorted() {
                out += " \(key)=\"\(Node.escape(attributes[key] ?? ""))\""
            }
            if children.isEmpty {
                out += "/>"
            } else {
                out += ">"
                for child in children {
                    child.write(to: &out)
                }
                out += "</\(name)>"
            }
        }

        private static func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "\n", with: "&#10;")
                .replacingOccurrences(of: "\t", with: "&#9;")
        }
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        private(set) var root: Node?
        private var stack: [Node] = []

        func parser(_ parser: XMLParser,
                    didStartElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            let node = Node(name: elementName, attributes: attributeDict)
            if let parent = stack.last {
                parent.children.append(node)
            } else if root == nil {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser,
                    didEndElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName qName: String?) {
            _ = stack.popLast()
        }
    }

    private static func parseTree(from data: Data) -> Node? {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false      // keep "xlink:href" etc. as written
        parser.shouldResolveExternalEntities = false
        let builder = TreeBuilder()
        parser.delegate = builder
        guard parser.parse() else {
            return nil
        }
        return builder.root
    }

    // MARK: - Flattening

    private static let drawable: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]

    private static func collectIDs(in node: Node, into map: inout [String: Node]) {
        if let id = node.attributes["id"] {
            map[id] = node
        }
        for child in node.children {
            collectIDs(in: child, into: &map)
        }
    }

    private static func walk(_ el: Node,
                             transform: CGAffineTransform,
                             defs: [String: Node],
                             out: inout [Node],
                             depth: Int) {

        guard depth < 32 else {
            return
        }   // guards against <use> cycles
        let name = el.name
        if name == "defs" || name == "symbol" || name == "clipPath" || name == "mask" {
            return
        }

        var t = transform
        if let s = el.attributes["transform"] {
            t = parseTransform(s).concatenating(transform)   // child applied first, then ancestors
        }

        if name == "use" {
            let ref = el.attributes["xlink:href"] ?? el.attributes["href"] ?? ""
            guard ref.hasPrefix("#"), let target = defs[String(ref.dropFirst())] else {
                return
            }
            var ut = t
            let x = Double(el.attributes["x"] ?? "") ?? 0
            let y = Double(el.attributes["y"] ?? "") ?? 0
            if x != 0 || y != 0 {
                ut = CGAffineTransform(translationX: x, y: y).concatenating(ut)
            }
            walk(target, transform: ut, defs: defs, out: &out, depth: depth + 1)
            return
        }

        if drawable.contains(name) {
            let copy = el.deepCopy()
            copy.attributes["id"] = nil
            copy.attributes["transform"] = nil
            if !t.isIdentity {
                copy.attributes["transform"] = "matrix(\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty))"
            }
            out.append(copy)
            return
        }

        for child in el.children {
            walk(child, transform: t, defs: defs, out: &out, depth: depth + 1)
        }
    }

    private static let transformRegex = try! NSRegularExpression(
        pattern: #"(matrix|translate|scale|rotate)\s*\(([^)]*)\)"#)

    /// matrix(), translate(), scale(), rotate() — applied left to right as in SVG.
    private static func parseTransform(_ string: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let ns = string as NSString

        for m in transformRegex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            let fn = ns.substring(with: m.range(at: 1))
            let v = ns.substring(with: m.range(at: 2))
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
                .compactMap { Double($0) }.map { CGFloat($0) }
            var op = CGAffineTransform.identity

            switch fn {
                case "matrix" where v.count == 6:
                    op = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
                case "translate" where v.count >= 1:
                    op = CGAffineTransform(translationX: v[0], y: v.count > 1 ? v[1] : 0)
                case "scale" where v.count >= 1:
                    op = CGAffineTransform(scaleX: v[0], y: v.count > 1 ? v[1] : v[0])
                case "rotate" where v.count >= 1:
                    let r = v[0] * .pi / 180
                    if v.count == 3 {
                        op = CGAffineTransform(translationX: v[1], y: v[2]).rotated(by: r).translatedBy(x: -v[1], y: -v[2])
                    } else {
                        op = CGAffineTransform(rotationAngle: r)
                    }
                default: break
            }
            result = op.concatenating(result)
        }
        return result
    }
}
