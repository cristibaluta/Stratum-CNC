//
//  GerberImporter.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import Foundation
import SwiftDXF

final class GerberImporter: Importer {

    private let factory = ObjectFactory()

    func parse(url: URL) -> D2_Object? {
        return nil
    }

    func parse(url: URL) -> [D2_Object] {

        guard let result = try? GerberParser.parseArchive(url: url) else {
            return []
        }

        var objects: [D2_Object] = []
        objects.reserveCapacity(result.files.count)

        for file in result.files {

            let entities = file.entities
            let contours = EntityChainer.chain(entities)

            var paths: [STBezierPath] = []

            for contour in contours {

                let path = STBezierPath()

                for (index, chained) in contour.entities.enumerated() {
                    chained.entity.appendTo(path, isFirst: index == 0, reversed: chained.reversed)
                }

                if contour.isClosed {
                    path.close()
                }

                guard path.elementCount > 0 else {
                    continue
                }

                paths.append(path)
            }

            guard !paths.isEmpty else {
                continue
            }

            if let object = factory.makeObject(name: file.name, paths: paths, entities: entities) {
                objects.append(object)
            }
        }

        print("Gerber files: \(objects.count)")

        return objects
    }
}
