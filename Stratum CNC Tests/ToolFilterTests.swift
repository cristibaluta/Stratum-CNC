//
//  ToolFilterTests.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 31.10.2026.
//


//
//  ToolFilterTests.swift
//  Stratum CNC
//
//  If the module name differs, adjust the @testable import below
//  ("Stratum CNC" becomes Stratum_CNC).
//

import XCTest
@testable import Stratum_CNC

final class ToolFilterTests: XCTestCase {

    private func tool(
        _ name: String,
        _ type: ToolType = .endMill,
        d: Double = 3,
        length: Double? = 10,
        qty: Int = 0
    ) -> Tool {
        Tool(name: name, shankDiameter: 3.175, toolDiameter: d, length: length, type: type, quantity: qty)
    }

    private var sample: [Tool] {
        [
            tool("6mm Flat End", .endMill, d: 6, length: 22, qty: 2),
            tool("1mm Flat End(Metal)", .endMill, d: 1, length: 3),
            tool("3.175mm Ball Nose", .ballNose, d: 3.175, length: 12, qty: 1),
            tool("0.8mm PCB drill", .drill, d: 0.8, length: nil, qty: 5),
            tool("1mm PCB drill", .drill, d: 1, length: nil),
            tool("Engraving Metal 0.1mm", .engraving, d: 0.1, length: nil)
        ]
    }

    // MARK: Scope

    func testAllScopeReturnsEverything() {
        XCTAssertEqual(ToolFilter().apply(to: sample).count, 6)
    }

    func testTypeScope() {
        var filter = ToolFilter()
        filter.scope = .type(.drill)
        XCTAssertEqual(filter.apply(to: sample).map(\.name), ["0.8mm PCB drill", "1mm PCB drill"])
    }

    func testInStockScope() {
        var filter = ToolFilter()
        filter.scope = .inStock
        XCTAssertEqual(Set(filter.apply(to: sample).map(\.name)),
                       ["6mm Flat End", "3.175mm Ball Nose", "0.8mm PCB drill"])
    }

    // MARK: Search

    func testSearchByName() {
        var filter = ToolFilter()
        filter.query = "ball"
        XCTAssertEqual(filter.apply(to: sample).map(\.name), ["3.175mm Ball Nose"])
    }

    func testSearchIsCaseInsensitive() {
        var filter = ToolFilter()
        filter.query = "BALL"
        XCTAssertEqual(filter.apply(to: sample).count, 1)
    }

    func testSearchByTypeName() {
        var filter = ToolFilter()
        filter.query = "end mill"
        XCTAssertEqual(filter.apply(to: sample).count, 2)
    }

    func testSearchByDiameter() {
        var filter = ToolFilter()
        filter.query = "3.175"
        XCTAssertEqual(filter.apply(to: sample).map(\.name), ["3.175mm Ball Nose"])
    }

    func testSearchWordsAreAndedInAnyOrder() {
        var filter = ToolFilter()
        filter.query = "nose 3.175"
        XCTAssertEqual(filter.apply(to: sample).count, 1)
        filter.query = "3.175 nose"
        XCTAssertEqual(filter.apply(to: sample).count, 1)
        filter.query = "nose drill"
        XCTAssertEqual(filter.apply(to: sample).count, 0)
    }

    func testBlankQueryMatchesEverything() {
        var filter = ToolFilter()
        filter.query = "   "
        XCTAssertEqual(filter.apply(to: sample).count, 6)
        XCTAssertFalse(filter.hasRefinements)
    }

    // MARK: Material

    func testMaterialFilter() {
        var filter = ToolFilter()
        filter.material = .metal
        XCTAssertEqual(Set(filter.apply(to: sample).map(\.name)),
                       ["1mm Flat End(Metal)", "Engraving Metal 0.1mm"])

        filter.material = .nonMetal
        XCTAssertEqual(filter.apply(to: sample).count, 4)
    }

    func testFiltersCombine() {
        var filter = ToolFilter()
        filter.scope = .type(.endMill)
        filter.material = .metal
        filter.query = "1mm"
        XCTAssertEqual(filter.apply(to: sample).map(\.name), ["1mm Flat End(Metal)"])
    }

    // MARK: Sorting

    func testSortsByTypeThenDiameter() {
        let names = ToolFilter().apply(to: sample).map(\.name)
        XCTAssertEqual(names, [
            "1mm Flat End(Metal)",   // end mills by diameter
            "6mm Flat End",
            "3.175mm Ball Nose",     // ball nose
            "Engraving Metal 0.1mm", // engraving
            "0.8mm PCB drill",       // drills by diameter
            "1mm PCB drill"
        ])
    }

    func testSameDiameterSortsByLengthThenName() {
        let tools = [
            tool("B", d: 3, length: 20),
            tool("A", d: 3, length: 20),
            tool("C", d: 3, length: 5)
        ]
        XCTAssertEqual(ToolFilter().apply(to: tools).map(\.name), ["C", "A", "B"])
    }

    func testNaturalNameOrderForTies() {
        let tools = [tool("Bit 10"), tool("Bit 2")]
        XCTAssertEqual(ToolFilter().apply(to: tools).map(\.name), ["Bit 2", "Bit 10"])
    }

    // MARK: Counts

    func testCountsWithNoFilters() {
        let counts = ToolFilter().counts(in: sample)
        XCTAssertEqual(counts[.all], 6)
        XCTAssertEqual(counts[.inStock], 3)
        XCTAssertEqual(counts[.type(.endMill)], 2)
        XCTAssertEqual(counts[.type(.drill)], 2)
        XCTAssertNil(counts[.type(.chamfer)])
    }

    func testCountsIgnoreScopeButRespectRefinements() {
        var filter = ToolFilter()
        filter.scope = .type(.drill)          // must not change the counts
        filter.material = .metal
        let counts = filter.counts(in: sample)
        XCTAssertEqual(counts[.all], 2)
        XCTAssertEqual(counts[.type(.endMill)], 1)
        XCTAssertEqual(counts[.type(.engraving)], 1)
        XCTAssertNil(counts[.type(.drill)])
        XCTAssertEqual(counts[.inStock], 0)
    }

    func testCountsRespectSearch() {
        var filter = ToolFilter()
        filter.query = "pcb"
        let counts = filter.counts(in: sample)
        XCTAssertEqual(counts[.all], 2)
        XCTAssertEqual(counts[.inStock], 1)
    }

    // MARK: Refinements

    func testClearRefinementsKeepsScope() {
        var filter = ToolFilter()
        filter.scope = .type(.drill)
        filter.material = .metal
        filter.query = "x"
        XCTAssertTrue(filter.hasRefinements)

        filter.clearRefinements()
        XCTAssertFalse(filter.hasRefinements)
        XCTAssertEqual(filter.scope, .type(.drill))
    }
}