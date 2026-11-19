//
//  Shaders.metal
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
    // Multiplies the fragment alpha (hidden dotted edges are drawn at 0.5).
    float alpha;
    // Drawable size in pixels and line width in pixels. Only `vertex_thick` reads these.
    float2 viewport;
    float lineWidth;
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
    return float4(in.color.rgb, in.color.a * uniforms.alpha);
}

// MARK: - Thick lines
//
// Metal draws lines one pixel wide, so a wider line is built from a quad per segment. Draws a
// `.lineList` buffer as triangles: 6 vertices per segment, read straight from the same
// `RenderVertex` buffer the hairline path uses (no vertex descriptor). The quad is widened in
// screen space, so the width stays constant in pixels at any zoom, and each end is pushed out
// by half a width (square cap) so segments of a tessellated curve join without gaps.
// `dist` leaves here in screen pixels, so `fragment_main`'s dashing gives dots that keep their
// size on screen.

struct RawVertex {
    float3 position;
    float4 color;
    float  dist;
};

vertex VertexOutput vertex_thick(uint vid [[vertex_id]],
                                 const device RawVertex* vertices [[buffer(0)]],
                                 constant Uniforms& uniforms [[buffer(1)]]) {
    uint segment = vid / 6;
    uint corner = vid % 6;
    // Two triangles per segment: (a-, a+, b-) and (b-, a+, b+).
    bool atEnd = (corner == 2 || corner == 3 || corner == 5);
    float side = (corner == 1 || corner == 4 || corner == 5) ? 1.0 : -1.0;

    RawVertex a = vertices[segment * 2];
    RawVertex b = vertices[segment * 2 + 1];

    float4 clipA = uniforms.modelViewProjectionMatrix * float4(a.position + float3(uniforms.offset, 0.0), 1.0);
    float4 clipB = uniforms.modelViewProjectionMatrix * float4(b.position + float3(uniforms.offset, 0.0), 1.0);

    float2 halfViewport = uniforms.viewport * 0.5;
    float2 screenA = clipA.xy / clipA.w * halfViewport;
    float2 screenB = clipB.xy / clipB.w * halfViewport;

    float2 delta = screenB - screenA;
    float screenLength = length(delta);
    float2 direction = screenLength > 1e-4 ? delta / screenLength : float2(1.0, 0.0);
    float2 normal = float2(-direction.y, direction.x);

    float halfWidth = uniforms.lineWidth * 0.5;
    float along = atEnd ? halfWidth : -halfWidth;
    float2 pixelOffset = normal * side * halfWidth + direction * along;

    float4 clip = atEnd ? clipB : clipA;
    clip.xy += pixelOffset / halfViewport * clip.w;

    // Path distance in model units -> pixels, using this segment's own scale. The projection is
    // orthographic, so that scale is the same all along an edge and the pattern runs on
    // unbroken across its segments.
    float worldLength = length(b.position - a.position);
    float pixelsPerUnit = worldLength > 1e-6 ? screenLength / worldLength : 0.0;

    VertexOutput out;
    out.position = clip;
    out.color = atEnd ? b.color : a.color;
    out.dist = (atEnd ? b.dist : a.dist) * pixelsPerUnit + along;
    return out;
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
    // The stock's original top and bottom Z, and how much darker a point at
    // the bottom is than one at the top (0 = no depth shading). Lets the
    // fragment shader shade by depth of cut, so a carved floor reads as a
    // different shade than the uncut top even when looked at from straight
    // above, where the walls between them are edge-on and invisible.
    float topZ;
    float bottomZ;
    float depthDarkening;
    // XY shift added to every vertex before the MVP transform. Zero for the
    // heightmap surface itself (its offset is baked into the carved
    // vertices); non-zero for solids that follow the toolpath, i.e. the tool.
    float2 offset;
};

