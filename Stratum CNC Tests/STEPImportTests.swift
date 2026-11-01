import Foundation
import Testing
@testable import Stratum_CNC

struct STEPImportTests {
    private func document(_ records: String) -> Data {
        Data("ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('fixture'),'2;1');\nENDSEC;\nDATA;\n\(records)\nENDSEC;\nEND-ISO-10303-21;".utf8)
    }

    /// Topology fixture, not a reference CAD export: face surfaces are intentionally
    /// unused by edge extraction. The original square.step is not in the repository.
    private func boxRecords() -> String {
        let points = [(0,0,0), (10,0,0), (10,10,0), (0,10,0), (0,0,1), (10,0,1), (10,10,1), (0,10,1)]
        let edges = [(0,1), (1,2), (2,3), (3,0), (4,5), (5,6), (6,7), (7,4), (0,4), (1,5), (2,6), (3,7)]
        let faces: [[(Int, Bool)]] = [
            [(0,true),(1,true),(2,true),(3,true)],
            [(4,true),(5,true),(6,true),(7,true)],
            [(0,true),(9,true),(4,false),(8,false)],
            [(1,true),(10,true),(5,false),(9,false)],
            [(2,true),(11,true),(6,false),(10,false)],
            [(3,true),(8,true),(7,false),(11,false)]
        ]
        var records: [String] = []
        for (i, p) in points.enumerated() {
            records += ["#\(i + 1)=CARTESIAN_POINT('',(\(p.0).,\(p.1).,\(p.2).));", "#\(i + 11)=VERTEX_POINT('',#\(i + 1));"]
        }
        for (i, edge) in edges.enumerated() {
            let a = points[edge.0], b = points[edge.1]
            records += [
                "#\(300+i)=DIRECTION('',(\(b.0-a.0).,\(b.1-a.1).,\(b.2-a.2).));",
                "#\(320+i)=VECTOR('',#\(300+i),1.);",
                "#\(30+i)=LINE('',#\(edge.0+1),#\(320+i));",
                "#\(50+i)=EDGE_CURVE('',#\(edge.0+11),#\(edge.1+11),#\(30+i),.T.);"
            ]
        }
        for (f, uses) in faces.enumerated() {
            for (j, use) in uses.enumerated() {
                records.append("#\(200+f*4+j)=ORIENTED_EDGE('',*,*,#\(50+use.0),.\(use.1 ? "T" : "F").);")
            }
            let refs = (0..<4).map { "#\(200+f*4+$0)" }.joined(separator: ",")
            records += [
                "#\(120+f)=EDGE_LOOP('',(\(refs)));",
                "#\(130+f)=FACE_OUTER_BOUND('',#\(120+f),.T.);",
                "#\(110+f)=ADVANCED_FACE('',(#\(130+f)),#180,.T.);"
            ]
        }
        records += [
            "#140=MANIFOLD_SOLID_BREP('box',#141);",
            "#141=CLOSED_SHELL('',(#110,#111,#112,#113,#114,#115));",
            "#150=ADVANCED_BREP_SHAPE_REPRESENTATION('',(#140),#160);",
            "#160=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#161)) REPRESENTATION_CONTEXT('',''));",
            "#161=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));",
            "#162=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));",
            "#180=PLANE('',#181);",
            "#181=AXIS2_PLACEMENT_3D('',#1,$,$);",
            "#900=EDGE_CURVE('unused construction edge',#11,#18,#30,.T.);"
        ]
        // Forward references and source order must not change extraction order.
        return records.reversed().joined(separator: "\n")
    }

    @Test func indexesComplexEntitiesAndParsesPart21ValuesLazily() throws {
        let file = try STEPFile(data: document("""
            /* #88=FAKE(); DATA; */
            #900=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));
            #7=VALUES('a''b; /* not a comment */ #1',(#900,$,*),10.,-2,1.E-3,+.5,.T.,.F.,.U.,LENGTH_MEASURE(25.4));
            """))
        #expect(file.index.count == 2)
        #expect(file.index[900]?.map(\.type) == ["LENGTH_UNIT", "NAMED_UNIT", "SI_UNIT"])
        let p = try file.parameters(7, type: "VALUES")
        #expect(p[0] == .string("a'b; /* not a comment */ #1"))
        #expect(p[1] == .list([.reference(900), .unset, .derived]))
        #expect(p[2] == .real(10))
        #expect(p[3] == .integer(-2))
        #expect(p[4] == .real(0.001))
        #expect(p[5] == .real(0.5))
        #expect(p[9] == .typed("LENGTH_MEASURE", [.real(25.4)]))
        #expect(try file.parameters(900, type: "NAMED_UNIT") == [.derived])
    }

