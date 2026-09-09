//
//  GerberImporter.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//


import Foundation

final class GerberImporter: Importer {

    private let factory = ObjectFactory()

    func parse(url: URL) -> D2_Object? {

        guard let result = try? GerberParser.parseArchive(url: url) else {
            return nil
        }

        let entities = result.entities

        print("Gerber files: \(result.fileCount)")
        print("Gerber entities: \(entities.count)")

        // Reuse the same contour-building pipeline as DXF.
        let contours = EntityChainer.chain(entities)

        var paths: [STBezierPath] = []

        for contour in contours {

            let path = STBezierPath()

            for (index, chained) in contour.entities.enumerated() {
                chained.entity.appendTo(
                    path,
                    isFirst: index == 0,
                    reversed: chained.reversed
                )
            }

            if contour.isClosed {
                path.close()
            }

            guard path.elementCount > 0 else {
                continue
            }

            paths.append(path)
        }

        return factory.makeObject(
            name: url.deletingPathExtension().lastPathComponent,
            paths: paths,
            entities: entities
        )
    }
}