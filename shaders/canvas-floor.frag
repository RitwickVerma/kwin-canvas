// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The canvas floor: the starter shader for the shader wallpaper's engine
// (kde-shader-wallpaper, Shadertoy conventions). The plane's remembered
// state - the clusters and the day-trail - arrives through the uniforms
// below, fed from the kwin-canvas passthrough plugin's state file
// (kwin-canvas-state.txt) by the engine's fork; see
// docs/shader-integration.md for the channel and the fork contract.
//
// At rest the floor is a deep calm; the clusters light it where the
// plane's rooms sit (the glow grows with the room's windows), and the
// day-trail runs through it as a faint ribbon of light. With the fork
// absent the uniforms read zero and the floor is simply the calm.
//
// @channels none

uniform int iCanvasClusterCount;   // up to 16, the plane's clusters
uniform vec4 iCanvasClusters[16];  // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;     // up to 64, the day-trail's samples
uniform vec2 iCanvasTrail[64];     // the screen path points, oldest first

float glow(vec2 p, vec2 c, float r) {
    return exp(-dot(p - c, p - c) / (r * r));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // The floor: a deep calm, lighter toward the top of the screen.
    vec3 col = mix(vec3(0.055, 0.06, 0.09), vec3(0.10, 0.11, 0.16), uv.y);

    // The clusters light the floor where the plane's rooms sit.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec2 c = iCanvasClusters[i].xy;
        float n = max(iCanvasClusters[i].z, 1.0);
        float r = 60.0 + 22.0 * n;
        float bloom = glow(fragCoord, c, r) * 0.55;
        float core = glow(fragCoord, c, r * 0.35) * 0.25;
        col += vec3(0.35, 0.55, 1.0) * bloom + vec3(1.0, 0.95, 0.9) * core;
    }

    // The day-trail: a faint ribbon of light along the path.
    float tglow = 0.0;
    for (int i = 0; i < iCanvasTrailCount - 1 && i < 63; i++) {
        vec2 a = iCanvasTrail[i];
        vec2 b = iCanvasTrail[i + 1];
        vec2 pa = fragCoord - a;
        vec2 ba = b - a;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1.0), 0.0, 1.0);
        float d = length(pa - ba * h);
        tglow += exp(-d * d / (7.0 * 7.0)) * 0.28;
    }
    col += vec3(0.55, 0.65, 0.9) * tglow;

    // A slow breathing light, so the floor lives even at rest.
    col *= 0.97 + 0.03 * sin(iTime * 0.4);

    fragColor = vec4(col, 1.0);
}
