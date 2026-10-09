// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The canvas floor: the starter shader for the shader wallpaper's engine
// (kde-shader-wallpaper, Shadertoy conventions). The plane's remembered
// state - the ground's own knobs, the clusters and the day-trail -
// arrives through the uniforms below, fed from the kwin-canvas
// passthrough plugin's state file (kwin-canvas-state.txt) by the
// engine's fork; see docs/shader-integration.md for the channel and the
// fork contract.
//
// The closed desktop is the plane at rest: the shader draws the same
// ground the canvas draws - the background colour and the multi-octave
// grid, scrolling with the saved view - then lights the clusters where
// the rooms sit and runs the day-trail through it as a faint ribbon.
// With the fork absent the uniforms read zero and the floor is simply
// the grid on the background.
//
// @channels none

uniform int iCanvasClusterCount;   // up to 16, the plane's clusters
uniform vec4 iCanvasClusters[16];  // x,y = the screen centre, z = the member count
uniform int iCanvasTrailCount;     // up to 64, the day-trail's samples
uniform vec2 iCanvasTrail[64];     // the screen path points, oldest first
uniform float iCanvasGridBase;     // the minor grid spacing, plane pixels
uniform float iCanvasGridFactor;   // each octave is this many times coarser
uniform float iCanvasGridOctaves;  // the octaves drawn
uniform vec3 iCanvasGridColor;     // the line colour, 0..1
uniform vec3 iCanvasBackground;    // the plane's ground, 0..1
uniform vec2 iCanvasView;          // the plane coordinate of the screen's top-left

float glow(vec2 p, vec2 c, float r) {
    return exp(-dot(p - c, p - c) / (r * r));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // The plane coordinate under this pixel: the screen is the plane
    // minus the view, so the plane is the screen plus the view.
    vec2 plane = fragCoord + iCanvasView;

    // The ground: the plane's own background, a little lighter above.
    vec3 col = mix(iCanvasBackground * 0.55, iCanvasBackground * 1.15, uv.y);

    // The grid: the same octaves the canvas draws, scrolling with the
    // view. The coarser an octave, the stronger its lines. Absent the
    // fork the base reads zero and the grid stays out of the way.
    float spacing = max(iCanvasGridBase, 1.0);
    if (iCanvasGridBase > 4.0) {
        for (int o = 0; o < 4; o++) {
            if (float(o) >= iCanvasGridOctaves) break;
            vec2 m = mod(plane, spacing);
            vec2 d = min(m, spacing - m);
            float g = 1.0 - smoothstep(0.0, 1.4 + 0.5 * float(o), min(d.x, d.y));
            float w = 0.10 + 0.22 * float(o);
            col = mix(col, iCanvasGridColor, g * w);
            spacing *= max(iCanvasGridFactor, 2.0);
        }
    }

    // The clusters light the floor where the plane's rooms sit.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec2 c = iCanvasClusters[i].xy;
        float n = max(iCanvasClusters[i].z, 1.0);
        float r = 60.0 + 22.0 * n;
        float bloom = glow(fragCoord, c, r) * 0.45;
        float core = glow(fragCoord, c, r * 0.35) * 0.22;
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
        tglow += exp(-d * d / (7.0 * 7.0)) * 0.30;
    }
    col += iCanvasGridColor * 1.4 * tglow;

    // A slow breathing light, so the floor lives even at rest.
    col *= 0.97 + 0.03 * sin(iTime * 0.4);

    fragColor = vec4(col, 1.0);
}
