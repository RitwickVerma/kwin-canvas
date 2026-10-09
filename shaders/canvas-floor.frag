// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The canvas floor: the plane at rest, as a place of light. A deep
// flowing field - the domain-warped fbm breathing in the canvas's own
// blues - with the canvas's remembered state living on it: the rooms
// glow where the clusters sit, each on its own slow beat, the real
// windows cast their faint light where they stand, and the pointer's
// light follows the hand. No graph paper: the floor is an atmosphere,
// and the canvas's state is the light in it.
//
// The canvas uniforms below are fed from the kwin-canvas passthrough
// plugin's state file (kwin-canvas-state.txt) by the engine's fork; the
// engine's own iMouse, iScreenOffset and the iWindow* set cover the
// hand and the windows. See docs/shader-integration.md for the channel
// and the fork contract. Absent the fork the uniforms read zero and the
// floor is simply the calm field.
//
// @channels none

uniform int iCanvasClusterCount;   // up to 16, the plane's clusters
uniform vec4 iCanvasClusters[16];  // x,y = the screen centre, z = the member count
uniform vec3 iCanvasBackground;    // the plane's ground, 0..1
uniform vec2 iCanvasView;          // the plane coordinate of the screen's top-left

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i), f),
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.02 + vec2(7.1, 3.7);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    // The plane coordinate under this pixel, for the field's drift.
    vec2 plane = fragCoord + iCanvasView;
    float t = iTime;

    // The deep floor: the canvas's own background, deepened toward the
    // bottom of the screen.
    vec3 col = mix(iCanvasBackground * 0.35, iCanvasBackground * 0.85, uv.y);

    // The flowing field: the domain-warped fbm - the nebula's slow
    // breath, in the canvas's own blues with a warm violet at the
    // crests. Layered time scales, so the motion reads as weather.
    vec2 q = vec2(fbm(plane * 0.0016 + vec2(0.0, t * 0.03)),
                  fbm(plane * 0.0016 + vec2(5.2, 1.3) - vec2(0.0, t * 0.025)));
    vec2 r = vec2(fbm(plane * 0.0021 + 3.5 * q + vec2(1.7, 9.2) + t * 0.015),
                  fbm(plane * 0.0021 + 3.5 * q + vec2(8.3, 2.8) - t * 0.012));
    float f = fbm(plane * 0.0028 + 2.6 * r);
    vec3 nebula = mix(vec3(0.10, 0.16, 0.34), vec3(0.22, 0.30, 0.52),
                      clamp(f * f * 2.5 + 0.5 * r.y, 0.0, 1.0));
    nebula = mix(nebula, vec3(0.62, 0.45, 0.62),
                 clamp(r.x * r.x * 1.2, 0.0, 1.0) * 0.35);
    col += nebula * 0.85;

    // The rooms: the clusters are pools of light breathing on the field
    // - the cool halo and the warm heart trading on each room's beat.
    for (int i = 0; i < iCanvasClusterCount && i < 16; i++) {
        vec2 c = iCanvasClusters[i].xy;
        float n = max(iCanvasClusters[i].z, 1.0);
        float beat = sin(t * 0.6 + float(i) * 1.618) * 0.5 + 0.5;
        float r1 = (90.0 + 30.0 * n) * (0.8 + 0.4 * beat);
        float dist = length(fragCoord - c);
        float glow = exp(-(dist * dist) / (2.0 * r1 * r1));
        float heart = exp(-(dist * dist) / (2.0 * r1 * r1 * 0.09));
        col += vec3(0.35, 0.55, 1.0) * glow * (0.20 + 0.20 * beat);
        col += vec3(1.0, 0.94, 0.85) * heart * (0.30 + 0.25 * beat);
    }

    // The windows: the faint light where the real windows stand.
    for (int i = 0; i < iWindowCount && i < 16; i++) {
        vec4 w = iWindowRects[i];
        vec2 c = w.xy + w.zw * 0.5;
        float md = length(fragCoord - c);
        float rr = max(w.z, w.w) * 0.8;
        col += vec3(0.45, 0.6, 0.95) * exp(-md * md / (2.0 * rr * rr)) * 0.05;
    }

    // The hand: the pointer's light, aligned to this screen (the
    // engine's iMouse is the global desktop position; this screen's
    // offset brings it home).
    vec2 m = iMouse.xy - iScreenOffset;
    if (m.x > 0.5 || m.y > 0.5) {
        float md = length(fragCoord - m);
        col += vec3(0.9, 0.85, 0.7) * exp(-md * md / (2.0 * 120.0 * 120.0)) * 0.08;
        col += vec3(1.0, 0.98, 0.9) * exp(-md * md / (2.0 * 30.0 * 30.0)) * 0.04;
    }

    // The slow breath over the whole.
    col *= 0.96 + 0.04 * sin(t * 0.35);

    fragColor = vec4(col, 1.0);
}
