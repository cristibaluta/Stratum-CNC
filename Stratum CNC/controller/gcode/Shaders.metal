//
//  VertexOut.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float dashLength; // > 0 enables dashing (e.g., 5.0), 0 = solid line
};

struct VertexInput {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
    float  dist     [[attribute(2)]]; // Accumulated path distance
};

struct VertexOutput {
    float4 position [[position]];
    float4 color;
    float  dist;
};

vertex VertexOutput vertex_main(VertexInput in [[stage_in]], constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOutput out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.color = in.color;
    out.dist = in.dist;
    return out;
}

fragment float4 fragment_main(VertexOutput in [[stage_in]], constant Uniforms& uniforms [[buffer(1)]]) {
    if (uniforms.dashLength > 0.0) {
        // Evaluate dash/gap state along the segment distance
        float pattern = fmod(in.dist, uniforms.dashLength * 2.0);
        if (pattern > uniforms.dashLength) {
            discard_fragment(); // Skip rendering the "gap"
        }
    }
    return in.color;
}