struct HeightmapVertexInput {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct HeightmapVertexOutput {
    float4 position [[position]];
    float3 worldNormal;
    float worldZ;
};

vertex HeightmapVertexOutput vertex_heightmap(HeightmapVertexInput in [[stage_in]],
                                              constant HeightmapUniforms& uniforms [[buffer(1)]]) {
    HeightmapVertexOutput out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position + float3(uniforms.offset, 0.0), 1.0);
    // `in.position` is already in world/machine space - this renderer has
    // no per-object model matrix (see Camera.swift: the MVP is view *
    // projection only) - so the normal needs no transform beyond carrying
    // it through for per-fragment interpolation.
    out.worldNormal = in.normal;
    out.worldZ = in.position.z;
    return out;
}

fragment float4 fragment_heightmap(HeightmapVertexOutput in [[stage_in]],
                                   constant HeightmapUniforms& uniforms [[buffer(1)]]) {
    float3 n = normalize(in.worldNormal);
    float diffuse = max(dot(n, normalize(uniforms.lightDirection)), 0.0);
    float lit = uniforms.ambient + (1.0 - uniforms.ambient) * diffuse;

    // A negative `depthDarkening` marks a coated tool (see `RenderObject.coatingZRange`):
    // `bottomZ`...`topZ` is the height range of its cutting part, and the surface is colored
    // by a smooth rainbow instead of `baseColor`. The rainbow runs up the tool, and its
    // position is warped by the angle around the axis (taken from the normal, which on a
    // lathe-turned tool points straight out from it), so the colors drift diagonally and
    // unevenly like the sheen of a real coating instead of lying in flat rings.
    if (uniforms.depthDarkening < 0.0) {
        float span = max(uniforms.topZ - uniforms.bottomZ, 0.001);
        float t = clamp((in.worldZ - uniforms.bottomZ) / span, 0.0, 1.0);
        float angle = atan2(n.y, n.x);
        float warp = 0.16 * sin(angle * 2.0 + t * 6.0)
                   + 0.10 * sin(angle * 3.0 - t * 11.0 + 1.7)
                   + 0.05 * sin(angle * 5.0 + t * 19.0 + 0.6);
        float h = t * 0.75 + warp;
        // Cosine palette: one smooth trip through the spectrum per unit of h
        float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (h + float3(0.0, 0.33, 0.67)));
        // Pull it a little toward gray: a coating is a metal, not a highlighter
        float gray = dot(rainbow, float3(0.299, 0.587, 0.114));
        rainbow = mix(float3(gray), rainbow, 0.85);
        return float4(rainbow * lit, uniforms.baseColor.a);
    }

    // Depth below the original top face, 0...1 of the stock's thickness.
    // Square root so the first millimeters of depth (where most pockets
    // live) darken noticeably instead of barely registering on thick
    // stock. Interpolates smoothly down a wall, which also grades it.
    float range = max(uniforms.topZ - uniforms.bottomZ, 0.001);
    float depth = clamp((uniforms.topZ - in.worldZ) / range, 0.0, 1.0);
    float depthShade = 1.0 - uniforms.depthDarkening * sqrt(depth);

    return float4(uniforms.baseColor.rgb * lit * depthShade, uniforms.baseColor.a);
}

// MARK: - GPU heightmap (carve + surface)
//
// The carve is a render pass, not a compute pass: every cutting segment is drawn as one
// instanced quad (its swept footprint), top-down, into a height texture. The fragment shader
// computes the exact height the tool leaves at that pixel and writes it both as colour and as
// depth; with a `less` depth test the hardware keeps the lowest one, which is what carving is
// ("a cell's height is the minimum any pass leaves it at"), in any draw order and with no atomics.
//
// The surface is then drawn from that texture: a static lattice of vertices whose height is read
// from it, with normals from neighbouring samples so the shading is smooth.
// Mirrors the structs of HeightmapGPU.swift byte-for-byte.

struct HMCarveParams {
    // Lower-left corner and size of the area the texture covers, in the stock's frame.
    float2 origin;
    float2 extent;
    // Added to every segment (the job's XY offset).
    float2 offset;
    // Stock bottom Z and thickness, to turn a height into a 0...1 depth.
    float bottomZ;
    float range;
};

struct HMCarveTool {
    float radius;
    // Rise per mm of radius for a cone (1 / tan(half angle)).
    float coneSlope;
    // 0 flat, 1 ball, 2 cone.
    uint kind;
    uint padding;
};

