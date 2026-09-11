//
//  EntityChainer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import Foundation
import SwiftDXF
import StratumCAM

enum EntityChainer {

    static func chain(_ entities: [DXF.Entity], tolerance: Double = 1e-3) -> [SC.Contour] {
        var remaining = entities.map { (entity: $0, used: false) }
        var contours: [SC.Contour] = []

        func endpoints(_ e: DXF.Entity) -> (CGPoint, CGPoint)? {
            switch e {
                case let .line(a, b, _, _):
                    return (a.cgPoint, b.cgPoint)

                case let .polyline(vertices, _, _, _):
                    guard let f = vertices.first, let l = vertices.last else {
                        return nil
                    }
                    return (f.point.cgPoint, l.point.cgPoint)

                case let .arc(center, r, start, end, _, _):
                    let s = CGPoint(x: center.x + r*cos(start * .pi/180), y: center.y + r*sin(start * .pi/180))
                    let e2 = CGPoint(x: center.x + r*cos(end * .pi/180), y: center.y + r*sin(end * .pi/180))
                    return (s, e2)

                default: return nil // circles/points/text/ellipse/dimension: standalone
            }
        }

        func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
            hypot(a.x - b.x, a.y - b.y) <= tolerance
        }

        for startIndex in remaining.indices {
            guard !remaining[startIndex].used, let (s0, e0) = endpoints(remaining[startIndex].entity) else {
                continue
            }

            var chain: [SC.Contour.Chained] = [SC.Contour.Chained(entity: remaining[startIndex].entity, reversed: false)]
            remaining[startIndex].used = true
            var tail = e0

            var extended = true
            while extended {
                extended = false
                for i in remaining.indices where !remaining[i].used {
                    guard let (a, b) = endpoints(remaining[i].entity) else {
                        continue
                    }
                    if close(tail, a) {
                        chain.append(SC.Contour.Chained(entity: remaining[i].entity, reversed: false))
                        remaining[i].used = true
                        tail = b
                        extended = true
                        break
                    } else if close(tail, b) {
                        chain.append(SC.Contour.Chained(entity: remaining[i].entity, reversed: true))
                        remaining[i].used = true
                        tail = a
                        extended = true
                        break
                    }
                }
            }

            contours.append(
                SC.Contour(entities: chain, isClosed: close(tail, s0))
            )
        }

        for i in remaining.indices where !remaining[i].used {
            contours.append(
                SC.Contour(entities: [SC.Contour.Chained(entity: remaining[i].entity, reversed: false)], isClosed: true)
            )
            remaining[i].used = true
        }

        return contours
    }
}
