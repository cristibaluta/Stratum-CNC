//
//  SVGFlattenerTests.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 11.11.2026.
//

import XCTest
import Foundation
import CoreGraphics
@testable import Stratum_CNC

/// These tests only use `SVGFlattener.flattenedURLIfNeeded(for:)` and inspect the output
/// structurally (parsed with XMLParser), so they run unchanged against the old
/// XMLDocument version (macOS) and the new XMLParser version (macOS + iOS).
final class SVGFlattenerTests: XCTestCase {

    // MARK: - Helpers

    private var tempDirs: [URL] = []
    private var outputs: [URL] = []

    override func tearDown() {
        (tempDirs + outputs).forEach { try? FileManager.default.removeItem(at: $0) }
        tempDirs.removeAll()
        outputs.removeAll()
        super.tearDown()
    }

    private func writeSVG(_ content: String, name: String = "test.svg") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svgflattener-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Runs the flattener and registers the output for cleanup.
    private func flatten(_ svg: String, name: String = "test.svg") throws -> (input: URL, output: URL) {
        let input = try writeSVG(svg, name: name)
        let output = SVGFlattener.flattenedURLIfNeeded(for: input)
        if output != input { outputs.append(output) }
        return (input, output)
    }

    private struct Element {
        let name: String
        let attributes: [String: String]
    }