struct HMCarveInstance {
    // xyz = start, w = index into the tool table.
    float4 a;
    // xyz = end.
    float4 b;
};

struct HMCarveVertexOut {
    float4 position [[position]];
    float2 world;
    float3 start [[flat]];
    float3 end [[flat]];
    uint tool [[flat]];
};

vertex HMCarveVertexOut vertex_hmcarve(uint vid [[vertex_id]],
                                       uint iid [[instance_id]],
                                       constant HMCarveParams& p [[buffer(0)]],
                                       constant HMCarveInstance* instances [[buffer(1)]],
                                       constant HMCarveTool* tools [[buffer(2)]]) {
    HMCarveInstance inst = instances[iid];
    uint toolIndex = uint(inst.a.w);
    float radius = tools[toolIndex].radius;

    float2 a = inst.a.xy + p.offset;
    float2 b = inst.b.xy + p.offset;
    float2 travel = b - a;
    float len = length(travel);
    float2 dir = len > 1e-6 ? travel / len : float2(1.0, 0.0);
    float2 perp = float2(-dir.y, dir.x);

    // Triangle strip over the rectangle around the segment, one radius wider on every side.
    float along = vid < 2 ? -radius : len + radius;
    float across = (vid & 1) == 0 ? -radius : radius;
    float2 world = a + dir * along + perp * across;

    // Row 0 of the texture is the lowest Y, so the surface can read (col, row) directly.
    float2 uv = (world - p.origin) / p.extent;

    HMCarveVertexOut out;
    out.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    out.world = world;
    out.start = float3(a, inst.a.z);
    out.end = float3(b, inst.b.z);
    out.tool = toolIndex;
    return out;
}

struct HMCarveOut {
    float4 height [[color(0)]];
    float depth [[depth(any)]];
};

// Same maths as ToolFootprint.surfaceZ / HeightmapGrid.carve, per pixel.
fragment HMCarveOut fragment_hmcarve(HMCarveVertexOut in [[stage_in]],
                                     constant HMCarveParams& p [[buffer(0)]],
                                     constant HMCarveTool* tools [[buffer(2)]]) {
    HMCarveTool tool = tools[in.tool];

    float2 a = in.start.xy;
    float2 travel = in.end.xy - a;
    float lengthSquared = dot(travel, travel);
    float t;
    if (lengthSquared > 0.0) {
        t = clamp(dot(in.world - a, travel) / lengthSquared, 0.0, 1.0);
    } else {
        // A plunge has no XY travel: its deepest end decides.
        t = in.end.z < in.start.z ? 1.0 : 0.0;
    }
    float d = distance(in.world, a + travel * t);
    if (d > tool.radius) {
        discard_fragment();
    }

    float tipZ = mix(in.start.z, in.end.z, t);
    float z = tipZ;
    if (tool.kind == 1) {
        float clamped = min(d, tool.radius);
        z = tipZ + tool.radius - sqrt(max(tool.radius * tool.radius - clamped * clamped, 0.0));
    } else if (tool.kind == 2) {
        z = tipZ + d * tool.coneSlope;
    }

    HMCarveOut out;
    out.height = float4(z, 0.0, 0.0, 0.0);
    // Lower Z, smaller depth, wins the `less` test. The uncut top is depth 1, which nothing
    // at or above the stock's top can beat.
    out.depth = clamp((z - p.bottomZ) / p.range, 0.0, 1.0);
    return out;
}

struct HMSurfaceParams {
    // Lattice samples along X and Y (one more than the cells), and the world distance between them.
    uint columns;
    uint rows;
    float2 spacing;
};

static float hm_height(texture2d<float, access::read> hm, uint col, uint row, float bottomZ) {
    return max(hm.read(uint2(col, row)).r, bottomZ);
}