    @Test func boxHasTwelveScopedEdgesAndEightVertices() throws {
        let importID = UUID()
        let data = document(boxRecords())
        let model = try STEPEdgeImporter.parse(data: data, importID: importID)
        #expect(model.edges.count == 12)
        #expect(model.reachableEdgeCount == 12)
        #expect(model.skippedEdgeCount == 0)
        #expect(model.diagnostics.isEmpty)
        #expect(model.bodies.count == 1)
        #expect(model.bodies.first?.unitScaleToMM == 1)
        #expect(model.bounds?.min == SIMD3<Double>(0,0,0))
        #expect(model.bounds?.max == SIMD3<Double>(10,10,1))
        #expect(Set(model.edges.flatMap { [$0.startVertexID, $0.endVertexID] }).count == 8)
        #expect(model.edges.allSatisfy { $0.adjacentFaceIDs.count == 2 && $0.id.importID == importID })
        #expect(model.edges.map(\.id.entityID) == Array(50...61))
        let repeated = try STEPEdgeImporter.parse(data: data, importID: importID)
        #expect(model.edges.map(\.id) == repeated.edges.map(\.id))
    }

    @Test func unitsComeFromEachRepresentationNotFileOrder() throws {
        let records = boxRecords() + """
            \n#151=ADVANCED_BREP_SHAPE_REPRESENTATION('',(#140),#170);
            #170=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#162)) REPRESENTATION_CONTEXT('',''));
            """
        let result = try STEPEdgeImporter.parse(data: document(records))
        #expect(result.edges.count == 24)
        #expect(Set(result.edges.map(\.id)).count == 24)
        #expect(result.bodies.map(\.unitScaleToMM) == [1, 1000])
        #expect(result.bounds?.max == SIMD3<Double>(10000,10000,1000))
        #expect(result.diagnostics.isEmpty)
    }

