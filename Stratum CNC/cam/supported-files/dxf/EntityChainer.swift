//
//  EntityChainer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import Foundation
import SwiftDXF

enum EntityChainer {

    static func chain(_ entities: [DXF.Entity], tolerance: Double = 1e-3) -> [Contour] {
        var remaining = entities.map { (entity: $0, used: false) }
        var contours: [Contour] = []

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
                    
                default: return nil // circles/points/text/dimension: standalone
            }
        }

        func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
            hypot(a.x - b.x, a.y - b.y) <= tolerance
        }

        for startIndex in remaining.indices {
            guard !remaining[startIndex].used, let (s0, e0) = endpoints(remaining[startIndex].entity) else {
                continue
            }
            if remaining[startIndex].used {
                continue
            }

            var chain: [DXF.Entity] = [remaining[startIndex].entity]
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
                        chain.append(remaining[i].entity)
                        remaining[i].used = true
                        tail = b
                        extended = true
                        break
                    } else if close(tail, b) {
                        chain.append(remaining[i].entity.reversed())
                        remaining[i].used = true
                        tail = a
                        extended = true
                        break
                    }
                }
            }

            contours.append(Contour(entities: chain, isClosed: close(tail, s0)))
        }

        // Anything without endpoints (circle, point, text) becomes its own single-entity contour
        for i in remaining.indices where !remaining[i].used {
            contours.append(Contour(entities: [remaining[i].entity], isClosed: true))
            remaining[i].used = true
        }

        return contours
    }
}