// One vertex per height sample, placed from its index alone; indexed by a static index buffer.
vertex HeightmapVertexOutput vertex_heightmap_surface(uint vid [[vertex_id]],
                                                      constant HeightmapUniforms& uniforms [[buffer(1)]],
                                                      constant HMSurfaceParams& s [[buffer(2)]],
                                                      texture2d<float, access::read> hm [[texture(0)]]) {
    uint col = vid % s.columns;
    uint row = vid / s.columns;
    float bottomZ = uniforms.bottomZ;

    float z = hm_height(hm, col, row, bottomZ);

    // Normal from the neighbouring samples. Across a step the slope is huge, so the normal
    // lies flat and the wall shades like a wall; elsewhere it follows the surface smoothly.
    uint c0 = col > 0 ? col - 1 : col;
    uint c1 = col + 1 < s.columns ? col + 1 : col;
    uint r0 = row > 0 ? row - 1 : row;
    uint r1 = row + 1 < s.rows ? row + 1 : row;
    float dzdx = (hm_height(hm, c1, row, bottomZ) - hm_height(hm, c0, row, bottomZ)) / (float(c1 - c0) * s.spacing.x);
    float dzdy = (hm_height(hm, col, r1, bottomZ) - hm_height(hm, col, r0, bottomZ)) / (float(r1 - r0) * s.spacing.y);

    float3 position = float3(float(col) * s.spacing.x, float(row) * s.spacing.y, z);

    HeightmapVertexOutput out;
    out.position = uniforms.modelViewProjectionMatrix * float4(position + float3(uniforms.offset, 0.0), 1.0);
    out.worldNormal = normalize(float3(-dzdx, -dzdy, 1.0));
    out.worldZ = z;
    return out;
}

// The four sides of the stock, from the carved edge down to the bottom, and the bottom face.
// Quads 0..<nx south, then east, north, west; the last one is the bottom.
vertex HeightmapVertexOutput vertex_heightmap_skirt(uint vid [[vertex_id]],
                                                    constant HeightmapUniforms& uniforms [[buffer(1)]],
                                                    constant HMSurfaceParams& s [[buffer(2)]],
                                                    texture2d<float, access::read> hm [[texture(0)]]) {
    uint quad = vid / 6;
    uint corner = vid % 6;
    // Two triangles over the corners 0 (i, top), 1 (i, bottom), 2 (i+1, bottom), 3 (i+1, top).
    uint k = corner == 0 ? 0 : (corner == 1 ? 1 : (corner == 2 ? 2 : (corner == 3 ? 0 : (corner == 4 ? 2 : 3))));
    uint along = k >= 2 ? 1 : 0;
    bool isTop = (k == 0 || k == 3);

    uint nx = s.columns - 1;
    uint ny = s.rows - 1;
    float bottomZ = uniforms.bottomZ;
    float width = float(nx) * s.spacing.x;
    float height = float(ny) * s.spacing.y;

    float3 position;
    float3 normal;

    if (quad >= 2 * nx + 2 * ny) {
        // Bottom face.
        float x = (k == 2 || k == 3) ? width : 0.0;
        float y = (k == 1 || k == 2) ? height : 0.0;
        position = float3(x, y, bottomZ);
        normal = float3(0.0, 0.0, -1.0);
    } else {
        uint col;
        uint row;
        uint q = quad;
        if (q < nx) {
            col = q + along;
            row = 0;
            normal = float3(0.0, -1.0, 0.0);
        } else if (q < nx + ny) {
            q -= nx;
            col = nx;
            row = q + along;
            normal = float3(1.0, 0.0, 0.0);
        } else if (q < 2 * nx + ny) {
            q -= nx + ny;
            col = q + along;
            row = ny;
            normal = float3(0.0, 1.0, 0.0);
        } else {
            q -= 2 * nx + ny;
            col = 0;
            row = q + along;
            normal = float3(-1.0, 0.0, 0.0);
        }
        float z = isTop ? hm_height(hm, col, row, bottomZ) : bottomZ;
        position = float3(float(col) * s.spacing.x, float(row) * s.spacing.y, z);
    }

    HeightmapVertexOutput out;
    out.position = uniforms.modelViewProjectionMatrix * float4(position + float3(uniforms.offset, 0.0), 1.0);
    out.worldNormal = normal;
    out.worldZ = position.z;
    return out;
}
