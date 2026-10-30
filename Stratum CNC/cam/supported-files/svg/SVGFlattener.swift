//
//  SVGFlattener.swift
//  Stratum CNC
//
//  PocketSVG only reads <path>-like elements that are drawn directly. SVGs
//  exported by Flash/Animate-style tools keep the geometry inside <defs> and
//  draw it through <use xlink:href="#id"> under transformed <g> groups.
//  PocketSVG finds no paths in those, so the import silently produced nothing.
//
//  This rewrites such a file into a flat one: every drawn <path> is emitted
//  at the top level, carrying the accumulated transform of its ancestors
//  (and of any <use> that referenced it) in its own `transform` attribute,
//  which SVGImporter already applies.
//

import Foundation
import CoreGraphics

enum SVGFlattener {

    /// Returns a URL to import: the original when it needs no work,
    /// otherwise a temporary flattened copy.
    static func flattenedURLIfNeeded(for url: URL) -> URL {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              text.contains("<use") || text.contains("<defs") else {
            return url
        }
        guard let doc = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]),
              let root = doc.rootElement() else {
            return url
        }

        var defs: [String: XMLElement] = [:]
        collectIDs(in: root, into: &defs)

        var flatPaths: [XMLElement] = []
        walk(root, transform: .identity, defs: defs, inDefs: false, out: &flatPaths, depth: 0)
        guard !flatPaths.isEmpty else { return url }

        let newRoot = XMLElement(name: "svg")
        for attr in root.attributes ?? [] {
            guard let name = attr.name, !name.hasPrefix("xmlns:") else { continue }
            newRoot.addAttribute(XMLNode.attribute(withName: name, stringValue: attr.stringValue ?? "") as! XMLNode)
        }
        flatPaths.forEach { newRoot.addChild($0) }
        let out = XMLDocument(rootElement: newRoot)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("flat-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try out.xmlData.write(to: tmp)
            return tmp
        } catch {
            return url
        }
    }

    private static let drawable: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]

    private static func collectIDs(in element: XMLElement, into map: inout [String: XMLElement]) {
        if let id = element.attribute(forName: "id")?.stringValue { map[id] = element }
        for case let child as XMLElement in element.children ?? [] { collectIDs(in: child, into: &map) }
    }

    private static func walk(_ el: XMLElement, transform: CGAffineTransform, defs: [String: XMLElement],
                             inDefs: Bool, out: inout [XMLElement], depth: Int) {
        guard depth < 32 else { return }   // guards against <use> cycles
        let name = el.name ?? ""
        if name == "defs" || name == "symbol" || name == "clipPath" || name == "mask" { return }

        var t = transform
        if let s = el.attribute(forName: "transform")?.stringValue {
            t = parseTransform(s).concatenating(transform)   // child applied first, then ancestors
        }

        if name == "use" {
            let ref = (el.attribute(forName: "xlink:href") ?? el.attribute(forName: "href"))?.stringValue ?? ""
            guard ref.hasPrefix("#"), let target = defs[String(ref.dropFirst())] else { return }
            var ut = t
            let x = Double(el.attribute(forName: "x")?.stringValue ?? "") ?? 0
            let y = Double(el.attribute(forName: "y")?.stringValue ?? "") ?? 0
            if x != 0 || y != 0 { ut = CGAffineTransform(translationX: x, y: y).concatenating(ut) }
            walk(target, transform: ut, defs: defs, inDefs: true, out: &out, depth: depth + 1)
            return
        }

        if drawable.contains(name) {
            let copy = el.copy() as! XMLElement
            copy.removeAttribute(forName: "id")
            copy.removeAttribute(forName: "transform")
            if !t.isIdentity {
                copy.addAttribute(XMLNode.attribute(withName: "transform", stringValue:
                    "matrix(\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty))") as! XMLNode)
            }
            out.append(copy)
            return
        }

        for case let child as XMLElement in el.children ?? [] {
            walk(child, transform: t, defs: defs, inDefs: inDefs, out: &out, depth: depth + 1)
        }
    }

    /// matrix(), translate(), scale(), rotate() — applied left to right as in SVG.
    private static func parseTransform(_ string: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let regex = try! NSRegularExpression(pattern: #"(matrix|translate|scale|rotate)\s*\(([^)]*)\)"#)
        let ns = string as NSString
        for m in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
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
                } else { op = CGAffineTransform(rotationAngle: r) }
            default: break
            }
            result = op.concatenating(result)
        }
        return result
    }
}