    @Test func conversionBasedInchesAndRecursiveFeet() throws {
        let conversion = """
            \n#163=(CONVERSION_BASED_UNIT('inch',#164) LENGTH_UNIT() NAMED_UNIT(*));
            #164=LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(25.4),#161);
            #165=(CONVERSION_BASED_UNIT('foot',#166) LENGTH_UNIT() NAMED_UNIT(*));
            #166=(LENGTH_MEASURE_WITH_UNIT() MEASURE_WITH_UNIT(LENGTH_MEASURE(12.),#163));
            """
        for (unit, scale) in [(163,25.4), (165,304.8)] {
            let records = boxRecords().replacingOccurrences(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#161))", with: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#\(unit)))") + conversion
            let result = try STEPEdgeImporter.parse(data: document(records))
            #expect(abs(try #require(result.bodies.first).unitScaleToMM - scale) < 1e-10)
            #expect(abs(try #require(result.bounds).max.x - 10 * scale) < 1e-9)
        }
    }

    @Test func unresolvedUnitsRequireExplicitAssumption() throws {
        let data = document(boxRecords().replacingOccurrences(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#161))", with: "GLOBAL_UNIT_ASSIGNED_CONTEXT(())"))
        #expect(throws: STEPParseError.self) { try STEPEdgeImporter.parse(data: data) }
        let model = try STEPEdgeImporter.parse(data: data, options: STEPImportOptions(assumedUnitScaleToMM: 1))
        #expect(model.edges.count == 12)
        #expect(model.bodies.first?.unitsAssumed == true)
        #expect(model.diagnostics.contains { $0.entityID == 160 && $0.message.contains("assuming") })
        #expect(throws: STEPParseError.self) {
            try STEPEdgeImporter.parse(data: data, options: STEPImportOptions(assumedUnitScaleToMM: .nan))
        }
    }

    @Test func rejectsAmbiguousAndCyclicUnits() throws {
        let ambiguous = boxRecords().replacingOccurrences(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#161))", with: "GLOBAL_UNIT_ASSIGNED_CONTEXT((#161,#162))")
        #expect(throws: STEPParseError.self) { try STEPEdgeImporter.parse(data: document(ambiguous)) }
        let cycle = boxRecords().replacingOccurrences(of: "#161=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.));", with: "#161=(CONVERSION_BASED_UNIT('cycle',#164) LENGTH_UNIT() NAMED_UNIT(*));\n#164=MEASURE_WITH_UNIT(LENGTH_MEASURE(1.),#161);")
        #expect(throws: STEPParseError.self) { try STEPEdgeImporter.parse(data: document(cycle)) }
    }

    @Test func surfaceAndSeamWrappersReachTheirLine() throws {
        let records = boxRecords().replacingOccurrences(of: "#50=EDGE_CURVE('',#11,#12,#30,.T.);", with: "#50=EDGE_CURVE('',#11,#12,#700,.F.);") + """
            \n#700=SEAM_CURVE('',#701,(),.CURVE_3D.);
            #701=SURFACE_CURVE('',#30,(),.CURVE_3D.);
            """
        let model = try STEPEdgeImporter.parse(data: document(records))
        #expect(model.edges.count == 12)
        #expect(model.diagnostics.isEmpty)
        #expect(model.edges.first?.points == [SIMD3<Double>(0,0,0), SIMD3<Double>(10,0,0)])
    }

    @Test func unsupportedCurvesAndBrokenVerticesAreSkippedNotInvented() throws {
        let records = boxRecords()
            .replacingOccurrences(of: "#30=LINE('',#1,#320);", with: "#30=CIRCLE('',#181,5.);")
            .replacingOccurrences(of: "#51=EDGE_CURVE('',#12,#13,#31,.T.);", with: "#51=EDGE_CURVE('',#99999,#13,#31,.T.);")
        let model = try STEPEdgeImporter.parse(data: document(records))
        #expect(model.edges.count == 10)
        #expect(model.reachableEdgeCount == 12)
        #expect(model.skippedEdgeCount == 2)
        #expect(model.diagnostics.contains { $0.entityID == 50 && $0.message.contains("CIRCLE") })
        #expect(model.diagnostics.contains { $0.entityID == 51 && $0.message.contains("99999") })
    }

    @Test func openShellAndVoidsTraverseTheSameScopedTopology() throws {
        let open = boxRecords()
            .replacingOccurrences(of: "#140=MANIFOLD_SOLID_BREP('box',#141);", with: "#140=SHELL_BASED_SURFACE_MODEL('box',(#141));")
            .replacingOccurrences(of: "#141=CLOSED_SHELL", with: "#141=OPEN_SHELL")
        #expect(try STEPEdgeImporter.parse(data: document(open)).edges.count == 12)
        let voids = boxRecords().replacingOccurrences(of: "#140=MANIFOLD_SOLID_BREP('box',#141);", with: "#140=BREP_WITH_VOIDS('box',#141,(#142));\n#142=ORIENTED_CLOSED_SHELL('',*,#141,.F.);")
        #expect(try STEPEdgeImporter.parse(data: document(voids)).edges.count == 12)
    }

    @Test func cyclesAndMalformedTopologyProduceDiagnostics() throws {
        let topology = boxRecords().replacingOccurrences(of: "#130=FACE_OUTER_BOUND('',#120,.T.);", with: "#130=FACE_OUTER_BOUND('',#130,.T.);")
        let model = try STEPEdgeImporter.parse(data: document(topology))
        #expect(model.diagnostics.contains { $0.entityID == 130 && $0.message.contains("Cyclic") })
        let curves = boxRecords().replacingOccurrences(of: "#30=LINE('',#1,#320);", with: "#30=SURFACE_CURVE('',#30,(),.CURVE_3D.);")
        #expect(try STEPEdgeImporter.parse(data: document(curves)).skippedEdgeCount == 1)
    }

    @Test func emptyGeometryHasNoInvalidBoundsAndAssembliesAreRejected() throws {
        let empty = try STEPEdgeImporter.parse(data: document("#1=CARTESIAN_POINT('',(0.,0.,0.));"))
        #expect(empty.bounds == nil)
        #expect(empty.edges.isEmpty)
        #expect(!empty.diagnostics.isEmpty)
        let assembly = boxRecords() + "\n#999=MAPPED_ITEM('',#998,#997);"
        #expect(throws: STEPParseError.self) { try STEPEdgeImporter.parse(data: document(assembly)) }
    }

    @Test func malformedRecordsFailWithoutTraps() throws {
        let invalid = [
            "#1=A(); #1=B();", "#0=A();", "#1=A('unterminated);", "/* unterminated",
            "#1=A((1.,2.);", "#1=A(1.E+);", "#1=A(1.E999);", "#1=();",
            "#1=A(" + String(repeating: "(", count: 130) + "1" + String(repeating: ")", count: 130) + ");"
        ]
        for records in invalid {
            #expect(throws: STEPParseError.self) { try STEPFile(data: document(records)) }
        }
        let invalidList = try STEPFile(data: document("#1=A(1,,2);"))
        #expect(throws: STEPParseError.self) { try invalidList.components(1) }
        #expect(throws: STEPParseError.self) { try STEPFile(data: Data("DATA;#1=A();ENDSEC;".utf8)) }
        #expect(throws: STEPParseError.self) { try STEPFile(data: document("#1=A();").dropLast(10)) }
    }

    @Test func fileEntryPointLoadsOffActorAndPreservesIdentity() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("step")
        defer { try? FileManager.default.removeItem(at: url) }
        try document(boxRecords()).write(to: url)
        let id = UUID()
        let model = try await STEPEdgeImporter.importFile(at: url, importID: id)
        #expect(model.importID == id)
        #expect(model.edges.count == 12)
    }

    @Test func cancellationIsNotConvertedToPartialGeometry() async throws {
        let data = document(boxRecords())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try STEPEdgeImporter.parse(data: data)
                Issue.record("Cancelled parse should throw")
            } catch is CancellationError { }
            do {
                _ = try await STEPEdgeImporter.importFile(at: URL(fileURLWithPath: "/does-not-exist.step"))
                Issue.record("Cancelled import should throw before file access")
            } catch is CancellationError { }
        }
        try await task.value
    }
}
