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
    // XY offset added to position in model space, before the MVP transform.
    // Zero for every batch except the toolpath rapid/cutting draws - see
    // MetalRenderer.drawBatch - so the stock box, tool marker, and axes
    // never move while the toolpath preview does.
    float2 offset;
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
    float3 offsetPosition = in.position + float3(uniforms.offset, 0.0);
    out.position = uniforms.modelViewProjectionMatrix * float4(offsetPosition, 1.0);
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

// MARK: - Heightmap (2.5D stock preview)
//
// A separate, much simpler pipeline from the line pass above: solid shaded
// triangles instead of dashable lines, so there's no `dist`/discard logic
// here at all. Mirrors `HeightmapUniforms` / `HeightmapMesh.Vertex` in
// MetalRenderer.swift and HeightmapMesh.swift byte-for-byte.

struct HeightmapUniforms {
    float4x4 modelViewProjectionMatrix;
    // Direction FROM a lit point on the surface TOWARD the light - i.e.
    // already the vector `dot()` below wants, not the light's direction of
    // travel. Doesn't need to arrive pre-normalized; the fragment shader
    // normalizes it.
    float3 lightDirection;
    float4 baseColor;
    // Fraction of `baseColor` that shows even where the surface faces
    // fully away from the light (0 = unlit side is pure black, 1 = no
    // shading at all). Keeps the carved shape legible without needing a
    // second light or real ambient occlusion yet.
    float ambient;
};

struct HeightmapVertexInput {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct HeightmapVertexOutput {
    float4 position [[position]];
    float3 worldNormal;
};

vertex HeightmapVertexOutput vertex_heightmap(HeightmapVertexInput in [[stage_in]],
                                              constant HeightmapUniforms& uniforms [[buffer(1)]]) {
    HeightmapVertexOutput out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    // `in.position` is already in world/machine space - this renderer has
    // no per-object model matrix (see Camera.swift: the MVP is view *
    // projection only) - so the normal needs no transform beyond carrying
    // it through for per-fragment interpolation.
    out.worldNormal = in.normal;
    return out;
}

fragment float4 fragment_heightmap(HeightmapVertexOutput in [[stage_in]],
                                   constant HeightmapUniforms& uniforms [[buffer(1)]]) {
    float3 n = normalize(in.worldNormal);
    float diffuse = max(dot(n, normalize(uniforms.lightDirection)), 0.0);
    float lit = uniforms.ambient + (1.0 - uniforms.ambient) * diffuse;
    return float4(uniforms.baseColor.rgb * lit, uniforms.baseColor.a);
}
