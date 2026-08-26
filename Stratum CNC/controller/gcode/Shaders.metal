//
//  VertexOut.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

#include <metal_stdlib>

using namespace metal;

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut line_vertex(
    const device float3 *vertices [[buffer(0)]],
    constant float4x4 &viewMatrix [[buffer(1)]],
    constant float4x4 &projectionMatrix [[buffer(2)]],
    uint vertexID [[vertex_id]]
) {
    VertexOut out;

    float4 position =
        float4(vertices[vertexID], 1.0);

    out.position =
        projectionMatrix *
        viewMatrix *
        position;

    return out;
}

fragment float4 line_fragment(
    constant float4 &color [[buffer(0)]]
) {
    return color;
}