    private final class Probe: NSObject, XMLParserDelegate {
        var elements: [Element] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            elements.append(Element(name: elementName, attributes: attributeDict))
        }
    }

    private func parseElements(at url: URL) throws -> [Element] {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        let probe = Probe()
        parser.delegate = probe
        XCTAssertTrue(parser.parse(), "Output is not well-formed XML: \(parser.parserError?.localizedDescription ?? "")")
        return probe.elements
    }

    private let drawableNames: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]

    private func drawables(_ elements: [Element]) -> [Element] {
        elements.filter { drawableNames.contains($0.name) }
    }

    private func matrix(of el: Element, file: StaticString = #filePath, line: UInt = #line) throws -> [Double] {
        let s = try XCTUnwrap(el.attributes["transform"], "missing transform", file: file, line: line)
        XCTAssertTrue(s.hasPrefix("matrix("), "unexpected transform: \(s)", file: file, line: line)
        let inner = s.replacingOccurrences(of: "matrix(", with: "").replacingOccurrences(of: ")", with: "")
        let nums = inner.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        XCTAssertEqual(nums.count, 6, file: file, line: line)
        return nums
    }

    private func assertMatrix(_ el: Element, _ expected: [Double],
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let m = try matrix(of: el, file: file, line: line)
        guard m.count == expected.count else { return }
        for (i, (a, b)) in zip(m, expected).enumerated() {
            XCTAssertEqual(a, b, accuracy: 1e-9, "matrix[\(i)] of \(m)", file: file, line: line)
        }
    }

    // MARK: - No-op cases (original URL returned)

    func testPlainSVGWithoutUseOrDefsReturnsOriginalURL() throws {
        let (input, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg"><rect x="0" y="0" width="10" height="10"/></svg>
        """)
        XCTAssertEqual(output, input)
    }

    func testDefsWithoutAnyUseReturnsOriginalURL() throws {
        let (input, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg"><defs><path id="a" d="M0 0 L1 1"/></defs></svg>
        """)
        XCTAssertEqual(output, input, "Nothing drawable outside defs, so nothing to flatten")
    }

    func testUseWithMissingReferenceReturnsOriginalURL() throws {
        let (input, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg"><use href="#nope"/></svg>
        """)
        XCTAssertEqual(output, input)
    }

    func testUseWithNonFragmentHrefIsIgnored() throws {
        let (input, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg"><defs><path id="a" d="M0 0"/></defs><use href="other.svg#a"/></svg>
        """)
        XCTAssertEqual(output, input)
    }

    func testMalformedXMLReturnsOriginalURL() throws {
        let (input, output) = try flatten("<svg><use href=\"#a\"><defs></svg>")
        XCTAssertEqual(output, input)
    }

    func testMissingFileReturnsOriginalURL() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).svg")
        XCTAssertEqual(SVGFlattener.flattenedURLIfNeeded(for: url), url)
    }

    // MARK: - Basic flattening

    func testUseOfPathInDefsIsInlined() throws {
        let (input, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <defs><path id="a" d="M0 0 L10 10"/></defs>
          <use href="#a"/>
        </svg>
        """)
        XCTAssertNotEqual(output, input)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(output.lastPathComponent.hasSuffix("test.svg"))

        let els = try parseElements(at: output)
        XCTAssertEqual(els.first?.name, "svg")
        XCTAssertFalse(els.contains { $0.name == "use" || $0.name == "defs" })

        let paths = drawables(els)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].name, "path")
        XCTAssertEqual(paths[0].attributes["d"], "M0 0 L10 10")
        XCTAssertNil(paths[0].attributes["id"], "ids must be stripped")
        XCTAssertNil(paths[0].attributes["transform"], "identity transform should not be written")
    }

    func testXlinkHrefIsSupportedAndNamespacePrefixDeclarationDropped() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
             viewBox="0 0 50 50" width="50" height="50">
          <defs><circle id="c" cx="5" cy="5" r="2"/></defs>
          <use xlink:href="#c"/>
        </svg>
        """)
        let els = try parseElements(at: output)
        let root = try XCTUnwrap(els.first)
        XCTAssertEqual(root.attributes["viewBox"], "0 0 50 50")
        XCTAssertEqual(root.attributes["width"], "50")
        XCTAssertEqual(root.attributes["height"], "50")
        XCTAssertEqual(root.attributes["xmlns"], "http://www.w3.org/2000/svg")
        XCTAssertNil(root.attributes["xmlns:xlink"])
        XCTAssertEqual(drawables(els).count, 1)
        XCTAssertEqual(drawables(els)[0].name, "circle")
    }

    func testOnlyReferencedDefsAreEmitted() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs>
            <path id="used" d="M0 0 L1 1"/>
            <path id="unused" d="M5 5 L6 6"/>
          </defs>
          <rect width="10" height="10"/>
          <use href="#used"/>
        </svg>
        """)
        let shapes = drawables(try parseElements(at: output))
        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(shapes.filter { $0.name == "rect" }.count, 1)
        XCTAssertEqual(shapes.filter { $0.attributes["d"] == "M5 5 L6 6" }.count, 0)
        XCTAssertEqual(shapes.filter { $0.attributes["d"] == "M0 0 L1 1" }.count, 1)
    }

    func testUseOfGroupEmitsAllChildren() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><g id="g"><rect width="1" height="1"/><circle r="2"/></g></defs>
          <use href="#g"/>
        </svg>
        """)
        let names = drawables(try parseElements(at: output)).map(\.name).sorted()
        XCTAssertEqual(names, ["circle", "rect"])
    }

    func testNonDrawableElementsAreDropped() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><path id="a" d="M0 0"/></defs>
          <title>hello</title>
          <g><use href="#a"/></g>
        </svg>
        """)
        let els = try parseElements(at: output)
        XCTAssertEqual(Set(els.map(\.name)), ["svg", "path"])
    }

    // MARK: - Transforms

    func testUseXYBecomesTranslation() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><path id="a" d="M0 0"/></defs>
          <use href="#a" x="10" y="20"/>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        try assertMatrix(p, [1, 0, 0, 1, 10, 20])
    }

    func testUseTransformAndXYCombine() throws {
        // SVG semantics: transform="scale(2)" then translate(x,y) in the scaled space -> tx = 20, ty = 10
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><path id="a" d="M0 0"/></defs>
          <use href="#a" transform="scale(2)" x="10" y="5"/>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        try assertMatrix(p, [2, 0, 0, 2, 20, 10])
    }

    func testAncestorTransformWithUse() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><rect id="r" transform="scale(2)" width="1" height="1"/></defs>
          <g transform="translate(10,20)"><use href="#r"/></g>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        try assertMatrix(p, [2, 0, 0, 2, 10, 20])
    }

    func testTransformListIsAppliedRightToLeftOnPoints() throws {
        // "translate(10 0) scale(2)": scale first, then translate
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><rect id="r" width="1" height="1"/></defs>
          <use href="#r" transform="translate(10 0) scale(2)"/>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        try assertMatrix(p, [2, 0, 0, 2, 10, 0])
    }

    func testRotateAroundPoint() throws {
        // rotate(90 10 10): the point (10,10) stays fixed -> matrix(0 1 -1 0 20 0)
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><rect id="r" width="1" height="1"/></defs>
          <use href="#r" transform="rotate(90 10 10)"/>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        try assertMatrix(p, [0, 1, -1, 0, 20, 0])
    }

    func testMatrixAndCommaSeparatedValues() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><rect id="r" width="1" height="1"/></defs>
          <use href="#r" transform="matrix(1,2,3,4,5,6)"/>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        try assertMatrix(p, [1, 2, 3, 4, 5, 6])
    }

    func testNonUniformAndSingleValueScale() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><rect id="r" width="1" height="1"/></defs>
          <use href="#r" transform="scale(3)"/>
          <use href="#r" transform="scale(2 4)"/>
        </svg>
        """)
        let shapes = drawables(try parseElements(at: output))
        XCTAssertEqual(shapes.count, 2)
        try assertMatrix(shapes[0], [3, 0, 0, 3, 0, 0])
        try assertMatrix(shapes[1], [2, 0, 0, 4, 0, 0])
    }

    // MARK: - Robustness

    func testUseCycleTerminates() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><g id="a"><use href="#a"/><rect width="1" height="1"/></g></defs>
          <use href="#a"/>
        </svg>
        """)
        XCTAssertFalse(drawables(try parseElements(at: output)).isEmpty)
    }

    func testSpecialCharactersInAttributesRoundTrip() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs><path id="a" d="M0 0" data-label="a &amp; b &lt; c &quot;q&quot;"/></defs>
          <use href="#a"/>
        </svg>
        """)
        let p = try XCTUnwrap(drawables(try parseElements(at: output)).first)
        XCTAssertEqual(p.attributes["data-label"], "a & b < c \"q\"")
    }

    func testOutputFileNameKeepsOriginalName() throws {
        let (_, output) = try flatten("""
        <svg xmlns="http://www.w3.org/2000/svg"><defs><path id="a" d="M0 0"/></defs><use href="#a"/></svg>
        """, name: "logo.svg")
        XCTAssertTrue(output.lastPathComponent.hasPrefix("flat-"))
        XCTAssertTrue(output.lastPathComponent.hasSuffix("-logo.svg"))
    }
}
