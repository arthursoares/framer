// FullscreenVertex.metal
// Single fullscreen-triangle vertex entry shared by every effect pipeline.
// Compiled once, bound by name (`fullscreenVertex`) from Swift when building
// a pipeline. Draw call: encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3).
//
// Why a triangle and not a quad: three vertices covering [-1, 3] × [-1, 3] in clip
// space fill the viewport exactly, at the cost of a few clipped fragments outside
// the screen. Simpler than a 4-vertex tri-strip and produces better cache locality
// at the triangle boundary. Standard fullscreen-shader pattern.

#include "ShaderCommon.h"

vertex VertexOut fullscreenVertex(uint vid [[vertex_index]]) {
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    float2 uvs[3]       = { float2(0,  1), float2(2,  1), float2(0, -1) };

    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv       = uvs[vid];
    return out;
}
